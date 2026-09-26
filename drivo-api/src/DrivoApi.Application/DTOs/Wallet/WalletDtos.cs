namespace DrivoApi.Application.DTOs.Wallet;

/// <summary>Cấu hình ví tài xế (bản demo: tài khoản ngân hàng DRIVO là thông tin giả).</summary>
public static class WalletSettings
{
    /// <summary>Số dư tối thiểu để bật trực tuyến / nhận cuốc.</summary>
    public const decimal MinBalance = 500_000m;
    public const decimal MinTopup = 50_000m;
    public const decimal MaxTopup = 50_000_000m;
    public const decimal MinWithdraw = 50_000m;

    public const string BankName = "Vietcombank (DEMO)";
    public const string BankAccountNumber = "0000 1234 5678";
    public const string BankAccountHolder = "CONG TY DRIVO (DEMO)";
}

public class WalletTransactionDto
{
    public long Id { get; set; }
    public int DriverId { get; set; }
    public string? DriverName { get; set; }
    public string? DriverPhone { get; set; }
    public string Type { get; set; } = null!;
    public decimal Amount { get; set; }
    public decimal? BalanceAfter { get; set; }
    public string Status { get; set; } = null!;
    public long? BookingId { get; set; }
    public string? BookingCode { get; set; }
    public string? ReferenceCode { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? ProcessedAt { get; set; }
}

public class BankInfoDto
{
    public string BankName { get; set; } = WalletSettings.BankName;
    public string AccountNumber { get; set; } = WalletSettings.BankAccountNumber;
    public string AccountHolder { get; set; } = WalletSettings.BankAccountHolder;
}

public class DriverWalletResponse
{
    public decimal Balance { get; set; }
    public decimal MinBalance { get; set; } = WalletSettings.MinBalance;
    /// <summary>Đủ số dư tối thiểu để nhận cuốc.</summary>
    public bool CanTakeTrips { get; set; }
    /// <summary>Số có thể rút = số dư − tối thiểu − yêu cầu rút đang chờ.</summary>
    public decimal Withdrawable { get; set; }
    public BankInfoDto DrivoBank { get; set; } = new();
    /// <summary>Tài khoản nhận tiền khai trong hồ sơ tài xế (để rút).</summary>
    public string? PayoutBankName { get; set; }
    public string? PayoutAccountNumber { get; set; }
    public string? PayoutAccountHolder { get; set; }
    public List<WalletTransactionDto> Transactions { get; set; } = [];
}

public class WalletAmountRequest
{
    public decimal Amount { get; set; }
}

public class TopupResponse
{
    public WalletTransactionDto Transaction { get; set; } = null!;
    public BankInfoDto DrivoBank { get; set; } = new();
}

public class AdminWalletRow
{
    public int DriverId { get; set; }
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public decimal Balance { get; set; }
    public bool BelowMinimum { get; set; }
    public int PendingRequests { get; set; }
    public string DriverStatus { get; set; } = null!;
}

public class AdminWalletOverview
{
    public decimal MinBalance { get; set; } = WalletSettings.MinBalance;
    public decimal TotalBalance { get; set; }
    public int DriversBelowMinimum { get; set; }
    public int PendingTopups { get; set; }
    public decimal PendingTopupAmount { get; set; }
    public int PendingWithdrawals { get; set; }
    public decimal PendingWithdrawAmount { get; set; }
    public List<AdminWalletRow> Drivers { get; set; } = [];
    public List<WalletTransactionDto> PendingRequests { get; set; } = [];
}

public class RejectWalletRequest
{
    public string? Reason { get; set; }
}

public class AdjustWalletRequest
{
    /// <summary>Có dấu: + cộng, - trừ.</summary>
    public decimal Amount { get; set; }
    public string Note { get; set; } = null!;
}
