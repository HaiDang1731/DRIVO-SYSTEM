using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using DrivoApi.Application.DTOs.Auth;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.Services;
using DrivoApi.Application.Settings;
using DrivoApi.Domain.Entities;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace DrivoApi.Infrastructure;

public class AuthService(DrivoDbContext db, IOptions<JwtSettings> jwtOptions) : IAuthService
{
    private readonly JwtSettings _jwt = jwtOptions.Value;
    private const int Pbkdf2Iterations = 350_000;

    // ── Register ───────────────────────────────────────────────
    public async Task<BaseResponse<AuthResponse>> RegisterAsync(RegisterRequest req)
    {
        // Validate role
        var role = req.Role.ToUpper();
        if (role != "CUSTOMER" && role != "DRIVER")
            return BaseResponse<AuthResponse>.Fail("Role không hợp lệ. Chọn CUSTOMER hoặc DRIVER.");

        // Check phone unique
        if (await db.Users.AnyAsync(u => u.Phone == req.Phone && !u.IsDeleted))
            return BaseResponse<AuthResponse>.Fail("Số điện thoại đã được đăng ký.");

        // Check email unique
        if (!string.IsNullOrEmpty(req.Email) &&
            await db.Users.AnyAsync(u => u.Email == req.Email && !u.IsDeleted))
            return BaseResponse<AuthResponse>.Fail("Email đã được đăng ký.");

        // Find role record
        var roleRecord = await db.Roles.FirstOrDefaultAsync(r => r.Name == role);
        if (roleRecord == null)
            return BaseResponse<AuthResponse>.Fail($"Role {role} không tồn tại trong hệ thống.");

        await using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            // Create User
            var user = new User
            {
                FullName = req.FullName.Trim(),
                Phone = req.Phone.Trim(),
                Email = req.Email?.Trim().ToLower(),
                Status = UserStatus.Active,
                CreatedAt = DateTime.UtcNow
            };
            user.PasswordHash = HashPassword(req.Password);
            db.Users.Add(user);
            await db.SaveChangesAsync();

            // Assign role
            db.UserRoles.Add(new UserRole
            {
                UserId = user.Id,
                RoleId = roleRecord.Id,
                AssignedAt = DateTime.UtcNow
            });

            // Create profile record
            if (role == "CUSTOMER")
            {
                db.Customers.Add(new Customer
                {
                    UserId = user.Id,
                    CreatedAt = DateTime.UtcNow
                });
            }
            else // DRIVER
            {
                db.Drivers.Add(new Driver
                {
                    UserId = user.Id,
                    LicenseNumber = $"PENDING_{user.Id}_{DateTime.UtcNow.Ticks}",
                    VerificationStatus = VerificationStatus.Pending,
                    DriverStatus = DriverStatus.Offline,
                    CreatedAt = DateTime.UtcNow
                });
            }

            await db.SaveChangesAsync();
            await transaction.CommitAsync();

            // Generate tokens
            var tokens = await GenerateAndSaveTokensAsync(user, [role]);
            return BaseResponse<AuthResponse>.Ok(tokens, "Đăng ký thành công!");
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }

    // ── Login ──────────────────────────────────────────────────
    public async Task<BaseResponse<AuthResponse>> LoginAsync(LoginRequest req)
    {
        User? user = null;
        if (!string.IsNullOrEmpty(req.Email))
        {
            user = await db.Users
                .Include(u => u.UserRoles).ThenInclude(ur => ur.Role)
                .FirstOrDefaultAsync(u => u.Email == req.Email && !u.IsDeleted);
        }
        else if (!string.IsNullOrEmpty(req.Phone))
        {
            user = await db.Users
                .Include(u => u.UserRoles).ThenInclude(ur => ur.Role)
                .FirstOrDefaultAsync(u => u.Phone == req.Phone && !u.IsDeleted);
        }

        if (user == null)
            return BaseResponse<AuthResponse>.Fail("Số điện thoại hoặc mật khẩu không đúng.");

        if (user.Status == UserStatus.Locked)
            return BaseResponse<AuthResponse>.Fail("Tài khoản của bạn đã bị khóa.");

        if (user.Status == UserStatus.Inactive)
            return BaseResponse<AuthResponse>.Fail("Tài khoản chưa được kích hoạt.");

        var verifyResult = VerifyPassword(req.Password, user.PasswordHash);
        if (!verifyResult)
            return BaseResponse<AuthResponse>.Fail("Số điện thoại hoặc mật khẩu không đúng.");

        // Update last login
        user.LastLoginAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        var roles = user.UserRoles.Select(ur => ur.Role.Name).ToList();
        var tokens = await GenerateAndSaveTokensAsync(user, roles);
        return BaseResponse<AuthResponse>.Ok(tokens, "Đăng nhập thành công!");
    }

