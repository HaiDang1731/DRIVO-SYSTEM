using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Wallet;

namespace DrivoApi.Application.Services;

public interface IDriverWalletService
{
    // Tài xế
    Task<BaseResponse<DriverWalletResponse>> GetMyWalletAsync(int userId);
    Task<BaseResponse<TopupResponse>> RequestTopupAsync(int userId, decimal amount);
    Task<BaseResponse<WalletTransactionDto>> RequestWithdrawAsync(int userId, decimal amount);
    Task<BaseResponse<bool>> CancelMyRequestAsync(int userId, long transactionId);

    /// <summary>Cấn trừ ví khi chuyến hoàn thành (idempotent: mỗi chuyến 1 lần).</summary>
    Task SettleTripAsync(long bookingId);

    // Admin
    Task<BaseResponse<AdminWalletOverview>> GetOverviewAsync();
    Task<BaseResponse<List<WalletTransactionDto>>> GetDriverTransactionsAsync(int driverId);
    Task<BaseResponse<WalletTransactionDto>> ApproveAsync(long transactionId, int adminUserId);
    Task<BaseResponse<WalletTransactionDto>> RejectAsync(long transactionId, int adminUserId, string? reason);
    Task<BaseResponse<WalletTransactionDto>> AdjustAsync(int driverId, decimal amount, string note, int adminUserId);
}
