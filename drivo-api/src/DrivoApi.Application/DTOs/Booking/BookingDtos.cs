using DrivoApi.Domain.Enums;

namespace DrivoApi.Application.DTOs.Booking;

public class EstimateFareRequest
{
    public decimal PickupLatitude { get; set; }
    public decimal PickupLongitude { get; set; }
    public decimal DestinationLatitude { get; set; }
    public decimal DestinationLongitude { get; set; }
    public VehicleType VehicleType { get; set; } = VehicleType.Car;
    public TransmissionType Transmission { get; set; } = TransmissionType.Automatic;
}

public class EstimateFareResponse
{
    public decimal EstimatedDistanceKm { get; set; }
    public int EstimatedDurationMin { get; set; }
    public decimal BaseFare { get; set; }
    public decimal DistanceFare { get; set; }
    public decimal TimeFare { get; set; }
    public decimal NightSurcharge { get; set; }
    public decimal TotalEstimatedFare { get; set; }
    public int? PricingRuleId { get; set; }

    /// <summary>Encoded polyline (precision 5) của chặng chính từ OSRM (null nếu dùng ước tính)</summary>
    public string? RoutePolyline { get; set; }

    // Xem trước chặng đón (tài xế Online gần nhất, vị trí trong 10 phút) — null nếu không có tài xế
    public decimal? EstimatedPickupKm { get; set; }
    public decimal? EstimatedPickupFee { get; set; }
    public int? NearestDriverEtaMin { get; set; }

    // Tham số phí từ bảng giá áp dụng
    public decimal FreePickupKm { get; set; }
    public decimal PickupFeePerKm { get; set; }
    public decimal WaitingPricePerMin { get; set; }
    public int FreeWaitingMin { get; set; }
}

public class CreateBookingRequest
{
    public int CustomerVehicleId { get; set; }
    public string PickupAddress { get; set; } = null!;
    public decimal PickupLatitude { get; set; }
    public decimal PickupLongitude { get; set; }
    public string DestinationAddress { get; set; } = null!;
    public decimal DestinationLatitude { get; set; }
    public decimal DestinationLongitude { get; set; }
    public string? CustomerNote { get; set; }
}

public class CancelBookingRequest
{
    public string? Reason { get; set; }
}

public class BookingDriverSummaryDto
{
    public int Id { get; set; }
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public string? AvatarUrl { get; set; }
    public decimal? Rating { get; set; }
}

public class BookingVehicleSummaryDto
{
    public int Id { get; set; }
    public string? Brand { get; set; }
    public string? Model { get; set; }
    public string LicensePlate { get; set; } = null!;
    public string Transmission { get; set; } = null!;
}

public class BookingDetailResponse
{
    public long Id { get; set; }
    public string BookingCode { get; set; } = null!;
    public string Status { get; set; } = null!;
    public string PickupAddress { get; set; } = null!;
    public decimal PickupLatitude { get; set; }
    public decimal PickupLongitude { get; set; }
    public string DestinationAddress { get; set; } = null!;
    public decimal DestinationLatitude { get; set; }
    public decimal DestinationLongitude { get; set; }
    public decimal EstimatedDistanceKm { get; set; }
    public int EstimatedDurationMin { get; set; }
    public decimal BaseFare { get; set; }
    public decimal DistanceFare { get; set; }
    public decimal Surcharge { get; set; }
    public decimal EstimatedPrice { get; set; }
    public decimal? FinalPrice { get; set; }
    public string? CustomerNote { get; set; }
    public DateTime CreatedAt { get; set; }

    public decimal TimeFare { get; set; }
    public string? RoutePolyline { get; set; }
    public decimal? PickupDistanceKm { get; set; }
    public decimal PickupFee { get; set; }
    public decimal WaitingFee { get; set; }
    public decimal ExtraDistanceFee { get; set; }
    public decimal Discount { get; set; }
    public decimal? ActualDistanceKm { get; set; }
    public DateTime? AcceptedAt { get; set; }
    public DateTime? ArrivedAt { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }

    // Vị trí hiện tại của tài xế (chỉ khi đã có tài xế nhận)
    public decimal? DriverLatitude { get; set; }
    public decimal? DriverLongitude { get; set; }
    public DateTime? DriverLastLocationAt { get; set; }

    /// <summary>Chỉ có trong danh sách cuốc chờ của tài xế: khoảng cách (km) từ tài xế tới điểm đón</summary>
    public decimal? DistanceToPickupKm { get; set; }

    public BookingVehicleSummaryDto Vehicle { get; set; } = null!;
    public BookingDriverSummaryDto? Driver { get; set; }
}

// ── Admin: chi tiết cuốc xe kèm lộ trình GPS ─────────────────
public class AdminBookingCustomerDto
{
    public int Id { get; set; }
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
}

public class TrailPointDto
{
    public decimal Latitude { get; set; }
    public decimal Longitude { get; set; }
    public DateTime RecordedAt { get; set; }
}

public class BookingStatusHistoryDto
{
    public string Status { get; set; } = null!;
    public string? OldStatus { get; set; }
    public DateTime ChangedAt { get; set; }
    public string? Note { get; set; }
}

public class PricingRuleSnapshotDto
{
    public int Id { get; set; }
    public string VehicleType { get; set; } = null!;
    public decimal BaseFare { get; set; }
    public decimal PricePerKm { get; set; }
    public decimal PricePerMinute { get; set; }
    public decimal NightSurcharge { get; set; }
    public decimal WaitingPricePerMin { get; set; }
    public decimal FreePickupKm { get; set; }
    public decimal PickupFeePerKm { get; set; }
    public int FreeWaitingMin { get; set; }
    public decimal OverDistanceTolerancePercent { get; set; }
}

public class AdminBookingDetailResponse : BookingDetailResponse
{
    public AdminBookingCustomerDto Customer { get; set; } = null!;
    public string? CancelledBy { get; set; }
    public string? CancellationReason { get; set; }
    public DateTime? CancelledAt { get; set; }
    public List<TrailPointDto> Trail { get; set; } = [];
    public List<BookingStatusHistoryDto> StatusHistory { get; set; } = [];
    public PricingRuleSnapshotDto? PricingRule { get; set; }
}
