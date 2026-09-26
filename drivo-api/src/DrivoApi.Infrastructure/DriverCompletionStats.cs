using DrivoApi.Application.DTOs.Admin;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure;

/// <summary>
/// Tỉ lệ hoàn thành của tài xế (dùng chung cho điều phối cuốc và trang admin):
/// hoàn thành / (hoàn thành + lần hủy do lỗi tài xế), trong 30 ngày gần nhất.
/// Khách tự hủy, khách vắng mặt / không giao xe (DriverAtFault = 0) không tính.
/// </summary>
public static class DriverCompletionStats
{
    public const int WindowDays = 30;
    /// <summary>Dưới số chuyến này coi là chưa đủ dữ liệu (điều phối tạm tính 90%).</summary>
    public const int MinTrips = 3;

    public static async Task<Dictionary<int, DriverCompletionDto>> QueryAsync(DrivoDbContext db, ICollection<int> driverIds)
    {
        var from = DateTime.UtcNow.AddDays(-WindowDays);
        var rows = await db.Bookings.AsNoTracking()
            .Where(x => x.DriverId != null && driverIds.Contains(x.DriverId.Value) && x.CreatedAt >= from &&
                        (x.Status == BookingStatus.Completed || x.Status == BookingStatus.Cancelled))
            .GroupBy(x => x.DriverId!.Value)
            .Select(g => new
            {
                DriverId = g.Key,
                Completed = g.Count(x => x.Status == BookingStatus.Completed),
                DriverFault = g.Count(x => x.Status == BookingStatus.Cancelled && x.DriverAtFault),
                NoFault = g.Count(x => x.Status == BookingStatus.Cancelled && !x.DriverAtFault),
            })
            .ToListAsync();

        var result = driverIds.Distinct().ToDictionary(id => id, _ => new DriverCompletionDto());
        foreach (var r in rows)
        {
            var dto = result[r.DriverId];
            dto.Completed = r.Completed;
            dto.DriverFaultCancelled = r.DriverFault;
            dto.NoFaultCancelled = r.NoFault;
        }
        foreach (var dto in result.Values)
        {
            var total = dto.Completed + dto.DriverFaultCancelled;
            dto.Rate = total >= MinTrips ? Math.Round(100.0 * dto.Completed / total, 1) : null;
        }
        return result;
    }
}
