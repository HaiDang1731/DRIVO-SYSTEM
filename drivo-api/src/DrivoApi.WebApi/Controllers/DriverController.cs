using DrivoApi.Application.DTOs.Driver;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers;

/// <summary>
/// Tài xế tự quản lý profile và đổi mật khẩu sau khi đăng nhập
/// </summary>
[ApiController]
[Route("api/v1/driver")]
[Authorize(Roles = "DRIVER")]
public class DriverController(IDriverProfileService driverProfileService) : ControllerBase
{
    private int CurrentUserId =>
        int.TryParse(User.FindFirst("sub")?.Value
            ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : 0;

    /// <summary>
    /// Xem thông tin cá nhân
    /// IsFirstLogin = true → nhắc tài xế đổi mật khẩu
    /// </summary>
    [HttpGet("profile")]
    public async Task<IActionResult> GetProfile()
    {
        var result = await driverProfileService.GetMyProfileAsync(CurrentUserId);
        return result.Success ? Ok(result) : NotFound(result);
    }

    /// <summary>Cập nhật thông tin cá nhân (tên, email, GPLX, ảnh đại diện)</summary>
    [HttpPut("profile")]
    public async Task<IActionResult> UpdateProfile([FromBody] UpdateDriverProfileRequest request)
    {
        var result = await driverProfileService.UpdateProfileAsync(CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>
    /// Đổi mật khẩu
    /// Lần đầu đăng nhập: CurrentPassword = SĐT (mật khẩu mặc định)
    /// </summary>
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest request)
    {
        var result = await driverProfileService.ChangePasswordAsync(CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }
}
