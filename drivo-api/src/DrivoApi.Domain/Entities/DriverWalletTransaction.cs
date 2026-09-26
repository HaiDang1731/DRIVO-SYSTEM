namespace DrivoApi.Domain.Entities;

public class DriverWalletTransaction
{
    public long Id { get; set; }
    public int DriverId { get; set; }
    /// <summary>TOPUP | WITHDRAW | TRIP_CASH | TRIP_APP | ADJUSTMENT</summary>
    public string Type { get; set; } = null!;
    /// <summary>Có dấu: + cộng vào ví, - trừ khỏi ví.</summary>
    public decimal Amount { get; set; }
    public decimal? BalanceAfter { get; set; }
    /// <summary>PENDING | COMPLETED | REJECTED</summary>
    public string Status { get; set; } = null!;
    public long? BookingId { get; set; }
    /// <summary>Nội dung chuyển khoản khi nạp tiền.</summary>
    public string? ReferenceCode { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? ProcessedAt { get; set; }
    public int? ProcessedBy { get; set; }

    public Driver Driver { get; set; } = null!;
}

public static class WalletTxType
{
    public const string Topup = "TOPUP";
    public const string Withdraw = "WITHDRAW";
    public const string TripCash = "TRIP_CASH";
    public const string TripApp = "TRIP_APP";
    public const string Adjustment = "ADJUSTMENT";
}

public static class WalletTxStatus
{
    public const string Pending = "PENDING";
    public const string Completed = "COMPLETED";
    public const string Rejected = "REJECTED";
}
