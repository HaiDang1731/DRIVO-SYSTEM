using DrivoApi.Application.DTOs.Wallet;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers;

/// <summary>Admin quản lý ví tài xế: duyệt nạp/rút, xem lịch sử, điều chỉnh số dư.</summary>
[ApiController]
[Route("api/v1/admin/wallets")]
[Authorize(Roles = "ADMIN,Admin")]
public class AdminWalletController(IDriverWalletService wallet) : ControllerBase
{
    private int AdminUserId =>
        int.TryParse(User.FindFirst("sub")?.Value
            ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : 0;

    [HttpGet]
    public async Task<IActionResult> Overview() => Ok(await wallet.GetOverviewAsync());

    [HttpGet("drivers/{driverId:int}/transactions")]
    public async Task<IActionResult> DriverTransactions(int driverId) => Ok(await wallet.GetDriverTransactionsAsync(driverId));

    [HttpPost("transactions/{id:long}/approve")]
    public async Task<IActionResult> Approve(long id)
    {
        var result = await wallet.ApproveAsync(id, AdminUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    [HttpPost("transactions/{id:long}/reject")]
    public async Task<IActionResult> Reject(long id, [FromBody] RejectWalletRequest req)
    {
        var result = await wallet.RejectAsync(id, AdminUserId, req.Reason);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    [HttpPost("drivers/{driverId:int}/adjust")]
    public async Task<IActionResult> Adjust(int driverId, [FromBody] AdjustWalletRequest req)
    {
        var result = await wallet.AdjustAsync(driverId, req.Amount, req.Note, AdminUserId);
        return result.Success ? Ok(result) : BadRequest(result);
    }
}
