using DrivoApi.Domain.Enums;

namespace DrivoApi.Application.DTOs.Customer;

public class CreateCustomerVehicleRequest
{
    public string? Brand { get; set; }
    public string? Model { get; set; }
    public string? Color { get; set; }
    public string LicensePlate { get; set; } = null!;
    public VehicleType VehicleType { get; set; } = VehicleType.Car;
    public TransmissionType Transmission { get; set; } = TransmissionType.Automatic;
    public short? ProductionYear { get; set; }
    public bool IsDefault { get; set; } = false;
}

public class CustomerVehicleResponse
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public string? Brand { get; set; }
    public string? Model { get; set; }
    public string? Color { get; set; }
    public string LicensePlate { get; set; } = null!;
    public string VehicleType { get; set; } = null!;
    public string Transmission { get; set; } = null!;
    public short? ProductionYear { get; set; }
    public bool IsDefault { get; set; }
    public DateTime CreatedAt { get; set; }
}
