using System;
using System.Collections.Generic;

namespace DrivoApi.Application.DTOs.Admin
{
    public class DashboardOverviewDto
    {
        public int TotalDrivers { get; set; }
        public int TotalPendingDrivers { get; set; }
        public int TotalCustomers { get; set; }
        public int TotalTripsToday { get; set; }
        public decimal TotalRevenueToday { get; set; }
    }

    public class RevenueChartItemDto
    {
        public string Date { get; set; } = string.Empty; // Format: YYYY-MM-DD
        public int TripsCount { get; set; }
        public decimal Revenue { get; set; }
    }
}
