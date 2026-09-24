using DrivoApi.Domain.Enums;

namespace DrivoApi.Domain.Entities;

public class Driver
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public string LicenseNumber { get; set; } = null!;
    public string? LicenseClass { get; set; }
    public VerificationStatus VerificationStatus { get; set; } = VerificationStatus.Pending;
    public DriverStatus DriverStatus { get; set; } = DriverStatus.Offline;
    public decimal RatingAverage { get; set; }
    public int RatingCount { get; set; }
    public int TotalTrips { get; set; }
    public decimal TotalEarnings { get; set; }
    public decimal? CurrentLatitude { get; set; }
    public decimal? CurrentLongitude { get; set; }
    public DateTime? LastLocationAt { get; set; }

    // Cá nhân + CCCD
    public DateOnly? DateOfBirth { get; set; }
    /// <summary>MALE | FEMALE | OTHER</summary>
    public string? Gender { get; set; }
    public string? Address { get; set; }
    public string? IdCardNumber { get; set; }

    // GPLX
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

    /// <summary>Tài xế đã duyệt sửa thông tin quan trọng / tải giấy tờ mới -> admin cần xem lại.</summary>
    public bool ProfileReviewPending { get; set; }
    public DateTime? ProfileUpdatedAt { get; set; }

    /// <summary>Số dư ví ký quỹ. Chỉ thay đổi qua DriverWalletTransaction (UPDATE cộng dồn, không ghi đè).</summary>
    public decimal WalletBalance { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    public User User { get; set; } = null!;
    public ICollection<DriverDocument> Documents { get; set; } = [];
    public ICollection<DriverStatusHistory> StatusHistory { get; set; } = [];
    public ICollection<DriverLocationHistory> LocationHistory { get; set; } = [];
    public ICollection<Booking> Bookings { get; set; } = [];
    public ICollection<Trip> Trips { get; set; } = [];
    public ICollection<Rating> Ratings { get; set; } = [];
}

public class DriverDocument
{
    public int Id { get; set; }
    public int DriverId { get; set; }
    public string DocumentType { get; set; } = null!;
    public string FileUrl { get; set; } = null!;
    public VerificationStatus VerificationStatus { get; set; } = VerificationStatus.Pending;
    public string? RejectionReason { get; set; }
    public int? VerifiedBy { get; set; }
    public DateTime? VerifiedAt { get; set; }
    public DateTime CreatedAt { get; set; }

    public Driver Driver { get; set; } = null!;
}

public class DriverStatusHistory
{
    public long Id { get; set; }
    public int DriverId { get; set; }
    public string? OldStatus { get; set; }
    public string NewStatus { get; set; } = null!;
    public DateTime ChangedAt { get; set; }
    public string? Reason { get; set; }

    public Driver Driver { get; set; } = null!;
}

public class DriverLocationHistory
{
    public long Id { get; set; }
    public int DriverId { get; set; }
    public long? BookingId { get; set; }
    public decimal Latitude { get; set; }
    public decimal Longitude { get; set; }
    public decimal? AccuracyMeters { get; set; }
    public decimal? SpeedKmh { get; set; }
    public decimal? Heading { get; set; }
    public DateTime RecordedAt { get; set; }

    public Driver Driver { get; set; } = null!;
}
