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
        if (newStatus == VerificationStatus.Approved) driver.ProfileReviewPending = false;

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
        var driver = await LoadDetailAsync(driverId);
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
                ProfileReviewPending = d.ProfileReviewPending,
                LicenseExpiryDate = d.LicenseExpiryDate,
                LicenseClass = d.LicenseClass,
                Email = d.User.Email,
                PendingDocuments = d.Documents.Count(x => x.VerificationStatus == VerificationStatus.Pending),
                CreatedAt = d.CreatedAt
            })
            .ToListAsync();
        foreach (var x in drivers) x.LicenseNumber = DriverProfileEditor.DisplayLicense(x.LicenseNumber);

        return BaseResponse<List<DriverListResponse>>.Ok(drivers);
    }

    private Task<Driver?> LoadDetailAsync(int driverId) => db.Drivers
        .Include(d => d.User)
        .Include(d => d.Documents)
        .Include(d => d.StatusHistory)
        .Include(d => d.Bookings).ThenInclude(b => b.Customer).ThenInclude(c => c.User)
        .Include(d => d.Ratings).ThenInclude(r => r.Customer).ThenInclude(c => c.User)
        .AsSplitQuery()
        .FirstOrDefaultAsync(d => d.Id == driverId);

    public async Task<BaseResponse<DriverDetailResponse>> UpdateDriverProfileAsync(int driverId, DriverProfileFields req)
    {
        var driver = await LoadDetailAsync(driverId);
        if (driver == null)
            return BaseResponse<DriverDetailResponse>.Fail("Không tìm thấy tài xế.");

        var (error, _) = await DriverProfileEditor.ApplyAsync(db, driver, req);
        if (error != null)
            return BaseResponse<DriverDetailResponse>.Fail(error);

        await db.SaveChangesAsync();
        return BaseResponse<DriverDetailResponse>.Ok(
            MapToDetail(driver, driver.User, driver.Documents.ToList()), "Đã cập nhật hồ sơ tài xế.");
    }

    public async Task<BaseResponse<DriverDetailResponse>> ReviewDocumentAsync(
        int driverId, int documentId, ReviewDocumentRequest req, int adminUserId)
    {
        if (!Enum.TryParse<VerificationStatus>(req.Status, true, out var status) ||
            status is not (VerificationStatus.Approved or VerificationStatus.Rejected))
            return BaseResponse<DriverDetailResponse>.Fail("Status phải là APPROVED hoặc REJECTED.");
        if (status == VerificationStatus.Rejected && string.IsNullOrWhiteSpace(req.RejectionReason))
            return BaseResponse<DriverDetailResponse>.Fail("Vui lòng nhập lý do từ chối để tài xế biết cần chụp lại gì.");

        var driver = await LoadDetailAsync(driverId);
        var doc = driver?.Documents.FirstOrDefault(x => x.Id == documentId);
        if (driver == null || doc == null)
            return BaseResponse<DriverDetailResponse>.Fail("Không tìm thấy giấy tờ.");

        doc.VerificationStatus = status;
        doc.RejectionReason = status == VerificationStatus.Rejected ? req.RejectionReason!.Trim() : null;
        doc.VerifiedBy = adminUserId;
        doc.VerifiedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        return BaseResponse<DriverDetailResponse>.Ok(
            MapToDetail(driver, driver.User, driver.Documents.ToList()),
            status == VerificationStatus.Approved ? "Đã duyệt giấy tờ." : "Đã từ chối giấy tờ.");
    }

    public async Task<BaseResponse<DriverDetailResponse>> CompleteProfileReviewAsync(int driverId)
    {
        var driver = await LoadDetailAsync(driverId);
        if (driver == null)
            return BaseResponse<DriverDetailResponse>.Fail("Không tìm thấy tài xế.");

        driver.ProfileReviewPending = false;
        driver.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return BaseResponse<DriverDetailResponse>.Ok(
            MapToDetail(driver, driver.User, driver.Documents.ToList()), "Đã xác nhận xem lại hồ sơ.");
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
        LicenseNumber = DriverProfileEditor.DisplayLicense(d.LicenseNumber),
        LicenseClass = d.LicenseClass,
        Profile = ProfileOf(d),
        ProfileReviewPending = d.ProfileReviewPending,
        ProfileUpdatedAt = d.ProfileUpdatedAt,
        VerificationStatus = d.VerificationStatus.ToString(),
        DriverStatus = d.DriverStatus.ToString(),
        AccountStatus = d.User.Status.ToString(),
        RatingAverage = d.RatingAverage,
        RatingCount = d.RatingCount,
        TotalTrips = d.TotalTrips,
        // TotalEarnings đã là thu nhập thực của tài xế (sau khi trừ hoa hồng nền tảng), cộng dồn khi hoàn thành chuyến.
        TotalEarnings = d.TotalEarnings,
        TotalDistanceKm = d.Bookings
            .Where(b => b.Status == BookingStatus.Completed)
            .Sum(b => b.ActualDistanceKm ?? b.EstimatedDistanceKm ?? 0m),
        LastLoginAt = u.LastLoginAt,
        CreatedAt = d.CreatedAt,
        UpdatedAt = d.UpdatedAt,
        Documents = docs.Select(MapToDocDto).ToList(),
        StatusHistory = d.StatusHistory
            .OrderByDescending(h => h.ChangedAt)
            .Select(h => new DriverStatusHistoryDto
            {
                Id = h.Id,
                OldStatus = h.OldStatus,
                NewStatus = h.NewStatus,
                ChangedAt = h.ChangedAt,
                Reason = h.Reason
            }).ToList(),
        Trips = d.Bookings
            .OrderByDescending(b => b.CreatedAt)
            .Select(b => new DriverTripSummaryDto
            {
                Id = b.Id,
                BookingCode = b.BookingCode,
                PickupAddress = b.PickupAddress,
                DestinationAddress = b.DestinationAddress,
                DistanceKm = b.ActualDistanceKm ?? b.EstimatedDistanceKm,
                Amount = b.FinalPrice ?? b.EstimatedPrice,
                Status = b.Status.ToString(),
                CustomerName = b.Customer?.User?.FullName,
                CustomerPhone = b.Customer?.User?.Phone,
                CreatedAt = b.CreatedAt
            }).ToList(),
        Ratings = d.Ratings
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new DriverRatingSummaryDto
            {
                Id = r.Id,
                Score = r.Score,
                Comment = r.Comment,
                CustomerName = r.Customer?.User?.FullName ?? "Khách hàng",
                CreatedAt = r.CreatedAt
            }).ToList()
    };

    private static DriverProfileFields ProfileOf(Driver d)
    {
        var p = new DriverProfileFields();
        DriverProfileEditor.Fill(p, d);
        return p;
    }

    private static DriverDocumentDto MapToDocDto(DriverDocument doc) => new()
    {
        Id = doc.Id,
        DocumentType = doc.DocumentType,
        FileUrl = doc.FileUrl,
        VerificationStatus = doc.VerificationStatus.ToString(),
        RejectionReason = doc.RejectionReason,
        VerifiedAt = doc.VerifiedAt,
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

    private Task<Driver?> LoadDriverAsync(int userId) => db.Drivers
        .Include(d => d.User)
        .Include(d => d.Documents)
        .FirstOrDefaultAsync(d => d.UserId == userId);

    public async Task<BaseResponse<DriverProfileResponse>> GetMyProfileAsync(int userId)
    {
        var driver = await LoadDriverAsync(userId);
        if (driver == null)
            return BaseResponse<DriverProfileResponse>.Fail("Không tìm thấy hồ sơ tài xế.");

        return BaseResponse<DriverProfileResponse>.Ok(MapToProfile(driver));
    }

    public async Task<BaseResponse<DriverProfileResponse>> UpdateProfileAsync(
        int userId, UpdateDriverProfileRequest req)
    {
        var driver = await LoadDriverAsync(userId);
        if (driver == null)
            return BaseResponse<DriverProfileResponse>.Fail("Không tìm thấy hồ sơ tài xế.");

        var (error, sensitive) = await DriverProfileEditor.ApplyAsync(db, driver, req);
        if (error != null)
            return BaseResponse<DriverProfileResponse>.Fail(error);
        if (!string.IsNullOrWhiteSpace(req.AvatarUrl)) driver.User.AvatarUrl = req.AvatarUrl.Trim();

        // Đã được duyệt mà đổi GPLX / CCCD / ngày sinh / tài khoản nhận tiền -> admin xem lại (vẫn chạy được)
        var needReview = sensitive && driver.VerificationStatus == VerificationStatus.Approved;
        if (needReview) driver.ProfileReviewPending = true;

        await db.SaveChangesAsync();
        return BaseResponse<DriverProfileResponse>.Ok(MapToProfile(driver), needReview
            ? "Đã lưu. Thông tin giấy tờ/tài khoản nhận tiền thay đổi sẽ được DRIVO duyệt lại."
            : "Cập nhật thông tin thành công!");
    }

    public async Task<BaseResponse<DriverProfileResponse>> UploadDocumentAsync(int userId, string documentType, string fileUrl)
    {
        if (!DriverDocumentTypes.Required.Contains(documentType))
            return BaseResponse<DriverProfileResponse>.Fail("Loại giấy tờ không hợp lệ.");

        var driver = await LoadDriverAsync(userId);
        if (driver == null)
            return BaseResponse<DriverProfileResponse>.Fail("Không tìm thấy hồ sơ tài xế.");

        // Mỗi loại chỉ giữ 1 ảnh mới nhất, chờ admin duyệt
        foreach (var old in driver.Documents.Where(x => x.DocumentType == documentType).ToList())
            db.DriverDocuments.Remove(old);

        var now = DateTime.UtcNow;
        db.DriverDocuments.Add(new DriverDocument
        {
            DriverId = driver.Id,
            DocumentType = documentType,
            FileUrl = fileUrl,
            VerificationStatus = VerificationStatus.Pending,
            CreatedAt = now
        });
        if (documentType == DriverDocumentTypes.Portrait) driver.User.AvatarUrl = fileUrl;
        if (driver.VerificationStatus == VerificationStatus.Approved) driver.ProfileReviewPending = true;
        driver.ProfileUpdatedAt = now;
        driver.UpdatedAt = now;

        await db.SaveChangesAsync();
        await db.Entry(driver).Collection(d => d.Documents).LoadAsync();
        return BaseResponse<DriverProfileResponse>.Ok(MapToProfile(driver), "Đã tải ảnh lên, chờ DRIVO duyệt.");
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
    private static DriverProfileResponse MapToProfile(Driver d)
    {
        var res = new DriverProfileResponse
        {
            DriverId = d.Id,
            Phone = d.User.Phone,
            AvatarUrl = d.User.AvatarUrl,
            ProfileReviewPending = d.ProfileReviewPending,
            Documents = d.Documents.OrderBy(x => x.DocumentType).Select(DriverProfileEditor.MapDocument).ToList(),
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
        DriverProfileEditor.Fill(res, d);
        return res;
    }

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
