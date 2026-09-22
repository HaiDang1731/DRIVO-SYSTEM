namespace DrivoApi.Application.DTOs.Admin;

// ── Admin tạo tài khoản tài xế ─────────────────────────────
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

// ── Admin duyệt / từ chối tài xế ───────────────────────────
public class VerifyDriverRequest
{
    /// <summary>APPROVED hoặc REJECTED</summary>
    public string Status { get; set; } = null!;
    public string? RejectionReason { get; set; }
}

// ── Admin đăng ký giấy tờ cho tài xế ──────────────────────
public class AddDriverDocumentRequest
{
    /// <summary>CCCD | GPLX | DRIVER_LICENSE | VEHICLE_REGISTRATION | INSURANCE</summary>
    public string DocumentType { get; set; } = null!;
    public string FileUrl { get; set; } = null!;
}

// ── Response: thông tin tài xế đầy đủ ──────────────────────
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
    public int TotalTrips { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public List<DriverDocumentDto> Documents { get; set; } = [];
}

public class DriverDocumentDto
{
    public int Id { get; set; }
    public string DocumentType { get; set; } = null!;
    public string FileUrl { get; set; } = null!;
    public string VerificationStatus { get; set; } = null!;
    public string? RejectionReason { get; set; }
    public DateTime CreatedAt { get; set; }
}

// ── Danh sách tài xế phân trang ────────────────────────────
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
    public DateTime CreatedAt { get; set; }
}
