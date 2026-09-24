using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using DrivoApi.Application.DTOs.Admin;
using DrivoApi.Application.Services;
using DrivoApi.Domain.Entities;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure
{
    public class AdminDashboardService : IAdminDashboardService
    {
        private readonly DrivoDbContext _context;

        public AdminDashboardService(DrivoDbContext context)
        {
            _context = context;
        }

        public async Task<DashboardOverviewDto> GetOverviewStatsAsync()
        {
            var today = DateTime.UtcNow.Date;

            var totalDrivers = await _context.Users.CountAsync(u => u.UserRoles.Any(r => r.Role.Name == "Driver"));
            var pendingDrivers = await _context.Drivers.CountAsync(d => d.VerificationStatus == VerificationStatus.Pending);
            var totalCustomers = await _context.Users.CountAsync(u => u.UserRoles.Any(r => r.Role.Name == "Customer"));

            var todayTrips = await _context.Bookings
                .Where(b => b.CreatedAt >= today)
                .CountAsync();

            var todayRevenue = await _context.Bookings
                .Where(b => b.CreatedAt >= today && b.Status == BookingStatus.Completed)
                .SumAsync(b => b.FinalPrice);

            return new DashboardOverviewDto
            {
                TotalDrivers = totalDrivers,
                TotalPendingDrivers = pendingDrivers,
                TotalCustomers = totalCustomers,
                TotalTripsToday = todayTrips,
                TotalRevenueToday = todayRevenue ?? 0
            };
        }

        public async Task<List<RevenueChartItemDto>> GetRevenueChartAsync(int days)
        {
            if (days <= 0 || days > 365) days = 7;
            var startDate = DateTime.UtcNow.Date.AddDays(-days + 1);

            var rawData = await _context.Bookings
                .Where(b => b.CreatedAt >= startDate && (b.Status == BookingStatus.Completed || b.Status == BookingStatus.DriverArrived || b.Status == BookingStatus.InProgress || b.Status == BookingStatus.DriverAssigned))
                .ToListAsync();

            var chart = new List<RevenueChartItemDto>();
            for (int i = 0; i < days; i++)
            {
                var d = startDate.AddDays(i);
                var dailyBookings = rawData.Where(b => b.CreatedAt.Date == d).ToList();
                var completedBookings = dailyBookings.Where(b => b.Status == BookingStatus.Completed).ToList();

                chart.Add(new RevenueChartItemDto
                {
                    Date = d.ToString("yyyy-MM-dd"),
                    TripsCount = dailyBookings.Count,
                    Revenue = completedBookings.Sum(b => b.FinalPrice ?? 0)
                });
            }

            return chart;
        }
    }
}
