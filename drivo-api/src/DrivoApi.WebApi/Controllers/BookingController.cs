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

    /// <summary>Khách chờ lâu bấm "Làm mới": tìm tài xế lại từ đầu</summary>
    [HttpPost("{id:long}/retry-search")]
    [Authorize(Roles = "CUSTOMER")]
    public async Task<IActionResult> RetrySearch(long id)
    {
        var result = await bookingService.RetrySearchAsync(id, CurrentUserId);
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

    /// <summary>Số liệu tài khoản khách: số chuyến, tổng chi, tiền tiết kiệm nhờ khuyến mãi</summary>
    [HttpGet("customer-summary")]
    [Authorize(Roles = "CUSTOMER")]
    public async Task<IActionResult> GetCustomerSummary()
    {
        var result = await bookingService.GetCustomerSummaryAsync(CurrentUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Danh sách mã khuyến mãi khách còn dùng được</summary>
    [HttpGet("vouchers")]
    [Authorize(Roles = "CUSTOMER")]
    public async Task<IActionResult> GetVouchers()
    {
        var result = await bookingService.GetAvailableVouchersAsync(CurrentUserId);
        return Ok(result);
    }

    /// <summary>Kiểm tra mã khuyến mãi và số tiền được giảm cho giá ước tính</summary>
    [HttpPost("vouchers/check")]
    [Authorize(Roles = "CUSTOMER")]
    public async Task<IActionResult> CheckVoucher([FromBody] CheckVoucherRequest request)
    {
        var result = await bookingService.CheckVoucherAsync(CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    [HttpPost("{id:long}/rate")]
    public async Task<IActionResult> RateBooking(long id, [FromBody] DrivoApi.Application.DTOs.Booking.RateBookingRequest req)
    {
        var result = await bookingService.RateBookingAsync(id, CurrentUserId, req.Score, req.Comment ?? string.Empty);
        return result.Success ? Ok(result) : BadRequest(result);
    }
}