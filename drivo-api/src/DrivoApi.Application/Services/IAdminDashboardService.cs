using System.Collections.Generic;
using System.Threading.Tasks;
using DrivoApi.Application.DTOs.Admin;

namespace DrivoApi.Application.Services
{
    public interface IAdminDashboardService
    {
        Task<DashboardOverviewDto> GetOverviewStatsAsync();
        Task<List<RevenueChartItemDto>> GetRevenueChartAsync(int days);
    }
}