    // ── Refresh Token ──────────────────────────────────────────
    public async Task<BaseResponse<AuthResponse>> RefreshTokenAsync(string refreshToken)
    {
        var tokenHash = HashToken(refreshToken);

        var stored = await db.RefreshTokens
            .Include(t => t.User)
                .ThenInclude(u => u.UserRoles)
                    .ThenInclude(ur => ur.Role)
            .FirstOrDefaultAsync(t => t.TokenHash == tokenHash);

        if (stored == null || !stored.IsActive)
            return BaseResponse<AuthResponse>.Fail("Refresh token không hợp lệ hoặc đã hết hạn.");

        if (stored.User.IsDeleted || stored.User.Status == UserStatus.Locked)
            return BaseResponse<AuthResponse>.Fail("Tài khoản không hợp lệ.");

        // Revoke old token (rotation)
        stored.RevokedAt = DateTime.UtcNow;

        var roles = stored.User.UserRoles.Select(ur => ur.Role.Name).ToList();
        var newTokens = await GenerateAndSaveTokensAsync(stored.User, roles);

        // Link old → new
        var newStored = await db.RefreshTokens
            .OrderByDescending(t => t.CreatedAt)
            .FirstOrDefaultAsync(t => t.UserId == stored.UserId && t.RevokedAt == null);

        if (newStored != null)
            stored.ReplacedByTokenId = newStored.Id;

        await db.SaveChangesAsync();
        return BaseResponse<AuthResponse>.Ok(newTokens, "Token đã được làm mới.");
    }

    // ── Logout ─────────────────────────────────────────────────
    public async Task<BaseResponse<bool>> LogoutAsync(string refreshToken)
    {
        var tokenHash = HashToken(refreshToken);
        var stored = await db.RefreshTokens
            .FirstOrDefaultAsync(t => t.TokenHash == tokenHash);

        if (stored == null || stored.RevokedAt != null)
            return BaseResponse<bool>.Ok(true, "Đã đăng xuất.");

        stored.RevokedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return BaseResponse<bool>.Ok(true, "Đăng xuất thành công!");
    }

    // ── Private Helpers ────────────────────────────────────────
    private async Task<AuthResponse> GenerateAndSaveTokensAsync(User user, List<string> roles)
    {
        var accessToken = GenerateAccessToken(user, roles);
        var (refreshTokenRaw, refreshTokenHash) = GenerateRefreshToken();
        var expiresAt = DateTime.UtcNow.AddMinutes(_jwt.AccessTokenExpiryMinutes);

        db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.Id,
            TokenHash = refreshTokenHash,
            ExpiresAt = DateTime.UtcNow.AddDays(_jwt.RefreshTokenExpiryDays),
            CreatedAt = DateTime.UtcNow
        });
        await db.SaveChangesAsync();

        return new AuthResponse
        {
            AccessToken = accessToken,
            RefreshToken = refreshTokenRaw,
            AccessTokenExpiresAt = expiresAt,
            User = new UserInfo
            {
                Id = user.Id,
                FullName = user.FullName,
                Phone = user.Phone,
                Email = user.Email,
                AvatarUrl = user.AvatarUrl,
                Roles = roles
            }
        };
    }

    private string GenerateAccessToken(User user, List<string> roles)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_jwt.SecretKey));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new("phone", user.Phone),
            new("fullName", user.FullName)
        };
        claims.AddRange(roles.Select(r => new Claim(ClaimTypes.Role, r)));

        var token = new JwtSecurityToken(
            issuer: _jwt.Issuer,
            audience: _jwt.Audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_jwt.AccessTokenExpiryMinutes),
            signingCredentials: creds
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static (string raw, string hash) GenerateRefreshToken()
    {
        var raw = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
        var hash = HashToken(raw);
        return (raw, hash);
    }

    private static string HashToken(string token)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return Convert.ToHexString(bytes).ToLower();
    }

    private static string HashPassword(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Pbkdf2Iterations, HashAlgorithmName.SHA256, 32);
        // format: iterations.salt(base64).hash(base64)
        return $"{Pbkdf2Iterations}.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(hash)}";
    }

    private static bool VerifyPassword(string password, string stored)
    {
        var parts = stored.Split('.');
        if (parts.Length != 3) return false;
        if (!int.TryParse(parts[0], out var iterations)) return false;
        var salt = Convert.FromBase64String(parts[1]);
        var expectedHash = Convert.FromBase64String(parts[2]);
        var actualHash = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, 32);
        return CryptographicOperations.FixedTimeEquals(actualHash, expectedHash);
    }

    // ── Update Profile ─────────────────────────────────────────
    public async Task<BaseResponse<UserInfo>> UpdateProfileAsync(int userId, UpdateProfileRequest req)
    {
        var user = await db.Users.Include(u => u.UserRoles).ThenInclude(ur => ur.Role).FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null)
            return BaseResponse<UserInfo>.Fail("Không tìm thấy người dùng.");

        user.FullName = req.FullName;
        user.Email = req.Email;
        user.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync();

        var roles = user.UserRoles.Select(ur => ur.Role.Name).ToList();

        var userInfo = new UserInfo
        {
            Id = user.Id,
            FullName = user.FullName,
            Phone = user.Phone,
            Email = user.Email,
            AvatarUrl = user.AvatarUrl,
            Roles = roles
        };

        return BaseResponse<UserInfo>.Ok(userInfo, "Cập nhật hồ sơ thành công.");
    }

    // ── Change Password ────────────────────────────────────────
    public async Task<BaseResponse<bool>> ChangePasswordAsync(int userId, ChangePasswordRequest req)
    {
        var user = await db.Users.FindAsync(userId);
        if (user == null)
            return BaseResponse<bool>.Fail("Không tìm thấy người dùng.");

        if (!VerifyPassword(req.CurrentPassword, user.PasswordHash))
            return BaseResponse<bool>.Fail("Mật khẩu hiện tại không chính xác.");

        user.PasswordHash = HashPassword(req.NewPassword);
        user.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync();

        return BaseResponse<bool>.Ok(true, "Đổi mật khẩu thành công.");
    }
}
