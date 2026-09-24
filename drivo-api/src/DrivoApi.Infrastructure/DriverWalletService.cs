using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Wallet;
using DrivoApi.Application.Services;
using DrivoApi.Domain.Entities;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure;

/// <summary>
/// Ví ký quỹ tài xế. Số dư chỉ đổi bằng UPDATE cộng dồn ở DB (không đọc-rồi-ghi) để các thao tác
/// đồng thời (hoàn thành chuyến + admin duyệt nạp) không đè lên nhau.
/// </summary>
public class DriverWalletService(DrivoDbContext db) : IDriverWalletService
{
    private static string Vnd(decimal v) =>
        v.ToString("#,0", System.Globalization.CultureInfo.GetCultureInfo("vi-VN")) + "đ";

    private static WalletTransactionDto Map(DriverWalletTransaction t, string? bookingCode = null) => new()
    {
        Id = t.Id,
        DriverId = t.DriverId,
        DriverName = t.Driver?.User?.FullName,
        DriverPhone = t.Driver?.User?.Phone,
        Type = t.Type,
        Amount = t.Amount,
        BalanceAfter = t.BalanceAfter,
        Status = t.Status,
        BookingId = t.BookingId,
        BookingCode = bookingCode,
        ReferenceCode = t.ReferenceCode,
        Note = t.Note,
        CreatedAt = t.CreatedAt,
        ProcessedAt = t.ProcessedAt
    };

    /// <summary>Cộng/trừ số dư ở DB. minAfter: chỉ trừ nếu số dư sau vẫn >= minAfter. Trả về số dư mới, null nếu không đủ.</summary>
    private async Task<decimal?> ChangeBalanceAsync(int driverId, decimal delta, decimal? minAfter = null)
    {
        var q = db.Drivers.Where(d => d.Id == driverId);
        if (minAfter is { } min) q = q.Where(d => d.WalletBalance + delta >= min);
        var n = await q.ExecuteUpdateAsync(s => s.SetProperty(d => d.WalletBalance, d => d.WalletBalance + delta));
        if (n == 0) return null;
        return await db.Drivers.Where(d => d.Id == driverId).Select(d => d.WalletBalance).FirstAsync();
    }

    private async Task<Dictionary<long, string>> BookingCodesAsync(IEnumerable<DriverWalletTransaction> txs)
    {
        var ids = txs.Where(t => t.BookingId != null).Select(t => t.BookingId!.Value).Distinct().ToList();
        return ids.Count == 0
            ? []
            : await db.Bookings.Where(b => ids.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.BookingCode);
    }

    private async Task<decimal> PendingWithdrawAsync(int driverId) =>
        -(await db.DriverWalletTransactions
            .Where(t => t.DriverId == driverId && t.Type == WalletTxType.Withdraw && t.Status == WalletTxStatus.Pending)
            .SumAsync(t => (decimal?)t.Amount) ?? 0m);

    // ══════════════════ TÀI XẾ ══════════════════

    public async Task<BaseResponse<DriverWalletResponse>> GetMyWalletAsync(int userId)
    {
        var driver = await db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null) return BaseResponse<DriverWalletResponse>.Fail("Không tìm thấy thông tin tài xế.");

        var txs = await db.DriverWalletTransactions.AsNoTracking()
            .Where(t => t.DriverId == driver.Id)
            .OrderByDescending(t => t.CreatedAt).ThenByDescending(t => t.Id)
            .Take(100)
            .ToListAsync();
        var codes = await BookingCodesAsync(txs);
        var pendingWithdraw = await PendingWithdrawAsync(driver.Id);

