using DrivoApi.Application.DTOs.Admin;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers;

/// <summary>
/// Admin quản lý tài xế — tạo tài khoản, thêm giấy tờ, duyệt hồ sơ
/// </summary>
[ApiController]
[Route("api/v1/admin/drivers")]
[Authorize(Roles = "ADMIN")]
public class AdminDriverController(IAdminDriverService adminDriverService) : ControllerBase
{
    private int AdminUserId =>
        int.TryParse(User.FindFirst("sub")?.Value
            ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : 0;

    /// <summary>
    /// [BƯỚC 1] Admin tạo tài khoản tài xế mới
    /// Mật khẩu mặc định = SĐT nếu không nhập InitialPassword
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> CreateDriver([FromBody] CreateDriverRequest request)
    {
        var result = await adminDriverService.CreateDriverAsync(request, AdminUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>
    /// [BƯỚC 2] Admin thêm giấy tờ cho tài xế (CCCD, GPLX, bảo hiểm...)
    /// </summary>
    [HttpPost("{driverId}/documents")]
    public async Task<IActionResult> AddDocument(
        int driverId, [FromBody] AddDriverDocumentRequest request)
    {
        var result = await adminDriverService.AddDocumentAsync(driverId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>
    /// [BƯỚC 3] Admin duyệt hoặc từ chối hồ sơ tài xế
    /// Status: APPROVED | REJECTED
    /// </summary>
    [HttpPatch("{driverId}/verify")]
    public async Task<IActionResult> VerifyDriver(
        int driverId, [FromBody] VerifyDriverRequest request)
    {
        var result = await adminDriverService.VerifyDriverAsync(driverId, request, AdminUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Admin xem chi tiết 1 tài xế</summary>
    [HttpGet("{driverId}")]
    public async Task<IActionResult> GetDriver(int driverId)
    {
        var result = await adminDriverService.GetDriverByIdAsync(driverId);
        return result.Success ? Ok(result) : NotFound(result);
    }

    /// <summary>Admin xem danh sách tài xế, lọc theo VerificationStatus</summary>
    [HttpGet]
    public async Task<IActionResult> GetDrivers(
        [FromQuery] string? verificationStatus = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var result = await adminDriverService.GetDriversAsync(verificationStatus, page, pageSize);
        return Ok(result);
    }

    /// <summary>Admin khóa / mở khóa tài khoản tài xế</summary>
    [HttpPatch("{driverId}/status")]
    public async Task<IActionResult> SetStatus(
        int driverId, [FromQuery] string status)
    {
        var result = await adminDriverService.SetDriverAccountStatusAsync(driverId, status, AdminUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }
}
