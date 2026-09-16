using DrivoApi.Application.DTOs.Customer;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers;

[ApiController]
[Route("api/v1/customer/vehicles")]
[Authorize(Roles = "CUSTOMER")]
public class CustomerVehicleController(ICustomerVehicleService vehicleService) : ControllerBase
{
    private int CurrentUserId =>
        int.TryParse(User.FindFirst("sub")?.Value
            ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
        ? id : 0;

    /// <summary>Lấy danh sách xe đã lưu của khách hàng</summary>
    [HttpGet]
    public async Task<IActionResult> GetVehicles()
    {
        var result = await vehicleService.GetVehiclesAsync(CurrentUserId);
        return Ok(result);
    }

    /// <summary>Thêm xe ô tô mới cho khách hàng</summary>
    [HttpPost]
    public async Task<IActionResult> AddVehicle([FromBody] CreateCustomerVehicleRequest request)
    {
        var result = await vehicleService.AddVehicleAsync(CurrentUserId, request);
        return result.Success ? Ok(result) : BadRequest(result);
    }

    /// <summary>Xóa xe ô tô khỏi danh sách</summary>
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> DeleteVehicle(int id)
    {
        var result = await vehicleService.DeleteVehicleAsync(CurrentUserId, id);
        return result.Success ? Ok(result) : NotFound(result);
    }
}
