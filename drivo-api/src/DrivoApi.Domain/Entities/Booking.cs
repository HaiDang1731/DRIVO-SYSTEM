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

    // Chia doanh thu nền tảng/tài xế, chốt cùng lúc với FinalPrice khi hoàn thành chuyến.
    public decimal CommissionAmount { get; set; }
    public decimal DriverPayout { get; set; }

    public PaymentMethod PaymentMethod { get; set; } = PaymentMethod.Cash;
    // Voucher áp lúc đặt chuyến; Discount đã chốt theo giá ước tính.
    public int? VoucherId { get; set; }
    public string? VoucherCode { get; set; }

    // Pickup leg (driver scooter -> pickup), waiting & over-distance fees
    public decimal? PickupDistanceKm { get; set; }
    public decimal PickupFee { get; set; }
    public decimal WaitingFee { get; set; }
    public decimal ExtraDistanceFee { get; set; }
    public decimal? ActualDistanceKm { get; set; }
    public string? RoutePolyline { get; set; }

    public DateTime? AcceptedAt { get; set; }
    public DateTime? ArrivedAt { get; set; }
    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }

    public BookingStatus Status { get; set; } = BookingStatus.Pending;
    public string? CancelledBy { get; set; }
    public string? CancellationReason { get; set; }
    public DateTime? CancelledAt { get; set; }
    /// <summary>Lần hủy có tính lỗi tài xế không (trừ tỉ lệ hoàn thành).</summary>
    public bool DriverAtFault { get; set; }
    /// <summary>Tài xế xác nhận khách vẫn đi, tiếp tục chờ (đã qua thời gian chờ miễn phí).</summary>
    public DateTime? WaitExtendedAt { get; set; }
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
