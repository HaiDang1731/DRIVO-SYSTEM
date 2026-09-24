using System.Security.Cryptography;
using System.Text;
using DrivoApi.Application.DTOs.Admin;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Driver;
using DrivoApi.Application.Services;
using DrivoApi.Domain.Entities;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure;

// ── Admin quản lý tài xế ───────────────────────────────────────────────────
public class AdminDriverService(DrivoDbContext db) : IAdminDriverService
{
    private const int Pbkdf2Iterations = 350_000;

    public async Task<BaseResponse<DriverDetailResponse>> CreateDriverAsync(
        CreateDriverRequest req, int adminUserId)
    {
        // Validate số điện thoại unique
        if (await db.Users.AnyAsync(u => u.Phone == req.Phone && !u.IsDeleted))
            return BaseResponse<DriverDetailResponse>.Fail("Số điện thoại đã được đăng ký.");

        if (!string.IsNullOrEmpty(req.Email) &&
            await db.Users.AnyAsync(u => u.Email == req.Email && !u.IsDeleted))
            return BaseResponse<DriverDetailResponse>.Fail("Email đã được sử dụng.");

        // Validate GPLX unique
        if (await db.Drivers.AnyAsync(d => d.LicenseNumber == req.LicenseNumber))
            return BaseResponse<DriverDetailResponse>.Fail("Số GPLX đã tồn tại trong hệ thống.");

        var driverRole = await db.Roles.FirstOrDefaultAsync(r => r.Name == "DRIVER");
        if (driverRole == null)
            return BaseResponse<DriverDetailResponse>.Fail("Role DRIVER không tồn tại.");

        // Password mặc định = SĐT nếu admin không nhập
        var initialPassword = string.IsNullOrEmpty(req.InitialPassword)
            ? req.Phone
            : req.InitialPassword;

        await using var tx = await db.Database.BeginTransactionAsync();
        try
        {
            // Tạo User
            var user = new User
            {
                FullName = req.FullName.Trim(),
                Phone = req.Phone.Trim(),
                Email = req.Email?.Trim().ToLower(),
                PasswordHash = HashPassword(initialPassword),
                // Status = Active (tài xế có thể đăng nhập ngay, nhưng VerificationStatus vẫn là Pending)
                Status = UserStatus.Active,
                CreatedAt = DateTime.UtcNow
            };
            db.Users.Add(user);
            await db.SaveChangesAsync();

            // Gán role DRIVER
            db.UserRoles.Add(new UserRole
            {
                UserId = user.Id,
                RoleId = driverRole.Id,
                AssignedAt = DateTime.UtcNow,
                AssignedBy = adminUserId
            });

            // Tạo Driver profile
            var driver = new Driver
            {
                UserId = user.Id,
                LicenseNumber = req.LicenseNumber.Trim(),
                LicenseClass = req.LicenseClass?.Trim(),
                VerificationStatus = VerificationStatus.Pending,
                DriverStatus = DriverStatus.Offline,
                CreatedAt = DateTime.UtcNow
            };
            db.Drivers.Add(driver);

            await db.SaveChangesAsync();
            await tx.CommitAsync();

            return BaseResponse<DriverDetailResponse>.Ok(
                MapToDetail(driver, user, []),
                $"Tạo tài khoản tài xế thành công! Mật khẩu mặc định: {initialPassword}");
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }
    }