        return BaseResponse<DriverWalletResponse>.Ok(new DriverWalletResponse
        {
            Balance = driver.WalletBalance,
            CanTakeTrips = driver.WalletBalance >= WalletSettings.MinBalance,
            Withdrawable = Math.Max(0m, driver.WalletBalance - WalletSettings.MinBalance - pendingWithdraw),
            PayoutBankName = driver.BankName,
            PayoutAccountNumber = driver.BankAccountNumber,
            PayoutAccountHolder = driver.BankAccountHolder,
            Transactions = txs.Select(t => Map(t, t.BookingId is { } b ? codes.GetValueOrDefault(b) : null)).ToList()
        });
    }

    public async Task<BaseResponse<TopupResponse>> RequestTopupAsync(int userId, decimal amount)
    {
        var driver = await db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null) return BaseResponse<TopupResponse>.Fail("Không tìm thấy thông tin tài xế.");
        if (amount < WalletSettings.MinTopup || amount > WalletSettings.MaxTopup)
            return BaseResponse<TopupResponse>.Fail($"Số tiền nạp từ {Vnd(WalletSettings.MinTopup)} đến {Vnd(WalletSettings.MaxTopup)}.");
        if (amount % 1000 != 0)
            return BaseResponse<TopupResponse>.Fail("Số tiền nạp phải chẵn nghìn đồng.");
        if (await db.DriverWalletTransactions.CountAsync(t =>
                t.DriverId == driver.Id && t.Type == WalletTxType.Topup && t.Status == WalletTxStatus.Pending) >= 3)
            return BaseResponse<TopupResponse>.Fail("Bạn đang có 3 yêu cầu nạp chờ duyệt, vui lòng đợi DRIVO xác nhận.");

        // Nội dung chuyển khoản riêng để admin đối chiếu sao kê
        var alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var suffix = new string(Enumerable.Range(0, 4).Select(_ => alphabet[Random.Shared.Next(alphabet.Length)]).ToArray());
        var tx = new DriverWalletTransaction
        {
            DriverId = driver.Id,
            Type = WalletTxType.Topup,
            Amount = amount,
            Status = WalletTxStatus.Pending,
            ReferenceCode = $"DRIVO NAP TX{driver.Id} {suffix}",
            Note = "Nạp tiền vào ví",
            CreatedAt = DateTime.UtcNow
        };
        db.DriverWalletTransactions.Add(tx);
        await db.SaveChangesAsync();

        return BaseResponse<TopupResponse>.Ok(new TopupResponse { Transaction = Map(tx) },
            "Đã tạo yêu cầu nạp. Chuyển khoản đúng nội dung để DRIVO xác nhận.");
    }

    public async Task<BaseResponse<WalletTransactionDto>> RequestWithdrawAsync(int userId, decimal amount)
    {
        var driver = await db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null) return BaseResponse<WalletTransactionDto>.Fail("Không tìm thấy thông tin tài xế.");
        if (string.IsNullOrWhiteSpace(driver.BankAccountNumber))
            return BaseResponse<WalletTransactionDto>.Fail("Vui lòng khai báo tài khoản nhận tiền trong Hồ sơ trước khi rút.");
        if (amount < WalletSettings.MinWithdraw || amount % 1000 != 0)
            return BaseResponse<WalletTransactionDto>.Fail($"Số tiền rút tối thiểu {Vnd(WalletSettings.MinWithdraw)}, chẵn nghìn đồng.");

        var available = driver.WalletBalance - WalletSettings.MinBalance - await PendingWithdrawAsync(driver.Id);
        if (amount > available)
            return BaseResponse<WalletTransactionDto>.Fail(
                $"Chỉ rút được phần vượt mức ký quỹ {Vnd(WalletSettings.MinBalance)}. Có thể rút tối đa {Vnd(Math.Max(0, available))}.");

        var tx = new DriverWalletTransaction
        {
            DriverId = driver.Id,
            Type = WalletTxType.Withdraw,
            Amount = -amount,
            Status = WalletTxStatus.Pending,
            Note = $"Rút về {driver.BankName} {driver.BankAccountNumber} ({driver.BankAccountHolder})",
            CreatedAt = DateTime.UtcNow
        };
        db.DriverWalletTransactions.Add(tx);
        await db.SaveChangesAsync();
        return BaseResponse<WalletTransactionDto>.Ok(Map(tx), "Đã gửi yêu cầu rút tiền, DRIVO sẽ chuyển khoản sau khi duyệt.");
    }

    public async Task<BaseResponse<bool>> CancelMyRequestAsync(int userId, long transactionId)
    {
        var driverId = await db.Drivers.Where(d => d.UserId == userId).Select(d => d.Id).FirstOrDefaultAsync();
        var n = await db.DriverWalletTransactions
            .Where(t => t.Id == transactionId && t.DriverId == driverId && t.Status == WalletTxStatus.Pending &&
                        (t.Type == WalletTxType.Topup || t.Type == WalletTxType.Withdraw))
            .ExecuteUpdateAsync(s => s
                .SetProperty(t => t.Status, WalletTxStatus.Rejected)
                .SetProperty(t => t.Note, t => t.Note + " · Tài xế đã hủy")
                .SetProperty(t => t.ProcessedAt, DateTime.UtcNow));
        return n == 0
            ? BaseResponse<bool>.Fail("Không tìm thấy yêu cầu đang chờ.")
            : BaseResponse<bool>.Ok(true, "Đã hủy yêu cầu.");
    }

    public async Task SettleTripAsync(long bookingId)
    {
        var b = await db.Bookings.AsNoTracking()
            .Where(x => x.Id == bookingId && x.Status == BookingStatus.Completed && x.DriverId != null && x.FinalPrice != null)
            .Select(x => new { x.Id, x.BookingCode, DriverId = x.DriverId!.Value, FinalPrice = x.FinalPrice!.Value, x.DriverPayout, x.PaymentMethod })
            .FirstOrDefaultAsync();
        if (b == null) return;

        // Tiền mặt: tài xế đã cầm FinalPrice -> ví nhận (thực nhận − tiền đã cầm) = −hoa hồng (+ phần DRIVO bù voucher).
        // Trả qua app: DRIVO giữ tiền -> ví nhận toàn bộ phần thực nhận.
        var cash = b.PaymentMethod == PaymentMethod.Cash;
        var delta = cash ? b.DriverPayout - b.FinalPrice : b.DriverPayout;
        var tx = new DriverWalletTransaction
        {
            DriverId = b.DriverId,
            Type = cash ? WalletTxType.TripCash : WalletTxType.TripApp,
            Amount = delta,
            Status = WalletTxStatus.Completed,
            BookingId = b.Id,
            Note = cash
                ? $"Chuyến {b.BookingCode} (tiền mặt {Vnd(b.FinalPrice)}): trừ hoa hồng DRIVO"
                : $"Chuyến {b.BookingCode} (khách trả qua app): cộng thu nhập",
            CreatedAt = DateTime.UtcNow,
            ProcessedAt = DateTime.UtcNow
        };
        db.DriverWalletTransactions.Add(tx);
        try
        {
            await db.SaveChangesAsync(); // UX_DriverWalletTransactions_Booking: chuyến đã cấn trừ thì bỏ qua
        }
        catch (DbUpdateException)
        {
            db.Entry(tx).State = EntityState.Detached;
            return;
        }

        tx.BalanceAfter = await ChangeBalanceAsync(b.DriverId, delta);
        await db.SaveChangesAsync();
    }

    // ══════════════════ ADMIN ══════════════════

    public async Task<BaseResponse<AdminWalletOverview>> GetOverviewAsync()
    {
        var drivers = await db.Drivers.AsNoTracking()
            .Select(d => new AdminWalletRow
            {
                DriverId = d.Id,
                FullName = d.User.FullName,
                Phone = d.User.Phone,
                Balance = d.WalletBalance,
                BelowMinimum = d.WalletBalance < WalletSettings.MinBalance,
                DriverStatus = d.DriverStatus.ToString(),
                PendingRequests = db.DriverWalletTransactions.Count(t => t.DriverId == d.Id && t.Status == WalletTxStatus.Pending)
            })
            .OrderByDescending(d => d.PendingRequests).ThenBy(d => d.Balance)
            .ToListAsync();

        var pending = await db.DriverWalletTransactions.AsNoTracking()
            .Include(t => t.Driver).ThenInclude(d => d.User)
            .Where(t => t.Status == WalletTxStatus.Pending)
            .OrderBy(t => t.CreatedAt)
            .ToListAsync();

        return BaseResponse<AdminWalletOverview>.Ok(new AdminWalletOverview
        {
            TotalBalance = drivers.Sum(d => d.Balance),
            DriversBelowMinimum = drivers.Count(d => d.BelowMinimum),
            PendingTopups = pending.Count(t => t.Type == WalletTxType.Topup),
            PendingTopupAmount = pending.Where(t => t.Type == WalletTxType.Topup).Sum(t => t.Amount),
            PendingWithdrawals = pending.Count(t => t.Type == WalletTxType.Withdraw),
            PendingWithdrawAmount = -pending.Where(t => t.Type == WalletTxType.Withdraw).Sum(t => t.Amount),
            Drivers = drivers,
            PendingRequests = pending.Select(t => Map(t)).ToList()
        });
    }

    public async Task<BaseResponse<List<WalletTransactionDto>>> GetDriverTransactionsAsync(int driverId)
    {
        var txs = await db.DriverWalletTransactions.AsNoTracking()
            .Include(t => t.Driver).ThenInclude(d => d.User)
            .Where(t => t.DriverId == driverId)
            .OrderByDescending(t => t.CreatedAt).ThenByDescending(t => t.Id)
            .Take(300)
            .ToListAsync();
        var codes = await BookingCodesAsync(txs);
        return BaseResponse<List<WalletTransactionDto>>.Ok(
            txs.Select(t => Map(t, t.BookingId is { } b ? codes.GetValueOrDefault(b) : null)).ToList());
    }

    public async Task<BaseResponse<WalletTransactionDto>> ApproveAsync(long transactionId, int adminUserId)
    {
        var tx = await db.DriverWalletTransactions.Include(t => t.Driver).ThenInclude(d => d.User)
            .FirstOrDefaultAsync(t => t.Id == transactionId);
        if (tx == null || tx.Status != WalletTxStatus.Pending)
            return BaseResponse<WalletTransactionDto>.Fail("Yêu cầu không tồn tại hoặc đã được xử lý.");

        // Giữ yêu cầu lại trước (tránh 2 admin duyệt cùng lúc cộng tiền 2 lần)
        var now = DateTime.UtcNow;
        var claimed = await db.DriverWalletTransactions
            .Where(t => t.Id == transactionId && t.Status == WalletTxStatus.Pending)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.Status, WalletTxStatus.Completed)
                .SetProperty(t => t.ProcessedAt, now).SetProperty(t => t.ProcessedBy, adminUserId));
        if (claimed == 0)
            return BaseResponse<WalletTransactionDto>.Fail("Yêu cầu vừa được xử lý bởi người khác.");

        // Rút tiền: số dư sau khi rút vẫn phải >= mức ký quỹ
        var balance = await ChangeBalanceAsync(tx.DriverId, tx.Amount,
            tx.Type == WalletTxType.Withdraw ? WalletSettings.MinBalance : null);
        if (balance == null)
        {
            await db.DriverWalletTransactions.Where(t => t.Id == transactionId)
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.Status, WalletTxStatus.Pending)
                    .SetProperty(t => t.ProcessedAt, (DateTime?)null).SetProperty(t => t.ProcessedBy, (int?)null));
            return BaseResponse<WalletTransactionDto>.Fail(
                $"Số dư không đủ: sau khi rút phải còn ít nhất {Vnd(WalletSettings.MinBalance)}.");
        }

        await db.DriverWalletTransactions.Where(t => t.Id == transactionId)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.BalanceAfter, balance));
        await db.Entry(tx).ReloadAsync();
        return BaseResponse<WalletTransactionDto>.Ok(Map(tx),
            tx.Type == WalletTxType.Topup ? $"Đã cộng {Vnd(tx.Amount)} vào ví." : $"Đã trừ {Vnd(-tx.Amount)} khỏi ví (đã chi trả).");
    }

    public async Task<BaseResponse<WalletTransactionDto>> RejectAsync(long transactionId, int adminUserId, string? reason)
    {
        if (string.IsNullOrWhiteSpace(reason))
            return BaseResponse<WalletTransactionDto>.Fail("Vui lòng nhập lý do từ chối.");
        var now = DateTime.UtcNow;
        var note = " · Từ chối: " + reason.Trim();
        var n = await db.DriverWalletTransactions
            .Where(t => t.Id == transactionId && t.Status == WalletTxStatus.Pending)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.Status, WalletTxStatus.Rejected)
                .SetProperty(t => t.Note, t => t.Note + note)
                .SetProperty(t => t.ProcessedAt, now).SetProperty(t => t.ProcessedBy, adminUserId));
        if (n == 0) return BaseResponse<WalletTransactionDto>.Fail("Yêu cầu không tồn tại hoặc đã được xử lý.");

        var tx = await db.DriverWalletTransactions.AsNoTracking().Include(t => t.Driver).ThenInclude(d => d.User)
            .FirstAsync(t => t.Id == transactionId);
        return BaseResponse<WalletTransactionDto>.Ok(Map(tx), "Đã từ chối yêu cầu.");
    }

    public async Task<BaseResponse<WalletTransactionDto>> AdjustAsync(int driverId, decimal amount, string note, int adminUserId)
    {
        if (amount == 0) return BaseResponse<WalletTransactionDto>.Fail("Số tiền điều chỉnh phải khác 0.");
        if (string.IsNullOrWhiteSpace(note)) return BaseResponse<WalletTransactionDto>.Fail("Vui lòng ghi lý do điều chỉnh.");
        if (!await db.Drivers.AnyAsync(d => d.Id == driverId))
            return BaseResponse<WalletTransactionDto>.Fail("Không tìm thấy tài xế.");

        var now = DateTime.UtcNow;
        var tx = new DriverWalletTransaction
        {
            DriverId = driverId,
            Type = WalletTxType.Adjustment,
            Amount = amount,
            Status = WalletTxStatus.Completed,
            Note = note.Trim(),
            CreatedAt = now,
            ProcessedAt = now,
            ProcessedBy = adminUserId
        };
        db.DriverWalletTransactions.Add(tx);
        await db.SaveChangesAsync();
        tx.BalanceAfter = await ChangeBalanceAsync(driverId, amount);
        await db.SaveChangesAsync();
        return BaseResponse<WalletTransactionDto>.Ok(Map(tx), $"Đã điều chỉnh {(amount > 0 ? "+" : "")}{Vnd(amount)}.");
    }
}
