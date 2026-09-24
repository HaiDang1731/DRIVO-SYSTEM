using DrivoApi.Application.DTOs.Driver;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers;

/// <summary>
/// Tài xế tự quản lý profile, trạng thái, và cuốc xe
/// </summary>
[ApiController]
[Route("api/v1/driver")]
[Authorize(Roles = "DRIVER")]
public class DriverController(IDriverProfileService driverProfileService, IBookingService bookingService) : ControllerBase
{
    private int CurrentUserId =>
        int.TryParse(User.FindFirst("sub")?.Value
            ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : 0;

    // ── Profile ──────────────────────────────────────────────

    /// <summary>Xem thông tin cá nhân</summary>
    [HttpGet("profile")]
    public async Task<IActionResult> GetProfile()
    {
        var result = await driverProfileService.GetMyProfileAsync(CurrentUserId);
        return result.Success ? Ok(result) : NotFound(result);
    }

    /// <summary>Cập nhật thông tin cá nhân</summary>
    [HttpPut("profile")]
    public async Task<IActionResult> UpdateProfile([FromBody] UpdateDriverProfileRequest request)
    {
        var result = await driverProfileService.UpdateProfileAsync(CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Đổi mật khẩu</summary>
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest request)
    {
        var result = await driverProfileService.ChangePasswordAsync(CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    // ── Status ───────────────────────────────────────────────

    /// <summary>Bật / Tắt trực tuyến để nhận cuốc</summary>
    [HttpPost("toggle-status")]
    public async Task<IActionResult> ToggleStatus([FromBody] ToggleDriverStatusRequest request)
    {
        var result = await bookingService.ToggleDriverStatusAsync(CurrentUserId, request.IsOnline, request.Latitude, request.Longitude);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Cập nhật vị trí GPS hiện tại (gọi định kỳ khi trực tuyến / đang chạy cuốc)</summary>
    [HttpPost("location")]
    public async Task<IActionResult> UpdateLocation([FromBody] DrivoApi.Application.DTOs.Tracking.UpdateDriverLocationRequest request)
    {
        var result = await bookingService.UpdateDriverLocationAsync(CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    // ── Booking ──────────────────────────────────────────────

    /// <summary>Lấy danh sách cuốc đang tìm tài xế</summary>
    [HttpGet("pending-bookings")]
    public async Task<IActionResult> GetPendingBookings()
    {
        var result = await bookingService.GetPendingBookingsAsync(CurrentUserId);
        return Ok(result);
    }

    /// <summary>Tài xế nhận cuốc</summary>
    [HttpPost("bookings/{id:long}/accept")]
    public async Task<IActionResult> AcceptBooking(long id)
    {
        var result = await bookingService.AcceptBookingAsync(id, CurrentUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Tài xế bỏ qua cuốc đang được gửi cho mình -> chuyển ngay cho tài xế tiếp theo</summary>
    [HttpPost("bookings/{id:long}/reject")]
    public async Task<IActionResult> RejectBooking(long id)
    {
        var result = await bookingService.RejectBookingAsync(id, CurrentUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Tài xế hủy chuyến</summary>
    [HttpPost("bookings/{id:long}/cancel")]
    public async Task<IActionResult> CancelBooking(long id, [FromBody] DrivoApi.Application.DTOs.Booking.CancelBookingRequest request)
    {
        var result = await bookingService.CancelBookingByDriverAsync(id, CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Cập nhật trạng thái cuốc (DriverArriving → DriverArrived → InProgress → Completed)</summary>
    [HttpPost("bookings/{id:long}/update-status")]
    public async Task<IActionResult> UpdateBookingStatus(long id, [FromBody] UpdateBookingStatusRequest request)
    {
        var result = await bookingService.UpdateBookingStatusAsync(id, CurrentUserId, request.Status);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Cuốc đang thực hiện của tài xế</summary>
    [HttpGet("bookings/active")]
    public async Task<IActionResult> GetActiveBooking()
    {
        var result = await bookingService.GetDriverActiveBookingAsync(CurrentUserId);
        return Ok(result);
    }

    /// <summary>Thu nhập theo kỳ (day | week | month) chứa ngày date (yyyy-MM-dd, giờ VN; mặc định hôm nay)</summary>
    [HttpGet("earnings")]
    public async Task<IActionResult> GetEarnings([FromQuery] string period = "day", [FromQuery] DateTime? date = null)
    {
        var result = await bookingService.GetDriverEarningsAsync(CurrentUserId, period, date);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Lịch sử chuyến đi đã hoàn thành</summary>
    [HttpGet("bookings/history")]
    public async Task<IActionResult> GetBookingHistory([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var result = await bookingService.GetDriverBookingHistoryAsync(CurrentUserId, page, pageSize);
        return Ok(result);
    }
}
