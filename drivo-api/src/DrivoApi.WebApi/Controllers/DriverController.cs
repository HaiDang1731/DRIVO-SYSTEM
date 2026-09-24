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

    private static readonly Dictionary<string, string> AllowedImageTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["image/jpeg"] = ".jpg",
        ["image/png"] = ".png",
        ["image/webp"] = ".webp",
    };
    private const long MaxDocumentBytes = 5 * 1024 * 1024;

    /// <summary>Tải ảnh giấy tờ: DRIVER_LICENSE_FRONT | DRIVER_LICENSE_BACK | CCCD_FRONT | CCCD_BACK | PROFILE_PHOTO</summary>
    [HttpPost("documents")]
    [RequestSizeLimit(MaxDocumentBytes + 64 * 1024)]
    public async Task<IActionResult> UploadDocument([FromForm] string documentType, IFormFile? file,
        [FromServices] IWebHostEnvironment env)
    {
        documentType = (documentType ?? string.Empty).Trim().ToUpperInvariant();
        if (!DriverDocumentTypes.Required.Contains(documentType))
            return BadRequest(DrivoApi.Application.DTOs.Common.BaseResponse<object>.Fail("Loại giấy tờ không hợp lệ."));
        if (file == null || file.Length == 0)
            return BadRequest(DrivoApi.Application.DTOs.Common.BaseResponse<object>.Fail("Vui lòng chọn ảnh."));
        if (file.Length > MaxDocumentBytes)
            return BadRequest(DrivoApi.Application.DTOs.Common.BaseResponse<object>.Fail("Ảnh tối đa 5 MB."));
        if (!AllowedImageTypes.TryGetValue(file.ContentType ?? string.Empty, out var ext) || !await LooksLikeImageAsync(file))
            return BadRequest(DrivoApi.Application.DTOs.Common.BaseResponse<object>.Fail("Chỉ nhận ảnh JPG, PNG hoặc WEBP."));

        // Tên file ngẫu nhiên, không dùng tên client gửi lên
        var webRoot = env.WebRootPath ?? Path.Combine(env.ContentRootPath, "wwwroot");
        var dir = Path.Combine(webRoot, "uploads", "drivers", CurrentUserId.ToString());
        Directory.CreateDirectory(dir);
        var fileName = $"{documentType.ToLowerInvariant()}-{Guid.NewGuid():N}{ext}";
        await using (var fs = System.IO.File.Create(Path.Combine(dir, fileName)))
            await file.CopyToAsync(fs);

        var url = $"/uploads/drivers/{CurrentUserId}/{fileName}";
        var result = await driverProfileService.UploadDocumentAsync(CurrentUserId, documentType, url);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    // ── Ví tài xế ────────────────────────────────────────────

    /// <summary>Số dư, mức ký quỹ, tài khoản DRIVO để nạp, lịch sử giao dịch</summary>
    [HttpGet("wallet")]
    public async Task<IActionResult> GetWallet([FromServices] IDriverWalletService wallet)
    {
        var result = await wallet.GetMyWalletAsync(CurrentUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Tạo yêu cầu nạp tiền (trả về nội dung chuyển khoản), admin duyệt sau khi nhận tiền</summary>
    [HttpPost("wallet/topup")]
    public async Task<IActionResult> Topup([FromBody] DrivoApi.Application.DTOs.Wallet.WalletAmountRequest req,
        [FromServices] IDriverWalletService wallet)
    {
        var result = await wallet.RequestTopupAsync(CurrentUserId, req.Amount);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Tạo yêu cầu rút tiền (chỉ phần vượt mức ký quỹ)</summary>
    [HttpPost("wallet/withdraw")]
    public async Task<IActionResult> Withdraw([FromBody] DrivoApi.Application.DTOs.Wallet.WalletAmountRequest req,
        [FromServices] IDriverWalletService wallet)
    {
        var result = await wallet.RequestWithdrawAsync(CurrentUserId, req.Amount);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Tài xế hủy yêu cầu nạp/rút đang chờ</summary>
    [HttpPost("wallet/requests/{id:long}/cancel")]
    public async Task<IActionResult> CancelWalletRequest(long id, [FromServices] IDriverWalletService wallet)
    {
        var result = await wallet.CancelMyRequestAsync(CurrentUserId, id);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Kiểm tra chữ ký đầu file (JPEG / PNG / WEBP), không tin Content-Type client gửi.</summary>
    private static async Task<bool> LooksLikeImageAsync(IFormFile file)
    {
        var head = new byte[12];
        await using var s = file.OpenReadStream();
        var n = await s.ReadAtLeastAsync(head, head.Length, throwOnEndOfStream: false);
        if (n >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) return true;
        if (n >= 8 && head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4E && head[3] == 0x47) return true;
        return n >= 12 && head[0] == 'R' && head[1] == 'I' && head[2] == 'F' && head[3] == 'F'
                       && head[8] == 'W' && head[9] == 'E' && head[10] == 'B' && head[11] == 'P';
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

    /// <summary>Tài xế xác nhận khách vẫn đi, tiếp tục chờ (sau thời gian chờ miễn phí) -> báo khách phí chờ bắt đầu tính</summary>
    [HttpPost("bookings/{id:long}/keep-waiting")]
    public async Task<IActionResult> KeepWaiting(long id)
    {
        var result = await bookingService.KeepWaitingAsync(id, CurrentUserId);
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