    public async Task<BaseResponse<DriverDetailResponse>> VerifyDriverAsync(
        int driverId, VerifyDriverRequest req, int adminUserId)
    {
        if (!Enum.TryParse<VerificationStatus>(req.Status, true, out var newStatus) ||
            (newStatus != VerificationStatus.Approved && newStatus != VerificationStatus.Rejected))
            return BaseResponse<DriverDetailResponse>.Fail("Status phải là APPROVED hoặc REJECTED.");

        if (newStatus == VerificationStatus.Rejected &&
            string.IsNullOrWhiteSpace(req.RejectionReason))
            return BaseResponse<DriverDetailResponse>.Fail("Vui lòng nhập lý do từ chối.");

        var driver = await db.Drivers
            .Include(d => d.User)
            .Include(d => d.Documents)
            .FirstOrDefaultAsync(d => d.Id == driverId);

        if (driver == null)
            return BaseResponse<DriverDetailResponse>.Fail("Không tìm thấy tài xế.");

        

        driver.VerificationStatus = newStatus;
        driver.UpdatedAt = DateTime.UtcNow;

        // Nếu bị từ chối → DriverStatus = Offline
        if (newStatus == VerificationStatus.Rejected)
            driver.DriverStatus = DriverStatus.Offline;

        await db.SaveChangesAsync();

        var msg = newStatus == VerificationStatus.Approved
            ? "Hồ sơ tài xế đã được duyệt thành công!"
            : $"Hồ sơ tài xế đã bị từ chối. Lý do: {req.RejectionReason}";

        return BaseResponse<DriverDetailResponse>.Ok(
            MapToDetail(driver, driver.User, driver.Documents.ToList()), msg);
    }

    public async Task<BaseResponse<DriverDocumentDto>> AddDocumentAsync(
        int driverId, AddDriverDocumentRequest req)
    {
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.Id == driverId);
        if (driver == null)
            return BaseResponse<DriverDocumentDto>.Fail("Không tìm thấy tài xế.");

        var doc = new DriverDocument
        {
            DriverId = driverId,
            DocumentType = req.DocumentType.ToUpper().Trim(),
            FileUrl = req.FileUrl.Trim(),
            VerificationStatus = VerificationStatus.Pending,
            CreatedAt = DateTime.UtcNow
        };
        db.DriverDocuments.Add(doc);
        await db.SaveChangesAsync();

