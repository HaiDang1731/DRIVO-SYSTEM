namespace DrivoApi.Application.DTOs.Admin;

// ── Admin tạo tài khoản tài xế ──────────────────────────────
public class CreateDriverRequest
{
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public string? Email { get; set; }
    public string LicenseNumber { get; set; } = null!;
    public string? LicenseClass { get; set; }
    /// <summary>Mật khẩu mặc định ban đầu. Mặc định = SĐT nếu để trống.</summary>
    public string? InitialPassword { get; set; }
}

// ── Admin duyệt / từ chối tài xế ────────────────────────────
public class VerifyDriverRequest
{
    /// <summary>APPROVED hoặc REJECTED</summary>
    public string Status { get; set; } = null!;
    public string? RejectionReason { get; set; }
}

// ── Admin đăng ký giấy tờ cho tài xế ────────────────────────
public class AddDriverDocumentRequest
{
    /// <summary>CCCD | GPLX | DRIVER_LICENSE | VEHICLE_REGISTRATION | INSURANCE</summary>
    public string DocumentType { get; set; } = null!;
    public string FileUrl { get; set; } = null!;
}

// ── Admin đặt lại mật khẩu cho tài xế ────────────────────────
public class ResetDriverPasswordRequest
{
    public string? NewPassword { get; set; }
}

// ── Response: thông tin tài xế đầy đủ ───────────────────────
public class DriverDetailResponse
{
    public int DriverId { get; set; }
    public int UserId { get; set; }
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public string? Email { get; set; }
    public string? AvatarUrl { get; set; }
    public string LicenseNumber { get; set; } = null!;
    public string? LicenseClass { get; set; }
    public string VerificationStatus { get; set; } = null!;
    public string DriverStatus { get; set; } = null!;
    public string AccountStatus { get; set; } = null!;
    public decimal RatingAverage { get; set; }
    public int RatingCount { get; set; }
    public int TotalTrips { get; set; }
    public decimal TotalEarnings { get; set; }
    public decimal TotalDistanceKm { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public List<DriverDocumentDto> Documents { get; set; } = [];
    /// <summary>Hồ sơ đầy đủ: cá nhân + CCCD, GPLX, liên hệ khẩn cấp, tài khoản nhận tiền.</summary>
    public DrivoApi.Application.DTOs.Driver.DriverProfileFields Profile { get; set; } = new();
    public bool ProfileReviewPending { get; set; }
    public DateTime? ProfileUpdatedAt { get; set; }
    public List<DriverStatusHistoryDto> StatusHistory { get; set; } = [];
    public List<DriverTripSummaryDto> Trips { get; set; } = [];
    public List<DriverRatingSummaryDto> Ratings { get; set; } = [];
}

public class DriverStatusHistoryDto
{
    public long Id { get; set; }
    public string? OldStatus { get; set; }
    public string NewStatus { get; set; } = null!;
    public DateTime ChangedAt { get; set; }
    public string? Reason { get; set; }
}

public class DriverTripSummaryDto
{
    public long Id { get; set; }
    public string BookingCode { get; set; } = null!;
    public string PickupAddress { get; set; } = null!;
    public string DestinationAddress { get; set; } = null!;
    public decimal? DistanceKm { get; set; }
    public decimal Amount { get; set; }
    public string Status { get; set; } = null!;
    public string? CustomerName { get; set; }
    public string? CustomerPhone { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class DriverRatingSummaryDto
{
    public long Id { get; set; }
    public byte Score { get; set; }
    public string? Comment { get; set; }
    public string CustomerName { get; set; } = null!;
    public DateTime CreatedAt { get; set; }
}

public class DriverDocumentDto
{
    public int Id { get; set; }
    public string DocumentType { get; set; } = null!;
    public string FileUrl { get; set; } = null!;
    public string VerificationStatus { get; set; } = null!;
    public string? RejectionReason { get; set; }
    public DateTime? VerifiedAt { get; set; }
    public DateTime CreatedAt { get; set; }
}

// ── Danh sách tài xế phân trang ──────────────────────────────
public class DriverListResponse
{
    public int DriverId { get; set; }
    public int UserId { get; set; }
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public string LicenseNumber { get; set; } = null!;
    public string VerificationStatus { get; set; } = null!;
    public string DriverStatus { get; set; } = null!;
    public string AccountStatus { get; set; } = null!;
    /// <summary>Tài xế đã duyệt vừa sửa thông tin quan trọng / tải giấy tờ mới.</summary>
    public bool ProfileReviewPending { get; set; }
    public DateOnly? LicenseExpiryDate { get; set; }
    public string? LicenseClass { get; set; }
    public string? Email { get; set; }
    /// <summary>Số ảnh giấy tờ đang chờ duyệt.</summary>
    public int PendingDocuments { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class ReviewDocumentRequest
{
    /// <summary>APPROVED | REJECTED</summary>
    public string Status { get; set; } = null!;
    public string? RejectionReason { get; set; }
}
