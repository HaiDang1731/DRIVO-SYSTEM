namespace DrivoApi.Application.DTOs.Driver;

// ── Tài xế tự cập nhật thông tin cá nhân ──────────────────
public class UpdateDriverProfileRequest
{
    public string? FullName { get; set; }
    public string? Email { get; set; }
    public string? LicenseNumber { get; set; }
    public string? LicenseClass { get; set; }
    public string? AvatarUrl { get; set; }
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
public class DriverProfileResponse
{
    public int DriverId { get; set; }
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
