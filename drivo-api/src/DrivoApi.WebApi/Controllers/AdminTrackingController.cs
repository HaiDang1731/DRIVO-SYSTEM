using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Tracking;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.WebApi.Controllers;

/// <summary>Bản đồ giám sát realtime cho admin (dữ liệu ban đầu; cập nhật tiếp qua SignalR /hubs/tracking).</summary>
[ApiController]
[Route("api/v1/admin/tracking")]
[Authorize(Roles = "ADMIN,Admin")]
public class AdminTrackingController(DrivoDbContext db) : ControllerBase
{
    /// <summary>Tài xế đã có vị trí, kèm cuốc đang chạy (nếu có)</summary>
    [HttpGet("drivers")]
    public async Task<IActionResult> GetDrivers()
    {
        var drivers = await db.Drivers.AsNoTracking()
            .Where(d => d.CurrentLatitude != null && d.CurrentLongitude != null)
            .Select(d => new
            {
                d.Id,
                d.UserId,
                d.User.FullName,
                d.User.Phone,
                d.User.AvatarUrl,
                d.DriverStatus,
                d.VerificationStatus,
                Lat = d.CurrentLatitude!.Value,
                Lng = d.CurrentLongitude!.Value,
                d.LastLocationAt
            })
            .ToListAsync();

        var driverIds = drivers.Select(d => d.Id).ToList();
        var activeBookings = await db.Bookings.AsNoTracking()
            .Where(b => b.DriverId != null && driverIds.Contains(b.DriverId.Value) &&
                        b.Status != BookingStatus.Completed && b.Status != BookingStatus.Cancelled)
            .OrderByDescending(b => b.CreatedAt)
            .Select(b => new { DriverId = b.DriverId!.Value, b.Id, b.BookingCode, b.Status })
            .ToListAsync();
        var activeByDriver = activeBookings
            .GroupBy(b => b.DriverId)
            .ToDictionary(g => g.Key, g => g.First());

        var result = drivers.Select(d =>
        {
            activeByDriver.TryGetValue(d.Id, out var ab);
            return new AdminTrackingDriverDto
            {
                DriverId = d.Id,
                UserId = d.UserId,
                FullName = d.FullName,
                Phone = d.Phone,
                AvatarUrl = d.AvatarUrl,
                DriverStatus = d.DriverStatus.ToString(),
                VerificationStatus = d.VerificationStatus.ToString(),
                Latitude = d.Lat,
                Longitude = d.Lng,
                LastLocationAt = d.LastLocationAt,
                ActiveBookingId = ab?.Id,
                ActiveBookingCode = ab?.BookingCode,
                ActiveBookingStatus = ab?.Status.ToString()
            };
        }).ToList();

        return Ok(BaseResponse<List<AdminTrackingDriverDto>>.Ok(result));
    }

    /// <summary>Các cuốc chưa kết thúc (chưa Completed/Cancelled)</summary>
    [HttpGet("bookings/active")]
    public async Task<IActionResult> GetActiveBookings()
    {
        var list = await db.Bookings.AsNoTracking()
            .Where(b => b.Status != BookingStatus.Completed && b.Status != BookingStatus.Cancelled)
            .OrderByDescending(b => b.CreatedAt)
            .Select(b => new
            {
                b.Id,
                b.BookingCode,
                b.Status,
                b.PickupAddress,
                b.PickupLatitude,
                b.PickupLongitude,
                b.DestinationAddress,
                b.DestinationLatitude,
                b.DestinationLongitude,
                b.RoutePolyline,
                CustomerName = b.Customer.User.FullName,
                CustomerPhone = b.Customer.User.Phone,
                b.DriverId,
                DriverName = b.Driver != null ? b.Driver.User.FullName : null,
                DriverLatitude = b.Driver != null ? b.Driver.CurrentLatitude : null,
                DriverLongitude = b.Driver != null ? b.Driver.CurrentLongitude : null,
                b.EstimatedPrice,
                b.CreatedAt
            })
            .ToListAsync();

        var result = list.Select(b => new AdminTrackingBookingDto
        {
            Id = b.Id,
            BookingCode = b.BookingCode,
            Status = b.Status.ToString(),
            PickupAddress = b.PickupAddress,
            PickupLatitude = b.PickupLatitude,
            PickupLongitude = b.PickupLongitude,
            DestinationAddress = b.DestinationAddress,
            DestinationLatitude = b.DestinationLatitude,
            DestinationLongitude = b.DestinationLongitude,
            RoutePolyline = b.RoutePolyline,
            CustomerName = b.CustomerName,
            CustomerPhone = b.CustomerPhone,
            DriverId = b.DriverId,
            DriverName = b.DriverName,
            DriverLatitude = b.DriverLatitude,
            DriverLongitude = b.DriverLongitude,
            EstimatedPrice = b.EstimatedPrice,
            CreatedAt = b.CreatedAt
        }).ToList();

        return Ok(BaseResponse<List<AdminTrackingBookingDto>>.Ok(result));
    }
}
