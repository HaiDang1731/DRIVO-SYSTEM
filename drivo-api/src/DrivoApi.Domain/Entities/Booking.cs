using DrivoApi.Domain.Enums;

namespace DrivoApi.Domain.Entities;

public class Booking
{
    public long Id { get; set; }
    public string BookingCode { get; set; } = null!;
    public int CustomerId { get; set; }
    public int? DriverId { get; set; }
    public int CustomerVehicleId { get; set; }
    public int? PricingRuleId { get; set; }

    public string PickupAddress { get; set; } = null!;
    public decimal PickupLatitude { get; set; }
    public decimal PickupLongitude { get; set; }
    public string DestinationAddress { get; set; } = null!;
    public decimal DestinationLatitude { get; set; }
    public decimal DestinationLongitude { get; set; }

    public VehicleType VehicleType { get; set; }
    public TransmissionType Transmission { get; set; }

    public decimal? EstimatedDistanceKm { get; set; }
    public int? EstimatedDurationMin { get; set; }

    public decimal BaseFare { get; set; }
    public decimal DistanceFare { get; set; }
    public decimal TimeFare { get; set; }
    public decimal Surcharge { get; set; }
    public decimal Discount { get; set; }
    public decimal EstimatedPrice { get; set; }
    public decimal? FinalPrice { get; set; }

    public BookingStatus Status { get; set; } = BookingStatus.Pending;
    public string? CancelledBy { get; set; }
    public string? CancellationReason { get; set; }
    public DateTime? CancelledAt { get; set; }
    public string? CustomerNote { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    // Navigation
    public Customer Customer { get; set; } = null!;
    public Driver? Driver { get; set; }
    public CustomerVehicle CustomerVehicle { get; set; } = null!;
    public PricingRule? PricingRule { get; set; }
    public Trip? Trip { get; set; }
    public ICollection<BookingDriverOffer> DriverOffers { get; set; } = [];
    public ICollection<BookingStatusHistory> StatusHistory { get; set; } = [];
}
