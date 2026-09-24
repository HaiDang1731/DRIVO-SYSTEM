using System.Security.Claims;
using DrivoApi.Infrastructure.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.WebApi.Hubs;

/// <summary>
/// Realtime tracking. Client → server: JoinBooking, LeaveBooking, JoinAdmin.
/// Server → client: "DriverLocation", "BookingStatusChanged".
/// JWT qua query ?access_token= (đã cấu hình trong Program.cs).
/// </summary>
[Authorize]
public class TrackingHub(DrivoDbContext db) : Hub
{
    public const string AdminsGroup = "admins";
    public static string BookingGroup(long bookingId) => $"booking-{bookingId}";

    private int CurrentUserId =>
        int.TryParse(Context.User?.FindFirst("sub")?.Value
            ?? Context.User?.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : 0;

    private bool IsAdmin => Context.User != null &&
        (Context.User.IsInRole("ADMIN") || Context.User.IsInRole("Admin"));

    /// <summary>Tham gia nhóm theo dõi cuốc — chỉ khách/tài xế của cuốc (hoặc admin).</summary>
    public async Task JoinBooking(long bookingId)
    {
        var userId = CurrentUserId;
        var allowed = IsAdmin || await db.Bookings.AsNoTracking().AnyAsync(b =>
            b.Id == bookingId &&
            (b.Customer.UserId == userId || (b.Driver != null && b.Driver.UserId == userId)));

        if (!allowed)
            throw new HubException("Bạn không có quyền theo dõi cuốc xe này.");

        await Groups.AddToGroupAsync(Context.ConnectionId, BookingGroup(bookingId));
    }

    public Task LeaveBooking(long bookingId) =>
        Groups.RemoveFromGroupAsync(Context.ConnectionId, BookingGroup(bookingId));

    public async Task JoinAdmin()
    {
        if (!IsAdmin)
            throw new HubException("Chỉ quản trị viên được tham gia nhóm admins.");

        await Groups.AddToGroupAsync(Context.ConnectionId, AdminsGroup);
    }
}
