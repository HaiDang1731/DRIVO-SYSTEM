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
    public decimal RatingAverage { get; set; }
    public int TotalTrips { get; set; }
    public decimal TotalEarnings { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool IsFirstLogin { get; set; }
}
