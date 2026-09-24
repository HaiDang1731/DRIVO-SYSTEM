using DrivoApi.Application.DTOs.Tracking;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.SignalR;

namespace DrivoApi.WebApi.Hubs;

/// <summary>Phát sự kiện tracking qua SignalR. Lỗi phát sóng chỉ được log, không làm hỏng request.</summary>
public class SignalRTrackingNotifier(IHubContext<TrackingHub> hub, ILogger<SignalRTrackingNotifier> logger) : ITrackingNotifier
{
    public async Task DriverLocationAsync(DriverLocationEvent evt)
    {
        try
        {
            var groups = new List<string> { TrackingHub.AdminsGroup };
            if (evt.BookingId.HasValue) groups.Add(TrackingHub.BookingGroup(evt.BookingId.Value));
            await hub.Clients.Groups(groups).SendAsync("DriverLocation", evt);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Không phát được DriverLocation cho tài xế {DriverId}", evt.DriverId);
        }
    }

    public async Task BookingStatusChangedAsync(BookingStatusChangedEvent evt)
    {
        try
        {
            await hub.Clients.Groups(TrackingHub.AdminsGroup, TrackingHub.BookingGroup(evt.BookingId))
                .SendAsync("BookingStatusChanged", evt);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Không phát được BookingStatusChanged cho cuốc {BookingId}", evt.BookingId);
        }
    }
}
