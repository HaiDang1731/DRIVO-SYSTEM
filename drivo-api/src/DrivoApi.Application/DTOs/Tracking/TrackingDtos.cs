namespace DrivoApi.Application.DTOs.Tracking;

/// <summary>SignalR event "DriverLocation" → group booking-{id} và admins.</summary>
public class DriverLocationEvent
{
    public int DriverId { get; set; }
    public long? BookingId { get; set; }
    public decimal Latitude { get; set; }
    public decimal Longitude { get; set; }
    public decimal? Heading { get; set; }
    public decimal? SpeedKmh { get; set; }
    public string DriverStatus { get; set; } = null!;
    public DateTime RecordedAt { get; set; }
}

/// <summary>SignalR event "BookingStatusChanged" → group booking-{id} và admins.</summary>
public class BookingStatusChangedEvent
{
    public long BookingId { get; set; }
    public string BookingCode { get; set; } = null!;
    public string Status { get; set; } = null!;
    public decimal? FinalPrice { get; set; }
    public decimal PickupFee { get; set; }
    public decimal WaitingFee { get; set; }
    public decimal ExtraDistanceFee { get; set; }
}

public class UpdateDriverLocationRequest
{
    public decimal Latitude { get; set; }
    public decimal Longitude { get; set; }
    public decimal? AccuracyMeters { get; set; }
    public decimal? SpeedKmh { get; set; }
    public decimal? Heading { get; set; }
}

public class AdminTrackingDriverDto
{
    public int DriverId { get; set; }
    public int UserId { get; set; }
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public string? AvatarUrl { get; set; }
    public string DriverStatus { get; set; } = null!;
    public string VerificationStatus { get; set; } = null!;
    public decimal Latitude { get; set; }
    public decimal Longitude { get; set; }
    public DateTime? LastLocationAt { get; set; }
    public long? ActiveBookingId { get; set; }
    public string? ActiveBookingCode { get; set; }
    public string? ActiveBookingStatus { get; set; }
}

public class AdminTrackingBookingDto
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
    public string? RoutePolyline { get; set; }
    public string CustomerName { get; set; } = null!;
    public string CustomerPhone { get; set; } = null!;
    public int? DriverId { get; set; }
    public string? DriverName { get; set; }
    public decimal? DriverLatitude { get; set; }
    public decimal? DriverLongitude { get; set; }
    public decimal EstimatedPrice { get; set; }
    public DateTime CreatedAt { get; set; }
}
