using DrivoApi.Application.DTOs.Booking;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers;

[ApiController]
[Route("api/v1/bookings")]
[Authorize]
public class BookingController(IBookingService bookingService) : ControllerBase
{
    private int CurrentUserId =>
        int.TryParse(User.FindFirst("sub")?.Value
            ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : 0;

    /// <summary>Ước tính giá cước theo tọa độ và loại xe</summary>
    [HttpPost("estimate")]
    public async Task<IActionResult> EstimateFare([FromBody] EstimateFareRequest request)
    {
        var result = await bookingService.EstimateFareAsync(request);
        return Ok(result);
    }

    /// <summary>Khách hàng tạo cuốc đặt tài xế mới</summary>
    [HttpPost]
    [Authorize(Roles = "CUSTOMER")]
    public async Task<IActionResult> CreateBooking([FromBody] CreateBookingRequest request)
    {
        var result = await bookingService.CreateBookingAsync(CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Lấy cuốc xe đang hoạt động của khách hàng</summary>
    [HttpGet("active")]
    [Authorize(Roles = "CUSTOMER")]
    public async Task<IActionResult> GetActiveBooking()
    {
        var result = await bookingService.GetActiveBookingAsync(CurrentUserId);
        return Ok(result);
    }

    /// <summary>Lấy chi tiết cuốc xe</summary>
    [HttpGet("{id:long}")]
    public async Task<IActionResult> GetBookingById(long id)
    {
        var result = await bookingService.GetBookingByIdAsync(id, CurrentUserId);
        return result.Success ? Ok(result) : NotFound(result);
    }

    /// <summary>Khách hàng hủy chuyến</summary>
    [HttpPost("{id:long}/cancel")]
    [Authorize(Roles = "CUSTOMER")]
    public async Task<IActionResult> CancelBooking(long id, [FromBody] CancelBookingRequest request)
    {
        var result = await bookingService.CancelBookingAsync(id, CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Lịch sử chuyến đi của khách</summary>
    [HttpGet("customer-history")]
    [Authorize(Roles = "CUSTOMER")]
    public async Task<IActionResult> GetCustomerBookings([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var result = await bookingService.GetCustomerBookingsAsync(CurrentUserId, page, pageSize);
        return Ok(result);
    }
}
