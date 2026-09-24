namespace DrivoApi.Application.DTOs.Driver;

// ── Các trường hồ sơ tài xế (dùng chung cho tài xế tự sửa và admin sửa) ──
// Quy ước khi cập nhật: null = giữ nguyên, chuỗi rỗng = xóa giá trị.
public class DriverProfileFields
{
    public string? FullName { get; set; }
    public string? Email { get; set; }

    // Cá nhân + CCCD
    public DateOnly? DateOfBirth { get; set; }
    /// <summary>MALE | FEMALE | OTHER</summary>
    public string? Gender { get; set; }
    public string? Address { get; set; }
    public string? IdCardNumber { get; set; }

    // GPLX
    public string? LicenseNumber { get; set; }
    public string? LicenseClass { get; set; }
    public DateOnly? LicenseExpiryDate { get; set; }
    public int? DrivingExperienceYears { get; set; }

    // Liên hệ khẩn cấp
    public string? EmergencyContactName { get; set; }
    public string? EmergencyContactPhone { get; set; }
    public string? EmergencyContactRelation { get; set; }

    // Tài khoản nhận tiền
    public string? BankName { get; set; }
    public string? BankAccountNumber { get; set; }
    public string? BankAccountHolder { get; set; }
}

// ── Tài xế tự cập nhật thông tin cá nhân ──────────────────
public class UpdateDriverProfileRequest : DriverProfileFields
{
    public string? AvatarUrl { get; set; }
}

// ── Giấy tờ tài xế ────────────────────────────────────────
public static class DriverDocumentTypes
{
    public const string LicenseFront = "DRIVER_LICENSE_FRONT";
    public const string LicenseBack = "DRIVER_LICENSE_BACK";
    public const string IdFront = "CCCD_FRONT";
    public const string IdBack = "CCCD_BACK";
    public const string Portrait = "PROFILE_PHOTO";

    public static readonly string[] Required = [LicenseFront, LicenseBack, IdFront, IdBack, Portrait];
}

public class DriverDocumentItem
{
    public int Id { get; set; }
    public string DocumentType { get; set; } = null!;
    public string FileUrl { get; set; } = null!;
    public string VerificationStatus { get; set; } = null!;
    public string? RejectionReason { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? VerifiedAt { get; set; }
}

// ── Thu nhập tài xế theo ngày / tuần / tháng ──────────────
public class DriverEarningsTripDto
{
    public long Id { get; set; }
    public string BookingCode { get; set; } = null!;
    public DateTime CompletedAt { get; set; }
    public string PickupAddress { get; set; } = null!;
    public string DestinationAddress { get; set; } = null!;
    /// <summary>Giá trước voucher.</summary>
    public decimal GrossFare { get; set; }
    public decimal Discount { get; set; }
    /// <summary>Khách thực trả = GrossFare − Discount.</summary>
    public decimal CustomerPaid { get; set; }
    /// <summary>Hoa hồng DRIVO trên giá trước voucher.</summary>
    public decimal Commission { get; set; }
    public decimal Payout { get; set; }
    public string PaymentMethod { get; set; } = null!;
}

public class EarningsBucketDto
{
    public string Date { get; set; } = null!;
    public string Label { get; set; } = null!;
    public int Trips { get; set; }
    public decimal Payout { get; set; }
}

public class DriverEarningsResponse
{
    /// <summary>day | week | month</summary>
    public string Period { get; set; } = null!;
    /// <summary>Ngày đầu / cuối kỳ theo giờ VN (yyyy-MM-dd, cả hai ngày đều tính).</summary>
    public string From { get; set; } = null!;
    public string To { get; set; } = null!;
    public int TripCount { get; set; }
    public decimal GrossFare { get; set; }
    public decimal Commission { get; set; }
    public decimal VoucherSupport { get; set; }
    public decimal Payout { get; set; }
    public decimal CustomerPaid { get; set; }
    /// <summary>Tiền mặt tài xế đã thu trực tiếp từ khách.</summary>
    public decimal CashCollected { get; set; }
    /// <summary>Payout − CashCollected: dương = DRIVO còn phải trả tài xế; âm = tài xế cần nộp lại DRIVO.</summary>
    public decimal BalanceWithPlatform { get; set; }
    public List<EarningsBucketDto> Buckets { get; set; } = [];
    public List<DriverEarningsTripDto> Trips { get; set; } = [];
}

// ── Tài xế đổi mật khẩu ───────────────────────────────────
public class ChangePasswordRequest
{
    public string CurrentPassword { get; set; } = null!;
    public string NewPassword { get; set; } = null!;
}

// ── Tài xế tự xem profile của mình ────────────────────────
public class DriverProfileResponse : DriverProfileFields
{
    public int DriverId { get; set; }
    public string Phone { get; set; } = null!;
    public string? AvatarUrl { get; set; }
    public bool ProfileReviewPending { get; set; }
    public List<DriverDocumentItem> Documents { get; set; } = [];
    public string VerificationStatus { get; set; } = null!;
    public string DriverStatus { get; set; } = null!;
    public string AccountStatus { get; set; } = null!;
    public decimal RatingAverage { get; set; }
    public int TotalTrips { get; set; }
    public decimal TotalEarnings { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool IsFirstLogin { get; set; }
}

// ── Driver toggle online/offline ─────────────────────────────
public class ToggleDriverStatusRequest
{
    public bool IsOnline { get; set; }
    /// <summary>Tùy chọn: vị trí hiện tại của tài xế khi bật/tắt</summary>
    public decimal? Latitude { get; set; }
    public decimal? Longitude { get; set; }
}

// ── Update booking status ─────────────────────────────────────
public class UpdateBookingStatusRequest
{
    public string Status { get; set; } = null!;
}