        return BaseResponse<DriverDocumentDto>.Ok(MapToDocDto(doc), "Thêm giấy tờ thành công!");
    }

    public async Task<BaseResponse<DriverDetailResponse>> GetDriverByIdAsync(int driverId)
    {
        var driver = await db.Drivers
            .Include(d => d.User)
            .Include(d => d.Documents)
            .Include(d => d.StatusHistory)
            .Include(d => d.Bookings)
                .ThenInclude(b => b.Customer)
                    .ThenInclude(c => c.User)
            .Include(d => d.Ratings)
                .ThenInclude(r => r.Customer)
                    .ThenInclude(c => c.User)
            .FirstOrDefaultAsync(d => d.Id == driverId);

        if (driver == null)
            return BaseResponse<DriverDetailResponse>.Fail("Không tìm thấy tài xế.");

        return BaseResponse<DriverDetailResponse>.Ok(
            MapToDetail(driver, driver.User, driver.Documents.ToList()));
    }

    public async Task<BaseResponse<bool>> ResetDriverPasswordAsync(int driverId, string? newPassword, int adminUserId)
    {
        var driver = await db.Drivers
            .Include(d => d.User)
            .FirstOrDefaultAsync(d => d.Id == driverId);

        if (driver == null)
            return BaseResponse<bool>.Fail("Không tìm thấy tài xế.");

        var pwd = string.IsNullOrWhiteSpace(newPassword) ? driver.User.Phone : newPassword.Trim();
        driver.User.PasswordHash = HashPassword(pwd);
        driver.User.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync();
        return BaseResponse<bool>.Ok(true, $"Đã đặt lại mật khẩu cho tài xế {driver.User.FullName}. Mật khẩu mới: {pwd}");
    }

    public async Task<BaseResponse<List<DriverListResponse>>> GetDriversAsync(
        string? verificationStatus, int page, int pageSize)
    {
        var query = db.Drivers
            .Include(d => d.User)
            .AsQueryable();

        if (!string.IsNullOrEmpty(verificationStatus) &&
            Enum.TryParse<VerificationStatus>(verificationStatus, true, out var vs))
            query = query.Where(d => d.VerificationStatus == vs);

        var drivers = await query
            .OrderByDescending(d => d.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(d => new DriverListResponse
            {
                DriverId = d.Id,
                UserId = d.UserId,
                FullName = d.User.FullName,
                Phone = d.User.Phone,
                LicenseNumber = d.LicenseNumber,
                VerificationStatus = d.VerificationStatus.ToString(),
                DriverStatus = d.DriverStatus.ToString(),
                  AccountStatus = d.User.Status.ToString(),
                CreatedAt = d.CreatedAt
            })
            .ToListAsync();

        return BaseResponse<List<DriverListResponse>>.Ok(drivers);
    }

    public async Task<BaseResponse<bool>> SetDriverAccountStatusAsync(
        int driverId, string status, int adminUserId)
    {
        if (!Enum.TryParse<UserStatus>(status, true, out var userStatus))
            return BaseResponse<bool>.Fail("Status không hợp lệ. Dùng: Active, Locked.");

        var driver = await db.Drivers
            .Include(d => d.User)
            .FirstOrDefaultAsync(d => d.Id == driverId);

        if (driver == null)
            return BaseResponse<bool>.Fail("Không tìm thấy tài xế.");

        driver.User.Status = userStatus;
        driver.User.UpdatedAt = DateTime.UtcNow;

        if (userStatus == UserStatus.Locked)
            driver.DriverStatus = DriverStatus.Offline;

        await db.SaveChangesAsync();
        return BaseResponse<bool>.Ok(true,
            userStatus == UserStatus.Locked
                ? "Đã khóa tài khoản tài xế."
                : "Đã mở khóa tài khoản tài xế.");
    }

    // ── Helpers ─────────────────────────────────────────────
    private static DriverDetailResponse MapToDetail(Driver d, User u, List<DriverDocument> docs) => new()
    {
        DriverId = d.Id,
        UserId = u.Id,
        FullName = u.FullName,
        Phone = u.Phone,
        Email = u.Email,
        AvatarUrl = u.AvatarUrl,
        LicenseNumber = d.LicenseNumber,
        LicenseClass = d.LicenseClass,
        VerificationStatus = d.VerificationStatus.ToString(),
        DriverStatus = d.DriverStatus.ToString(),
                  AccountStatus = d.User.Status.ToString(),
        RatingAverage = d.RatingAverage,
        TotalTrips = d.TotalTrips,
        CreatedAt = d.CreatedAt,
        UpdatedAt = d.UpdatedAt,
        Documents = docs.Select(MapToDocDto).ToList()
    };

    private static DriverDocumentDto MapToDocDto(DriverDocument doc) => new()
    {
        Id = doc.Id,
        DocumentType = doc.DocumentType,
        FileUrl = doc.FileUrl,
        VerificationStatus = doc.VerificationStatus.ToString(),
        RejectionReason = doc.RejectionReason,
        CreatedAt = doc.CreatedAt
    };

    private static string HashPassword(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt,
            Pbkdf2Iterations, HashAlgorithmName.SHA256, 32);
        return $"{Pbkdf2Iterations}.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(hash)}";
    }
}

// ── Tài xế tự quản lý profile ──────────────────────────────────────────────
public class DriverProfileService(DrivoDbContext db) : IDriverProfileService
{
    private const int Pbkdf2Iterations = 350_000;

    public async Task<BaseResponse<DriverProfileResponse>> GetMyProfileAsync(int userId)
    {
        var driver = await db.Drivers
            .Include(d => d.User)
            .FirstOrDefaultAsync(d => d.UserId == userId);

        if (driver == null)
            return BaseResponse<DriverProfileResponse>.Fail("Không tìm thấy hồ sơ tài xế.");

        return BaseResponse<DriverProfileResponse>.Ok(MapToProfile(driver));
    }

