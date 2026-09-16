namespace DrivoApi.Domain.Enums;

public enum BookingStatus
{
    Pending,
    SearchingDriver,
    DriverAssigned,
    DriverAccepted,
    DriverArriving,
    DriverArrived,
    InProgress,
    Completed,
    Cancelled
}

public enum DriverStatus
{
    Offline,
    Online,
    Busy,
    Suspended
}

public enum VerificationStatus
{
    Pending,
    Approved,
    Rejected,
    Suspended
}

public enum PaymentStatus
{
    Pending,
    Success,
    Failed,
    Refunded
}

public enum PaymentMethod
{
    Cash,
    MockBanking,
    MockEwallet
}

public enum VehicleType
{
    Motorbike,
    Car,
    Suv,
    Truck,
    Other
}

public enum TransmissionType
{
    Manual,
    Automatic,
    Other
}

public enum UserStatus
{
    Active,
    Inactive,
    Locked,
    Pending
}

public enum OfferStatus
{
    Sent,
    Accepted,
    Rejected,
    Expired,
    Cancelled
}
