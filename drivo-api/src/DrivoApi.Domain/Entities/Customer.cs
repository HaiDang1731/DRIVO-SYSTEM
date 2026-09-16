using DrivoApi.Domain.Enums;

namespace DrivoApi.Domain.Entities;

public class Customer
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public DateOnly? DateOfBirth { get; set; }
    public string? Gender { get; set; }
    public string? EmergencyName { get; set; }
    public string? EmergencyPhone { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    public User User { get; set; } = null!;
    public ICollection<CustomerVehicle> Vehicles { get; set; } = [];
    public ICollection<Booking> Bookings { get; set; } = [];
    public ICollection<Rating> Ratings { get; set; } = [];
}

public class CustomerVehicle
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public VehicleType VehicleType { get; set; }
    public TransmissionType Transmission { get; set; }
    public string? Brand { get; set; }
    public string? Model { get; set; }
    public string? Color { get; set; }
    public string LicensePlate { get; set; } = null!;
    public short? ProductionYear { get; set; }
    public bool IsDefault { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }

    public Customer Customer { get; set; } = null!;
    public ICollection<Booking> Bookings { get; set; } = [];
}
