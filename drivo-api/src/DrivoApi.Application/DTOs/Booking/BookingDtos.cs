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

    public BookingVehicleSummaryDto Vehicle { get; set; } = null!;
    public BookingDriverSummaryDto? Driver { get; set; }
}
