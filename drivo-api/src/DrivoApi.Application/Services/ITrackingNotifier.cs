using DrivoApi.Application.DTOs.Tracking;

namespace DrivoApi.Application.Services;

/// <summary>
/// Phát sự kiện realtime (SignalR TrackingHub). Triển khai ở WebApi để Infrastructure
/// không phụ thuộc ASP.NET Core. Không bao giờ ném lỗi.
/// </summary>
public interface ITrackingNotifier
{
    Task DriverLocationAsync(DriverLocationEvent evt);
    Task BookingStatusChangedAsync(BookingStatusChangedEvent evt);
}
