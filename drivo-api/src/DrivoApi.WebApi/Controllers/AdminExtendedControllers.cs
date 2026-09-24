using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using DrivoApi.Application.DTOs.Admin;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.Services;
using DrivoApi.Domain.Entities;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.WebApi.Controllers
{
    // ==========================================
    // 1. ADMIN CUSTOMERS CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/customers")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminCustomerController : ControllerBase
    {
        private readonly DrivoDbContext _db;
        public AdminCustomerController(DrivoDbContext db) => _db = db;

        [HttpGet]
        public async Task<IActionResult> GetCustomers([FromQuery] string? search = null, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
        {
            var query = _db.Customers
                .Include(c => c.User)
                .Include(c => c.Vehicles)
                .Include(c => c.Bookings)
                .AsQueryable();

            if (!string.IsNullOrWhiteSpace(search))
            {
                var s = search.Trim().ToLower();
                query = query.Where(c => c.User.FullName.ToLower().Contains(s) || c.User.Phone.Contains(s) || (c.User.Email != null && c.User.Email.ToLower().Contains(s)));
            }

            var total = await query.CountAsync();
            var list = await query
                .OrderByDescending(c => c.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(c => new
                {
                    c.Id,
                    c.UserId,
                    c.User.FullName,
                    c.User.Phone,
                    c.User.Email,
                    Status = c.User.Status.ToString(),
                    c.Gender,
                    c.DateOfBirth,
                    VehicleCount = c.Vehicles.Count,
                    BookingCount = c.Bookings.Count,
                    TotalSpent = c.Bookings.Where(b => b.Status == BookingStatus.Completed).Sum(b => (decimal?)(b.FinalPrice ?? b.EstimatedPrice)) ?? 0,
                    c.CreatedAt,
                    c.User.LastLoginAt
                })
                .ToListAsync();

            return Ok(BaseResponse<object>.Ok(new { items = list, totalCount = total }));
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetCustomer(int id)
        {
            var c = await _db.Customers
                .Include(c => c.User)
                .Include(c => c.Vehicles)
                .Include(c => c.Bookings)
                .FirstOrDefaultAsync(x => x.Id == id);

            if (c == null) return NotFound(BaseResponse<object>.Fail("Không tìm thấy khách hàng"));

            var result = new
            {
                c.Id,
                c.UserId,
                c.User.FullName,
                c.User.Phone,
                c.User.Email,
                Status = c.User.Status.ToString(),
                c.Gender,
                c.DateOfBirth,
                c.EmergencyName,
                c.EmergencyPhone,
                c.CreatedAt,
                c.User.LastLoginAt,
                Vehicles = c.Vehicles.Select(v => new { v.Id, v.Brand, v.Model, v.Color, v.LicensePlate, VehicleType = v.VehicleType.ToString(), Transmission = v.Transmission.ToString() }),
                RecentBookings = c.Bookings.OrderByDescending(b => b.CreatedAt).Take(10).Select(b => new { b.Id, b.BookingCode, b.PickupAddress, b.DestinationAddress, Price = b.FinalPrice ?? b.EstimatedPrice, Status = b.Status.ToString(), b.CreatedAt })
            };

            return Ok(BaseResponse<object>.Ok(result));
        }

        [HttpPatch("{id}/status")]
        public async Task<IActionResult> SetCustomerStatus(int id, [FromQuery] string status)
        {
            var customer = await _db.Customers.Include(c => c.User).FirstOrDefaultAsync(c => c.Id == id);
            if (customer == null) return NotFound(BaseResponse<bool>.Fail("Không tìm thấy khách hàng"));

            if (!Enum.TryParse<UserStatus>(status, true, out var userStatus))
                return BadRequest(BaseResponse<bool>.Fail("Trạng thái không hợp lệ. Chọn: Active, Locked"));

            customer.User.Status = userStatus;
            customer.User.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();

            return Ok(BaseResponse<bool>.Ok(true, $"Đã cập nhật trạng thái khách hàng thành {userStatus}"));
        }
    }

    // ==========================================
    // 2. ADMIN BOOKINGS CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/bookings")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminBookingController : ControllerBase
    {
        private readonly DrivoDbContext _db;
        private readonly IBookingService _bookingService;
        public AdminBookingController(DrivoDbContext db, IBookingService bookingService)
        {
            _db = db;
            _bookingService = bookingService;
        }

        private int CurrentUserId =>
            int.TryParse(User.FindFirst("sub")?.Value
                ?? User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value, out var id)
            ? id : 0;

        /// <summary>Chi tiết cuốc: thông tin đầy đủ + lộ trình GPS (trail) + lịch sử trạng thái + bảng giá áp dụng</summary>
        [HttpGet("{id:long}")]
        public async Task<IActionResult> GetBooking(long id)
        {
            var result = await _bookingService.GetAdminBookingDetailAsync(id);
            return result.Success ? Ok(result) : NotFound(result);
        }

        [HttpGet]
        public async Task<IActionResult> GetBookings([FromQuery] string? status = null, [FromQuery] string? search = null, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
        {
            var query = _db.Bookings
                .Include(b => b.Customer).ThenInclude(c => c.User)
                .Include(b => b.Driver).ThenInclude(d => d.User)
                .AsQueryable();

            if (!string.IsNullOrWhiteSpace(status) && Enum.TryParse<BookingStatus>(status, true, out var bs))
            {
                query = query.Where(b => b.Status == bs);
            }

            if (!string.IsNullOrWhiteSpace(search))
            {
                var s = search.Trim().ToLower();
                query = query.Where(b => b.BookingCode.ToLower().Contains(s) || b.PickupAddress.ToLower().Contains(s) || b.DestinationAddress.ToLower().Contains(s) || b.Customer.User.FullName.ToLower().Contains(s) || b.Customer.User.Phone.Contains(s));
            }

            var total = await query.CountAsync();
            var list = await query
                .OrderByDescending(b => b.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(b => new
                {
                    b.Id,
                    b.BookingCode,
                    CustomerName = b.Customer.User.FullName,
                    CustomerPhone = b.Customer.User.Phone,
                    DriverName = b.Driver != null ? b.Driver.User.FullName : "Chưa có tài xế",
                    DriverPhone = b.Driver != null ? b.Driver.User.Phone : "",
                    b.PickupAddress,
                    b.DestinationAddress,
                    DistanceKm = b.EstimatedDistanceKm,
                    Price = b.FinalPrice ?? b.EstimatedPrice,
                    Status = b.Status.ToString(),
                    b.CreatedAt
                })
                .ToListAsync();

            return Ok(BaseResponse<object>.Ok(new { items = list, totalCount = total }));
        }

        [HttpPatch("{id}/cancel")]
        public async Task<IActionResult> CancelBooking(long id, [FromBody] CancelBookingAdminRequest req)
        {
            if (!await _db.Bookings.AnyAsync(b => b.Id == id))
                return NotFound(BaseResponse<bool>.Fail("Không tìm thấy chuyến đi"));

            var result = await _bookingService.CancelBookingByAdminAsync(id, CurrentUserId, req?.Reason);
            return result.Success ? Ok(result) : BadRequest(result);
        }
    }

    public class CancelBookingAdminRequest
    {
        public string? Reason { get; set; }
    }

    // ==========================================
    // 3. ADMIN PAYMENTS CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/payments")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminPaymentController : ControllerBase
    {
        private readonly DrivoDbContext _db;
        public AdminPaymentController(DrivoDbContext db) => _db = db;

        [HttpGet]
        public async Task<IActionResult> GetPayments([FromQuery] int page = 1, [FromQuery] int pageSize = 50)
        {
            var payments = await _db.Payments
                .Include(p => p.Customer).ThenInclude(c => c.User)
                .Include(p => p.Trip).ThenInclude(t => t.Booking)
                .OrderByDescending(p => p.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(p => new
                {
                    p.Id,
                    BookingCode = p.Trip.Booking.BookingCode,
                    CustomerName = p.Customer.User.FullName,
                    CustomerPhone = p.Customer.User.Phone,
                    p.Amount,
                    p.Currency,
                    PaymentMethod = p.PaymentMethod.ToString(),
                    PaymentStatus = p.PaymentStatus.ToString(),
                    p.PaidAt,
                    p.CreatedAt
                })
                .ToListAsync();

            var totalRevenue = await _db.Payments.Where(p => p.PaymentStatus == PaymentStatus.Success).SumAsync(p => (decimal?)p.Amount) ?? 0;
            var completedCount = await _db.Payments.CountAsync(p => p.PaymentStatus == PaymentStatus.Success);
            var pendingCount = await _db.Payments.CountAsync(p => p.PaymentStatus == PaymentStatus.Pending);

            return Ok(BaseResponse<object>.Ok(new { items = payments, summary = new { totalRevenue, completedCount, pendingCount } }));
        }
    }

    // ==========================================
    // 4. ADMIN PRICING RULES CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/pricing")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminPricingController : ControllerBase
    {
        private readonly DrivoDbContext _db;
        public AdminPricingController(DrivoDbContext db) => _db = db;

        [HttpGet]
        public async Task<IActionResult> GetPricingRules()
        {
            var rules = await _db.PricingRules.OrderBy(p => p.VehicleType).ToListAsync();
            return Ok(BaseResponse<object>.Ok(rules));
        }

        private static string? ValidatePricing(PricingRuleUpsertRequest r)
        {
            if (r.BaseFare < 0 || r.PricePerKm < 0 || r.PricePerMinute < 0 || r.NightSurcharge < 0 || r.WaitingPricePerMin < 0 ||
                r.FreePickupKm < 0 || r.PickupFeePerKm < 0 || r.FreeWaitingMin < 0 || r.OverDistanceTolerancePercent < 0 ||
                r.CommissionPercent < 0)
                return "Giá trị bảng giá không được âm";
            if (r.FreePickupKm > 9999 || r.OverDistanceTolerancePercent > 999)
                return "Giá trị bảng giá vượt giới hạn cho phép";
            if (r.CommissionPercent > 100)
                return "Hoa hồng nền tảng không được vượt quá 100%";
            return null;
        }

        [HttpPost]
        public async Task<IActionResult> CreatePricingRule([FromBody] PricingRuleUpsertRequest req)
        {
            var error = ValidatePricing(req);
            if (error != null) return BadRequest(BaseResponse<object>.Fail(error));

            var now = DateTime.UtcNow;
            var effectiveFrom = req.EffectiveFrom ?? now;
            if (req.EffectiveTo.HasValue && req.EffectiveTo.Value <= effectiveFrom)
                return BadRequest(BaseResponse<object>.Fail("Ngày kết thúc phải sau ngày bắt đầu hiệu lực"));

            var rule = new PricingRule
            {
                VehicleType = req.VehicleType ?? VehicleType.Car,
                BaseFare = req.BaseFare,
                PricePerKm = req.PricePerKm,
                PricePerMinute = req.PricePerMinute,
                NightSurcharge = req.NightSurcharge,
                WaitingPricePerMin = req.WaitingPricePerMin,
                FreePickupKm = req.FreePickupKm ?? 3m,
                PickupFeePerKm = req.PickupFeePerKm ?? 5000m,
                FreeWaitingMin = req.FreeWaitingMin ?? 10,
                OverDistanceTolerancePercent = req.OverDistanceTolerancePercent ?? 10m,
                CommissionPercent = req.CommissionPercent ?? 15m,
                IsActive = req.IsActive,
                EffectiveFrom = effectiveFrom,
                EffectiveTo = req.EffectiveTo,
                CreatedAt = now
            };
            _db.PricingRules.Add(rule);
            await _db.SaveChangesAsync();
            return Ok(BaseResponse<object>.Ok(rule, "Đã thêm bảng giá mới"));
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> UpdatePricingRule(int id, [FromBody] PricingRuleUpsertRequest updated)
        {
            var rule = await _db.PricingRules.FirstOrDefaultAsync(p => p.Id == id);
            if (rule == null) return NotFound(BaseResponse<object>.Fail("Không tìm thấy bảng giá"));

            var error = ValidatePricing(updated);
            if (error != null) return BadRequest(BaseResponse<object>.Fail(error));

            var effectiveFrom = updated.EffectiveFrom ?? rule.EffectiveFrom;
            var effectiveTo = updated.EffectiveTo ?? rule.EffectiveTo;
            if (effectiveTo.HasValue && effectiveTo.Value <= effectiveFrom)
                return BadRequest(BaseResponse<object>.Fail("Ngày kết thúc phải sau ngày bắt đầu hiệu lực"));

            if (updated.VehicleType.HasValue) rule.VehicleType = updated.VehicleType.Value;
            rule.BaseFare = updated.BaseFare;
            rule.PricePerKm = updated.PricePerKm;
            rule.PricePerMinute = updated.PricePerMinute;
            rule.NightSurcharge = updated.NightSurcharge;
            rule.WaitingPricePerMin = updated.WaitingPricePerMin;
            if (updated.FreePickupKm.HasValue) rule.FreePickupKm = updated.FreePickupKm.Value;
            if (updated.PickupFeePerKm.HasValue) rule.PickupFeePerKm = updated.PickupFeePerKm.Value;
            if (updated.FreeWaitingMin.HasValue) rule.FreeWaitingMin = updated.FreeWaitingMin.Value;
            if (updated.OverDistanceTolerancePercent.HasValue) rule.OverDistanceTolerancePercent = updated.OverDistanceTolerancePercent.Value;
            if (updated.CommissionPercent.HasValue) rule.CommissionPercent = updated.CommissionPercent.Value;
            rule.IsActive = updated.IsActive;
            rule.EffectiveFrom = effectiveFrom;
            rule.EffectiveTo = effectiveTo;

            await _db.SaveChangesAsync();
            return Ok(BaseResponse<object>.Ok(rule, "Đã cập nhật bảng giá"));
        }

        [HttpPatch("{id}/toggle")]
        public async Task<IActionResult> TogglePricingRule(int id)
        {
            var rule = await _db.PricingRules.FirstOrDefaultAsync(p => p.Id == id);
            if (rule == null) return NotFound(BaseResponse<object>.Fail("Không tìm thấy bảng giá"));

            rule.IsActive = !rule.IsActive;
            await _db.SaveChangesAsync();
            return Ok(BaseResponse<object>.Ok(rule, $"Đã {(rule.IsActive ? "kích hoạt" : "vô hiệu hóa")} bảng giá"));
        }
    }

    // ==========================================
    // 5. ADMIN VOUCHERS CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/vouchers")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminVoucherController : ControllerBase
    {
        private readonly DrivoDbContext _db;
        public AdminVoucherController(DrivoDbContext db) => _db = db;

        [HttpGet]
        public async Task<IActionResult> GetVouchers()
        {
            var list = await _db.Vouchers.OrderByDescending(v => v.CreatedAt).ToListAsync();
            return Ok(BaseResponse<object>.Ok(list));
        }

        [HttpPost]
        public async Task<IActionResult> CreateVoucher([FromBody] Voucher voucher)
        {
            voucher.Code = (voucher.Code ?? string.Empty).Trim().ToUpperInvariant();
            if (voucher.Code.Length == 0)
                return BadRequest(BaseResponse<object>.Fail("Vui lòng nhập mã voucher"));
            if (await _db.Vouchers.AnyAsync(v => v.Code == voucher.Code))
                return BadRequest(BaseResponse<object>.Fail("Mã voucher đã tồn tại"));

            voucher.CreatedAt = DateTime.UtcNow;
            _db.Vouchers.Add(voucher);
            await _db.SaveChangesAsync();
            return Ok(BaseResponse<object>.Ok(voucher, "Đã tạo mã giảm giá thành công"));
        }

        [HttpPatch("{id}/toggle")]
        public async Task<IActionResult> ToggleVoucher(int id)
        {
            var voucher = await _db.Vouchers.FirstOrDefaultAsync(v => v.Id == id);
            if (voucher == null) return NotFound(BaseResponse<object>.Fail("Không tìm thấy voucher"));

            voucher.IsActive = !voucher.IsActive;
            await _db.SaveChangesAsync();
            return Ok(BaseResponse<object>.Ok(voucher, $"Đã {(voucher.IsActive ? "kích hoạt" : "tạm dừng")} mã khuyến mãi"));
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteVoucher(int id)
        {
            var voucher = await _db.Vouchers.FirstOrDefaultAsync(v => v.Id == id);
            if (voucher == null) return NotFound(BaseResponse<object>.Fail("Không tìm thấy voucher"));

            _db.Vouchers.Remove(voucher);
            await _db.SaveChangesAsync();
            return Ok(BaseResponse<bool>.Ok(true, "Đã xóa mã khuyến mãi"));
        }
    }

    // ==========================================
    // 6. ADMIN NOTIFICATIONS CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/notifications")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminNotificationController : ControllerBase
    {
        private readonly DrivoDbContext _db;
        public AdminNotificationController(DrivoDbContext db) => _db = db;

        [HttpGet]
        public async Task<IActionResult> GetNotifications([FromQuery] int take = 30)
        {
            var list = await _db.Notifications
                .Include(n => n.User)
                .OrderByDescending(n => n.CreatedAt)
                .Take(take)
                .Select(n => new
                {
                    n.Id,
                    n.Type,
                    n.Title,
                    n.Message,
                    TargetUser = n.User.FullName,
                    TargetPhone = n.User.Phone,
                    n.IsRead,
                    n.CreatedAt
                })
                .ToListAsync();

            return Ok(BaseResponse<object>.Ok(list));
        }

        [HttpPost("broadcast")]
        public async Task<IActionResult> BroadcastNotification([FromBody] BroadcastRequest req)
        {
            if (string.IsNullOrWhiteSpace(req.Title) || string.IsNullOrWhiteSpace(req.Message))
                return BadRequest(BaseResponse<bool>.Fail("Tiêu đề và nội dung không được để trống"));

            var query = _db.Users.AsQueryable();
            if (req.TargetGroup == "DRIVERS")
                query = query.Where(u => u.UserRoles.Any(r => r.Role.Name == "DRIVER" || r.Role.Name == "Driver"));
            else if (req.TargetGroup == "CUSTOMERS")
                query = query.Where(u => u.UserRoles.Any(r => r.Role.Name == "CUSTOMER" || r.Role.Name == "Customer"));

            var userIds = await query.Select(u => u.Id).ToListAsync();
            var notifs = userIds.Select(uid => new Notification
            {
                UserId = uid,
                Type = req.Type ?? "SYSTEM",
                Title = req.Title,
                Message = req.Message,
                CreatedAt = DateTime.UtcNow
            }).ToList();

            _db.Notifications.AddRange(notifs);
            await _db.SaveChangesAsync();

            return Ok(BaseResponse<bool>.Ok(true, $"Đã gửi thông báo đến {notifs.Count} người dùng"));
        }
    }

    public class BroadcastRequest
    {
        public string Title { get; set; } = null!;
        public string Message { get; set; } = null!;
        public string? Type { get; set; }
        public string TargetGroup { get; set; } = "ALL"; // ALL | DRIVERS | CUSTOMERS
    }

    // ==========================================
    // 7. ADMIN ACCOUNTS CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/accounts")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminAccountController : ControllerBase
    {
        private readonly DrivoDbContext _db;
        public AdminAccountController(DrivoDbContext db) => _db = db;

        [HttpGet]
        public async Task<IActionResult> GetAdmins()
        {
            var admins = await _db.Users
                .Where(u => u.UserRoles.Any(r => r.Role.Name == "ADMIN" || r.Role.Name == "Admin"))
                .OrderByDescending(u => u.CreatedAt)
                .Select(u => new
                {
                    u.Id,
                    u.FullName,
                    u.Phone,
                    u.Email,
                    Status = u.Status.ToString(),
                    u.LastLoginAt,
                    u.CreatedAt
                })
                .ToListAsync();

            return Ok(BaseResponse<object>.Ok(admins));
        }

        [HttpPost]
        public async Task<IActionResult> CreateAdmin([FromBody] CreateAdminRequest req)
        {
            if (await _db.Users.AnyAsync(u => u.Phone == req.Phone))
                return BadRequest(BaseResponse<object>.Fail("Số điện thoại đã tồn tại"));

            var adminRole = await _db.Roles.FirstOrDefaultAsync(r => r.Name == "ADMIN" || r.Name == "Admin");
            if (adminRole == null)
            {
                adminRole = new Role { Name = "ADMIN", Description = "Administrator", CreatedAt = DateTime.UtcNow };
                _db.Roles.Add(adminRole);
                await _db.SaveChangesAsync();
            }

            var salt = RandomNumberGenerator.GetBytes(16);
            var hash = Rfc2898DeriveBytes.Pbkdf2(req.Password, salt, 350_000, HashAlgorithmName.SHA256, 32);
            var hashStr = $"350000.{Convert.ToBase64String(salt)}.{Convert.ToBase64String(hash)}";

            var user = new User
            {
                FullName = req.FullName,
                Phone = req.Phone,
                Email = req.Email,
                PasswordHash = hashStr,
                Status = UserStatus.Active,
                CreatedAt = DateTime.UtcNow
            };
            _db.Users.Add(user);
            await _db.SaveChangesAsync();

            _db.UserRoles.Add(new UserRole { UserId = user.Id, RoleId = adminRole.Id, AssignedAt = DateTime.UtcNow });
            await _db.SaveChangesAsync();

            return Ok(BaseResponse<object>.Ok(user, "Đã tạo tài khoản Admin thành công"));
        }

        [HttpPatch("{id}/status")]
        public async Task<IActionResult> ToggleStatus(int id)
        {
            var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == id);
            if (user == null) return NotFound(BaseResponse<bool>.Fail("Không tìm thấy người dùng"));

            user.Status = user.Status == UserStatus.Active ? UserStatus.Locked : UserStatus.Active;
            user.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();

            return Ok(BaseResponse<bool>.Ok(true, $"Đã cập nhật trạng thái admin thành {user.Status}"));
        }
    }

    public class CreateAdminRequest
    {
        public string FullName { get; set; } = null!;
        public string Phone { get; set; } = null!;
        public string? Email { get; set; }
        public string Password { get; set; } = null!;
    }

    // ==========================================
    // 8. ADMIN REPORTS CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/reports")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminReportController : ControllerBase
    {
        private readonly DrivoDbContext _db;
        public AdminReportController(DrivoDbContext db) => _db = db;

        [HttpGet("summary")]
        public async Task<IActionResult> GetReportSummary()
        {
            var totalDrivers = await _db.Drivers.CountAsync();
            var totalCustomers = await _db.Customers.CountAsync();
            var totalBookings = await _db.Bookings.CountAsync();
            var completedBookings = await _db.Bookings.CountAsync(b => b.Status == BookingStatus.Completed);
            var cancelledBookings = await _db.Bookings.CountAsync(b => b.Status == BookingStatus.Cancelled);
            var totalRevenue = await _db.Bookings.Where(b => b.Status == BookingStatus.Completed).SumAsync(b => (decimal?)(b.FinalPrice ?? b.EstimatedPrice)) ?? 0;

            var topDrivers = await _db.Drivers
                .Include(d => d.User)
                .OrderByDescending(d => d.TotalTrips)
                .Take(5)
                .Select(d => new { d.Id, d.User.FullName, d.User.Phone, d.TotalTrips, d.RatingAverage })
                .ToListAsync();

            return Ok(BaseResponse<object>.Ok(new
            {
                totalDrivers,
                totalCustomers,
                totalBookings,
                completedBookings,
                cancelledBookings,
                completionRate = totalBookings > 0 ? Math.Round((double)completedBookings / totalBookings * 100, 1) : 0,
                totalRevenue,
                topDrivers
            }));
        }

        /// <summary>
        /// Doanh thu nền tảng theo ngày và loại xe trong [from, to] (yyyy-MM-dd, giờ VN, gồm cả 2 ngày; mặc định 30 ngày gần nhất).
        /// Hoa hồng tính trên giá trước voucher; DRIVO thực thu = hoa hồng − tiền voucher DRIVO chịu.
        /// </summary>
        [HttpGet("revenue")]
        public async Task<IActionResult> GetRevenueReport([FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
        {
            var toLocal = (to ?? DrivoApi.Application.Common.VnClock.Today).Date;
            var fromLocal = (from ?? toLocal.AddDays(-29)).Date;
            if (fromLocal > toLocal) (fromLocal, toLocal) = (toLocal, fromLocal);
            if ((toLocal - fromLocal).TotalDays > 366)
                return BadRequest(BaseResponse<object>.Fail("Khoảng thời gian tối đa 1 năm"));

            var fromUtc = DrivoApi.Application.Common.VnClock.StartOfDayUtc(fromLocal);
            var toUtc = DrivoApi.Application.Common.VnClock.StartOfDayUtc(toLocal.AddDays(1));

            var rows = await _db.Bookings.AsNoTracking()
                .Where(b => b.Status == BookingStatus.Completed && b.FinalPrice != null)
                .Where(b => (b.CompletedAt ?? b.UpdatedAt ?? b.CreatedAt) >= fromUtc &&
                            (b.CompletedAt ?? b.UpdatedAt ?? b.CreatedAt) < toUtc)
                .Select(b => new RevenueRow(
                    b.CompletedAt ?? b.UpdatedAt ?? b.CreatedAt,
                    b.VehicleType,
                    b.FinalPrice!.Value,
                    b.Discount,
                    b.DriverPayout))
                .ToListAsync();

            var days = (int)(toLocal - fromLocal).TotalDays + 1;
            var byDay = Enumerable.Range(0, days).Select(i =>
            {
                var d = fromLocal.AddDays(i);
                var agg = RevenueTotals.Of(rows.Where(r => DrivoApi.Application.Common.VnClock.ToLocal(r.CompletedAt).Date == d));
                return new { date = d.ToString("yyyy-MM-dd"), totals = agg };
            }).ToList();

            var byVehicleType = rows
                .GroupBy(r => r.VehicleType)
                .Select(g => new { vehicleType = g.Key.ToString(), totals = RevenueTotals.Of(g) })
                .OrderByDescending(x => x.totals.Commission)
                .ToList();

            return Ok(BaseResponse<object>.Ok(new
            {
                from = fromLocal.ToString("yyyy-MM-dd"),
                to = toLocal.ToString("yyyy-MM-dd"),
                summary = RevenueTotals.Of(rows),
                byDay,
                byVehicleType
            }));
        }

        private record RevenueRow(DateTime CompletedAt, VehicleType VehicleType, decimal FinalPrice, decimal Discount, decimal DriverPayout);

        private record RevenueTotals(
            int Trips, decimal GrossFare, decimal VoucherCost, decimal CustomerPaid,
            decimal DriverPayout, decimal Commission, decimal PlatformNet)
        {
            public static RevenueTotals Of(IEnumerable<RevenueRow> src)
            {
                var list = src.ToList();
                var paid = list.Sum(x => x.FinalPrice);
                var voucher = list.Sum(x => x.Discount);
                var payout = list.Sum(x => x.DriverPayout);
                return new RevenueTotals(list.Count, paid + voucher, voucher, paid, payout, paid + voucher - payout, paid - payout);
            }
        }
    }

    // ==========================================
    // 9. ADMIN SETTINGS CONTROLLER
    // ==========================================
    [ApiController]
    [Route("api/v1/admin/settings")]
    [Authorize(Roles = "ADMIN,Admin")]
    public class AdminSettingController : ControllerBase
    {
        [HttpGet]
        public IActionResult GetSettings()
        {
            return Ok(BaseResponse<object>.Ok(new
            {
                systemName = "Hệ thống Quản lý DRIVO",
                version = "1.2.0-PROD",
                hotline = "1900 8888",
                supportEmail = "support@drivo.vn",
                driverCommissionRate = 15, // 15% hoa hồng
                vatPercent = 8,
                maxSearchRadiusKm = 10,
                autoMatchTimeoutSeconds = 30,
                environment = "Production"
            }));
        }
    }
}
