using DrivoApi.Application.DTOs.Auth;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers;

[ApiController]
[Route("api/v1/auth")]
public class AuthController(IAuthService authService) : ControllerBase
{
    /// <summary>Đăng ký tài khoản mới (CUSTOMER hoặc DRIVER)</summary>
    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        var result = await authService.RegisterAsync(request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Đăng nhập bằng số điện thoại và mật khẩu</summary>
    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var result = await authService.LoginAsync(request);
        return result.Success ? Ok(result) : Unauthorized(result);
    }

    /// <summary>Làm mới Access Token bằng Refresh Token</summary>
    [HttpPost("refresh")]
    [AllowAnonymous]
    public async Task<IActionResult> Refresh([FromBody] RefreshTokenRequest request)
    {
        var result = await authService.RefreshTokenAsync(request.RefreshToken);
        return result.Success ? Ok(result) : Unauthorized(result);
    }

    /// <summary>Đăng xuất - thu hồi Refresh Token</summary>
    [HttpPost("logout")]
    [AllowAnonymous]
    public async Task<IActionResult> Logout([FromBody] RefreshTokenRequest request)
    {
        var result = await authService.LogoutAsync(request.RefreshToken);
        return Ok(result);
    }

    /// <summary>Lấy thông tin user hiện tại (test auth)</summary>
    [HttpGet("me")]
    [Authorize]
    public IActionResult Me()
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                  ?? User.FindFirst("sub")?.Value;
        var roles = User.FindAll(System.Security.Claims.ClaimTypes.Role)
                        .Select(c => c.Value).ToList();
        return Ok(new { UserId = userId, Roles = roles, Message = "Token hợp lệ!" });
    }
}
