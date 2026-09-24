using System.Threading.Tasks;
using DrivoApi.Application.DTOs;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers
{
    [ApiController]
    [Route("api/v1/admin/dashboard")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminDashboardController : ControllerBase
    {
        private readonly IAdminDashboardService _dashboardService;

        public AdminDashboardController(IAdminDashboardService dashboardService)
        {
            _dashboardService = dashboardService;
        }

        [HttpGet("overview")]
        public async Task<IActionResult> GetOverview()
        {
            var stats = await _dashboardService.GetOverviewStatsAsync();
            return Ok(BaseResponse<object>.Ok(stats, "Overview stats retrieved successfully."));
        }

        [HttpGet("chart-revenue")]
        public async Task<IActionResult> GetRevenueChart([FromQuery] int days = 7)
        {
            var chart = await _dashboardService.GetRevenueChartAsync(days);
            return Ok(BaseResponse<object>.Ok(chart, "Chart data retrieved successfully."));
        }
    }
}
