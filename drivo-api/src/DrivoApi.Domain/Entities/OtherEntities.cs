using DrivoApi.Domain.Enums;

namespace DrivoApi.Domain.Entities;

public class Role
{
    public int Id { get; set; }
    public string Name { get; set; } = null!;
    public string? Description { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }

    public ICollection<UserRole> UserRoles { get; set; } = [];
}

public class UserRole
{
    public int UserId { get; set; }
    public int RoleId { get; set; }
    public DateTime AssignedAt { get; set; }
    public int? AssignedBy { get; set; }

    public User User { get; set; } = null!;
    public Role Role { get; set; } = null!;
}

public class RefreshToken
{
    public long Id { get; set; }
    public int UserId { get; set; }
    public string TokenHash { get; set; } = null!;
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public long? ReplacedByTokenId { get; set; }

    public User User { get; set; } = null!;
    public RefreshToken? ReplacedBy { get; set; }

    public bool IsActive => RevokedAt == null && ExpiresAt > DateTime.UtcNow;
}

public class Trip
{
    public long Id { get; set; }
    public long BookingId { get; set; }
    public int DriverId { get; set; }
    public DateTime? StartTime { get; set; }
    public DateTime? EndTime { get; set; }
    public decimal? StartLatitude { get; set; }
    public decimal? StartLongitude { get; set; }
    public decimal? EndLatitude { get; set; }
    public decimal? EndLongitude { get; set; }
    public decimal? ActualDistanceKm { get; set; }
    public int? ActualDurationMin { get; set; }
    public string Status { get; set; } = "NOT_STARTED";
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    public Booking Booking { get; set; } = null!;
    public Driver Driver { get; set; } = null!;
    public Payment? Payment { get; set; }
    public Rating? Rating { get; set; }
}

public class Payment
{
    public long Id { get; set; }
    public long TripId { get; set; }
    public int CustomerId { get; set; }
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "VND";
    public PaymentMethod PaymentMethod { get; set; }
    public PaymentStatus PaymentStatus { get; set; } = PaymentStatus.Pending;
    public DateTime? PaidAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    public Trip Trip { get; set; } = null!;
    public Customer Customer { get; set; } = null!;
    public ICollection<PaymentTransaction> Transactions { get; set; } = [];
}

public class PaymentTransaction
{
    public long Id { get; set; }
    public long PaymentId { get; set; }
    public string TransactionCode { get; set; } = null!;
    public string TransactionType { get; set; } = "CHARGE";
    public decimal Amount { get; set; }
    public string Status { get; set; } = "PENDING";
    public string? Provider { get; set; }
    public string? ProviderTransactionId { get; set; }
    public string? FailureReason { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? CompletedAt { get; set; }

    public Payment Payment { get; set; } = null!;
}

public class Rating
{
    public long Id { get; set; }
    public long TripId { get; set; }
    public int CustomerId { get; set; }
    public int DriverId { get; set; }
    public byte Score { get; set; }
    public string? Comment { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    public Trip Trip { get; set; } = null!;
    public Customer Customer { get; set; } = null!;
    public Driver Driver { get; set; } = null!;
}

public class PricingRule
{
    public int Id { get; set; }
    public VehicleType VehicleType { get; set; }
    public decimal BaseFare { get; set; }
    public decimal PricePerKm { get; set; }
    public decimal PricePerMinute { get; set; }
    public decimal NightSurcharge { get; set; }
    public decimal WaitingPricePerMin { get; set; }
    public decimal FreePickupKm { get; set; } = 3m;
    public decimal PickupFeePerKm { get; set; } = 5000m;
    public int FreeWaitingMin { get; set; } = 10;
    public decimal OverDistanceTolerancePercent { get; set; } = 10m;
    public bool IsActive { get; set; } = true;
    public DateTime EffectiveFrom { get; set; }
    public DateTime? EffectiveTo { get; set; }
    public DateTime CreatedAt { get; set; }

    public ICollection<Booking> Bookings { get; set; } = [];
}

public class BookingDriverOffer
{
    public long Id { get; set; }
    public long BookingId { get; set; }
    public int DriverId { get; set; }
    public int OfferRound { get; set; } = 1;
    public decimal? DistanceToPickupKm { get; set; }
    public int? EstimatedArrivalMin { get; set; }
    public OfferStatus OfferStatus { get; set; } = OfferStatus.Sent;
    public DateTime SentAt { get; set; }
    public DateTime? RespondedAt { get; set; }

    public Booking Booking { get; set; } = null!;
    public Driver Driver { get; set; } = null!;
}

public class BookingStatusHistory
{
    public long Id { get; set; }
    public long BookingId { get; set; }
    public string? OldStatus { get; set; }
    public string NewStatus { get; set; } = null!;
    public int? ChangedByUserId { get; set; }
    public DateTime ChangedAt { get; set; }
    public string? Reason { get; set; }

    public Booking Booking { get; set; } = null!;
}

public class Notification
{
    public long Id { get; set; }
    public int UserId { get; set; }
    public string Type { get; set; } = null!;
    public string Title { get; set; } = null!;
    public string Message { get; set; } = null!;
    public string? DataJson { get; set; }
    public bool IsRead { get; set; }
    public DateTime? ReadAt { get; set; }
    public DateTime CreatedAt { get; set; }

    public User User { get; set; } = null!;
}

public class AuditLog
{
    public long Id { get; set; }
    public int? UserId { get; set; }
    public string Action { get; set; } = null!;
    public string? EntityType { get; set; }
    public string? EntityId { get; set; }
    public string? OldValue { get; set; }
    public string? NewValue { get; set; }
    public string? IpAddress { get; set; }
    public string? UserAgent { get; set; }
    public DateTime CreatedAt { get; set; }
}
