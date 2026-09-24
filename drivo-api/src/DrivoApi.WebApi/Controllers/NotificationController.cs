using DrivoApi.Application.DTOs.Common;
using DrivoApi.Infrastructure.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.WebApi.Controllers;

/// <summary>Người dùng (khách / tài xế) đọc thông báo của mình, gồm thông báo admin gửi hàng loạt.</summary>
[ApiController]
[Route("api/v1/notifications")]
[Authorize]
public class NotificationController(DrivoDbContext db) : ControllerBase
{
    private int CurrentUserId =>
        int.TryParse(User.FindFirst("sub")?.Value
            ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : 0;

    [HttpGet]
    public async Task<IActionResult> GetMine([FromQuery] int take = 50)
    {
        take = Math.Clamp(take, 1, 200);
        var items = await db.Notifications.AsNoTracking()
            .Where(n => n.UserId == CurrentUserId)
            .OrderByDescending(n => n.CreatedAt)
            .Take(take)
            .Select(n => new { n.Id, n.Type, n.Title, n.Message, n.IsRead, n.CreatedAt })
            .ToListAsync();
        var unread = await db.Notifications.CountAsync(n => n.UserId == CurrentUserId && !n.IsRead);
        return Ok(BaseResponse<object>.Ok(new { unread, items }));
    }

    [HttpPost("{id:long}/read")]
    public async Task<IActionResult> MarkRead(long id)
    {
        await db.Notifications
            .Where(n => n.Id == id && n.UserId == CurrentUserId && !n.IsRead)
            .ExecuteUpdateAsync(s => s.SetProperty(n => n.IsRead, true).SetProperty(n => n.ReadAt, DateTime.UtcNow));
        return Ok(BaseResponse<bool>.Ok(true));
    }

    [HttpPost("read-all")]
    public async Task<IActionResult> MarkAllRead()
    {
        var n = await db.Notifications
            .Where(x => x.UserId == CurrentUserId && !x.IsRead)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.IsRead, true).SetProperty(x => x.ReadAt, DateTime.UtcNow));
        return Ok(BaseResponse<int>.Ok(n, "Đã đánh dấu tất cả là đã đọc"));
    }
}