    public async Task<BaseResponse<DriverProfileResponse>> UpdateProfileAsync(
        int userId, UpdateDriverProfileRequest req)
    {
        var driver = await db.Drivers
            .Include(d => d.User)
            .FirstOrDefaultAsync(d => d.UserId == userId);

        if (driver == null)
            return BaseResponse<DriverProfileResponse>.Fail("Không tìm thấy hồ sơ tài xế.");

        // Validate email unique nếu đổi email
        if (!string.IsNullOrEmpty(req.Email) && req.Email != driver.User.Email)
        {
            if (await db.Users.AnyAsync(u => u.Email == req.Email && u.Id != userId && !u.IsDeleted))
                return BaseResponse<DriverProfileResponse>.Fail("Email đã được sử dụng.");
            driver.User.Email = req.Email.Trim().ToLower();
        }

        // Validate GPLX unique nếu đổi
        if (!string.IsNullOrEmpty(req.LicenseNumber) && req.LicenseNumber != driver.LicenseNumber)
        {
            if (await db.Drivers.AnyAsync(d => d.LicenseNumber == req.LicenseNumber && d.Id != driver.Id))
                return BaseResponse<DriverProfileResponse>.Fail("Số GPLX đã tồn tại trong hệ thống.");
            driver.LicenseNumber = req.LicenseNumber.Trim();
        }

        if (!string.IsNullOrEmpty(req.FullName)) driver.User.FullName = req.FullName.Trim();
        if (!string.IsNullOrEmpty(req.LicenseClass)) driver.LicenseClass = req.LicenseClass.Trim();
        if (!string.IsNullOrEmpty(req.AvatarUrl)) driver.User.AvatarUrl = req.AvatarUrl.Trim();

        driver.User.UpdatedAt = DateTime.UtcNow;
        driver.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        return BaseResponse<DriverProfileResponse>.Ok(
            MapToProfile(driver), "Cập nhật thông tin thành công!");
    }

    public async Task<BaseResponse<bool>> ChangePasswordAsync(
        int userId, ChangePasswordRequest req)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId && !u.IsDeleted);
        if (user == null) return BaseResponse<bool>.Fail("Tài khoản không tồn tại.");

        if (!VerifyPassword(req.CurrentPassword, user.PasswordHash))
            return BaseResponse<bool>.Fail("Mật khẩu hiện tại không đúng.");

        if (req.NewPassword.Length < 6)
            return BaseResponse<bool>.Fail("Mật khẩu mới phải có ít nhất 6 ký tự.");

        user.PasswordHash = HashPassword(req.NewPassword);
        user.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        return BaseResponse<bool>.Ok(true, "Đổi mật khẩu thành công!");
    }

    // ── Helpers ─────────────────────────────────────────────
    private static DriverProfileResponse MapToProfile(Driver d) => new()
    {
        DriverId = d.Id,
        FullName = d.User.FullName,
        Phone = d.User.Phone,
        Email = d.User.Email,
        AvatarUrl = d.User.AvatarUrl,
        LicenseNumber = d.LicenseNumber,
        LicenseClass = d.LicenseClass,
        VerificationStatus = d.VerificationStatus.ToString(),
        DriverStatus = d.DriverStatus.ToString(),
                  AccountStatus = d.User.Status.ToString(),
        RatingAverage = d.RatingAverage,
        TotalTrips = d.TotalTrips,
        TotalEarnings = d.TotalEarnings,
        CreatedAt = d.CreatedAt,
        // FirstLogin: nếu LastLoginAt null = chưa từng đăng nhập (mật khẩu vẫn là mặc định)
        IsFirstLogin = d.User.LastLoginAt == null
    };

    private static string HashPassword(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt,
            Pbkdf2Iterations, HashAlgorithmName.SHA256, 32);
        return $"{Pbkdf2Iterations}.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(hash)}";
    }

    private static bool VerifyPassword(string password, string stored)
    {
        var parts = stored.Split('.');
        if (parts.Length != 3) return false;
        if (!int.TryParse(parts[0], out var iterations)) return false;
        var salt = Convert.FromBase64String(parts[1]);
        var expected = Convert.FromBase64String(parts[2]);
        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt,
            iterations, HashAlgorithmName.SHA256, 32);
        return CryptographicOperations.FixedTimeEquals(actual, expected);
    }
}
