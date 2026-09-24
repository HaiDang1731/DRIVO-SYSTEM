using System.Linq.Expressions;
using DrivoApi.Application.Common;
using DrivoApi.Application.DTOs.Booking;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Driver;
using DrivoApi.Application.DTOs.Maps;
using DrivoApi.Application.DTOs.Tracking;
using DrivoApi.Application.Services;
using DrivoApi.Domain.Entities;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure;

public class BookingService(DrivoDbContext db, IMapsService maps, ITrackingNotifier notifier) : IBookingService
{
    /// <summary>Bán kính (km, đường chim bay) để tài xế thấy cuốc chờ.</summary>
    private const double PendingSearchRadiusKm = 10.0;

    /// <summary>Vị trí tài xế được coi là "mới" trong khoảng thời gian này (xem trước chặng đón).</summary>
    private static readonly TimeSpan FreshLocationWindow = TimeSpan.FromMinutes(10);

    /// <summary>Bỏ qua cập nhật vị trí nếu lần trước cách chưa tới 2 giây.</summary>
    private static readonly TimeSpan LocationThrottle = TimeSpan.FromSeconds(2);

    /// <summary>Khi không có cuốc, chỉ lưu lịch sử vị trí tối đa 1 lần / 60 giây.</summary>
    private static readonly TimeSpan IdleHistoryInterval = TimeSpan.FromSeconds(60);

    private const double MaxGpsAccuracyMeters = 50.0;
    private const double MaxPlausibleSpeedKmh = 150.0;

    /// <summary>Các trạng thái tài xế đang phục vụ cuốc (DriverAccepted..InProgress).</summary>
    private static readonly Expression<Func<Booking, bool>> IsDriverActiveStatus = b =>
        b.Status == BookingStatus.DriverAccepted ||
        b.Status == BookingStatus.DriverArriving ||
        b.Status == BookingStatus.DriverArrived ||
        b.Status == BookingStatus.InProgress;

    // ══════════════════════════════════════════════════════════
    //  PRICING HELPERS
    // ══════════════════════════════════════════════════════════

    private static PricingRule DefaultPricingRule() => new()
    {
        Id = 0,
        VehicleType = VehicleType.Car,
        BaseFare = 150000m,
        PricePerKm = 16000m,
        PricePerMinute = 1000m,
        NightSurcharge = 30000m,
        WaitingPricePerMin = 1000m,
        FreePickupKm = 3m,
        PickupFeePerKm = 5000m,
        FreeWaitingMin = 10,
        OverDistanceTolerancePercent = 10m
    };

    private async Task<PricingRule> GetApplicablePricingRuleAsync(VehicleType vehicleType)
    {
        var now = DateTime.UtcNow;
        var effective = db.PricingRules.AsNoTracking()
            .Where(p => p.IsActive && p.EffectiveFrom <= now && (p.EffectiveTo == null || p.EffectiveTo > now));

        var rule = await effective
            .Where(p => p.VehicleType == vehicleType)
            .OrderByDescending(p => p.EffectiveFrom)
            .FirstOrDefaultAsync();

        rule ??= await effective
            .OrderByDescending(p => p.EffectiveFrom)
            .FirstOrDefaultAsync();

        return rule ?? DefaultPricingRule();
    }

    /// <summary>Bảng giá đã chốt lúc đặt cuốc (snapshot), nếu không có thì bảng giá hiện hành.</summary>
    private async Task<PricingRule> GetPricingRuleForBookingAsync(Booking booking)
    {
        if (booking.PricingRuleId.HasValue)
        {
            var rule = await db.PricingRules.AsNoTracking().FirstOrDefaultAsync(p => p.Id == booking.PricingRuleId.Value);
            if (rule != null) return rule;
        }
        return await GetApplicablePricingRuleAsync(booking.VehicleType);
    }

    private static decimal CalcPickupFee(decimal pickupKm, PricingRule rule) =>
        GeoUtils.Round1000(Math.Max(0m, pickupKm - rule.FreePickupKm) * rule.PickupFeePerKm);

    private async Task<(EstimateFareResponse Fare, RouteResult Route)> ComputeEstimateAsync(EstimateFareRequest req)
    {
        RouteResult route;
        var pickupValid = GeoUtils.IsValid(req.PickupLatitude, req.PickupLongitude);
        if (pickupValid && GeoUtils.IsValid(req.DestinationLatitude, req.DestinationLongitude))
        {
            route = await maps.GetRouteAsync(
                (double)req.PickupLatitude, (double)req.PickupLongitude,
                (double)req.DestinationLatitude, (double)req.DestinationLongitude, "DRIVE");
        }
        else
        {
            // Thiếu tọa độ (client cũ) → giữ hành vi cũ: mặc định 5 km
            route = new RouteResult { DistanceKm = 5.0m, DurationMin = 13, Polyline = null };
        }

        var distKm = route.DistanceKm;
        var estMinutes = route.DurationMin;

        var pricing = await GetApplicablePricingRuleAsync(req.VehicleType);

        var baseFare = pricing.BaseFare;
        var distanceFare = Math.Max(0m, distKm - 2m) * pricing.PricePerKm;
        var timeFare = estMinutes * pricing.PricePerMinute;

        var localNow = DateTime.UtcNow.AddHours(7);
        var isNight = localNow.Hour >= 22 || localNow.Hour < 6;
        var nightSurcharge = isNight ? pricing.NightSurcharge : 0m;

        var total = GeoUtils.Round1000(baseFare + distanceFare + timeFare + nightSurcharge);

        var res = new EstimateFareResponse
        {
            EstimatedDistanceKm = distKm,
            EstimatedDurationMin = estMinutes,
            BaseFare = baseFare,
            DistanceFare = distanceFare,
            TimeFare = timeFare,
            NightSurcharge = nightSurcharge,
            TotalEstimatedFare = total,
            PricingRuleId = pricing.Id > 0 ? pricing.Id : null,
            RoutePolyline = route.Polyline,
            FreePickupKm = pricing.FreePickupKm,
            PickupFeePerKm = pricing.PickupFeePerKm,
            WaitingPricePerMin = pricing.WaitingPricePerMin,
            FreeWaitingMin = pricing.FreeWaitingMin
        };

        // Xem trước chặng đón: tài xế Online gần nhất có vị trí trong 10 phút (không gọi dịch vụ định tuyến)
        if (pickupValid)
        {
            var since = DateTime.UtcNow - FreshLocationWindow;
            var drivers = await db.Drivers.AsNoTracking()
                .Where(d => d.DriverStatus == DriverStatus.Online &&
                            d.VerificationStatus == VerificationStatus.Approved &&
                            d.CurrentLatitude != null && d.CurrentLongitude != null &&
                            d.LastLocationAt != null && d.LastLocationAt >= since)
                .Select(d => new { Lat = d.CurrentLatitude!.Value, Lng = d.CurrentLongitude!.Value })
                .ToListAsync();

            var nearest = drivers
                .Where(d => GeoUtils.IsValid(d.Lat, d.Lng))
                .Select(d => GeoUtils.HaversineKm(d.Lat, d.Lng, req.PickupLatitude, req.PickupLongitude) * GeoUtils.RoadFactor)
                .DefaultIfEmpty(-1)
                .Min();

            if (nearest >= 0)
            {
                var pickupKm = Math.Round((decimal)nearest, 1);
                res.EstimatedPickupKm = pickupKm;
                res.EstimatedPickupFee = CalcPickupFee(pickupKm, pricing);
                res.NearestDriverEtaMin = Math.Max(1, (int)Math.Ceiling(nearest / GeoUtils.ScooterSpeedKmh * 60.0));
            }
        }

        return (res, route);
    }

    public async Task<BaseResponse<EstimateFareResponse>> EstimateFareAsync(EstimateFareRequest req)
    {
        var (fare, _) = await ComputeEstimateAsync(req);
        return BaseResponse<EstimateFareResponse>.Ok(fare);
    }

    // ══════════════════════════════════════════════════════════
    //  VOUCHERS
    // ══════════════════════════════════════════════════════════

    private static string NormalizeVoucherCode(string? code) => (code ?? string.Empty).Trim().ToUpperInvariant();

    private static string Vnd(decimal amount) =>
        amount.ToString("#,0", System.Globalization.CultureInfo.GetCultureInfo("vi-VN")) + "đ";

    /// <summary>PERCENT: % giá ước tính, trần MaxDiscountAmount; FIXED: số tiền cố định. Không vượt giá chuyến.</summary>
    private static decimal CalcVoucherDiscount(Voucher v, decimal orderAmount)
    {
        var raw = string.Equals(v.DiscountType, "PERCENT", StringComparison.OrdinalIgnoreCase)
            ? orderAmount * v.DiscountValue / 100m
            : v.DiscountValue;
        var discount = GeoUtils.Round1000(Math.Max(0m, raw));
        if (v.MaxDiscountAmount is > 0) discount = Math.Min(discount, v.MaxDiscountAmount.Value);
        return Math.Min(discount, orderAmount);
    }

    private IQueryable<Voucher> UsableVouchers(DateTime now) => db.Vouchers.AsNoTracking()
        .Where(v => v.IsActive && v.StartDate <= now && v.EndDate >= now && v.UsedCount < v.UsageLimit);

    private Task<bool> CustomerUsedVoucherAsync(int customerId, int voucherId) =>
        db.Bookings.AnyAsync(b => b.CustomerId == customerId && b.VoucherId == voucherId && b.Status != BookingStatus.Cancelled);

    private async Task<(Voucher? Voucher, decimal Discount, string? Error)> ResolveVoucherAsync(
        int customerId, string code, decimal orderAmount)
    {
        var norm = NormalizeVoucherCode(code);
        var now = DateTime.UtcNow;
        var v = await db.Vouchers.AsNoTracking().FirstOrDefaultAsync(x => x.Code == norm);
        if (v == null)
            return (null, 0, "Mã khuyến mãi không tồn tại.");
        if (!v.IsActive || now < v.StartDate || now > v.EndDate)
            return (null, 0, "Mã khuyến mãi đã hết hạn hoặc đang tạm dừng.");
        if (v.UsedCount >= v.UsageLimit)
            return (null, 0, "Mã khuyến mãi đã hết lượt sử dụng.");
        if (orderAmount < v.MinOrderAmount)
            return (null, 0, $"Mã này chỉ áp dụng cho chuyến từ {Vnd(v.MinOrderAmount)}.");
        if (customerId > 0 && await CustomerUsedVoucherAsync(customerId, v.Id))
            return (null, 0, "Bạn đã sử dụng mã này rồi.");
        return (v, CalcVoucherDiscount(v, orderAmount), null);
    }

    /// <summary>Trả lại 1 lượt dùng khi chuyến có voucher bị hủy.</summary>
    private Task ReleaseVoucherAsync(Booking booking) =>
        booking.VoucherId is int vid
            ? db.Vouchers.Where(v => v.Id == vid && v.UsedCount > 0)
                .ExecuteUpdateAsync(s => s.SetProperty(v => v.UsedCount, v => v.UsedCount - 1))
            : Task.CompletedTask;

    public async Task<BaseResponse<List<VoucherResponse>>> GetAvailableVouchersAsync(int userId)
    {
        var customerId = await db.Customers.Where(c => c.UserId == userId).Select(c => c.Id).FirstOrDefaultAsync();
        var now = DateTime.UtcNow;
        var list = await UsableVouchers(now)
            .Where(v => customerId == 0 || !db.Bookings.Any(b =>
                b.CustomerId == customerId && b.VoucherId == v.Id && b.Status != BookingStatus.Cancelled))
            .OrderBy(v => v.EndDate)
            .Select(v => new VoucherResponse
            {
                Code = v.Code,
                Title = v.Title,
                Description = v.Description,
                DiscountType = v.DiscountType,
                DiscountValue = v.DiscountValue,
                MaxDiscountAmount = v.MaxDiscountAmount,
                MinOrderAmount = v.MinOrderAmount,
                EndDate = v.EndDate
            })
            .ToListAsync();
        return BaseResponse<List<VoucherResponse>>.Ok(list);
    }

    public async Task<BaseResponse<CheckVoucherResponse>> CheckVoucherAsync(int userId, CheckVoucherRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Code))
            return BaseResponse<CheckVoucherResponse>.Fail("Vui lòng nhập mã khuyến mãi.");
        var customerId = await db.Customers.Where(c => c.UserId == userId).Select(c => c.Id).FirstOrDefaultAsync();
        var (v, discount, error) = await ResolveVoucherAsync(customerId, req.Code, Math.Max(0m, req.OrderAmount));
        if (error != null)
            return BaseResponse<CheckVoucherResponse>.Fail(error);
        return BaseResponse<CheckVoucherResponse>.Ok(
            new CheckVoucherResponse { Code = v!.Code, Title = v.Title, Discount = discount },
            $"Áp dụng thành công, giảm {Vnd(discount)}.");
    }

    // ══════════════════════════════════════════════════════════
    //  REALTIME HELPERS
    // ══════════════════════════════════════════════════════════

    private Task NotifyStatusAsync(Booking b) => notifier.BookingStatusChangedAsync(new BookingStatusChangedEvent
    {
        BookingId = b.Id,
        BookingCode = b.BookingCode,
        Status = b.Status.ToString(),
        FinalPrice = b.FinalPrice,
        PickupFee = b.PickupFee,
        WaitingFee = b.WaitingFee,
        ExtraDistanceFee = b.ExtraDistanceFee
    });

    // ══════════════════════════════════════════════════════════
    //  CUSTOMER METHODS
    // ══════════════════════════════════════════════════════════

    public async Task<BaseResponse<BookingDetailResponse>> CreateBookingAsync(int userId, CreateBookingRequest req)
    {
        if (!GeoUtils.IsValid(req.PickupLatitude, req.PickupLongitude) ||
            !GeoUtils.IsValid(req.DestinationLatitude, req.DestinationLongitude))
            return BaseResponse<BookingDetailResponse>.Fail("Vui lòng chọn điểm đón và điểm đến trên bản đồ (thiếu tọa độ).");

        var customer = await db.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
        {
            customer = new Customer { UserId = userId, CreatedAt = DateTime.UtcNow };
            db.Customers.Add(customer);
            await db.SaveChangesAsync();
        }

        var vehicle = await db.CustomerVehicles
            .FirstOrDefaultAsync(v => v.Id == req.CustomerVehicleId && v.CustomerId == customer.Id && v.IsActive);

        if (vehicle == null)
            return BaseResponse<BookingDetailResponse>.Fail("Không tìm thấy xe của bạn.");

        var hasActiveBooking = await db.Bookings.AnyAsync(b =>
            b.CustomerId == customer.Id &&
            b.Status != BookingStatus.Completed &&
            b.Status != BookingStatus.Cancelled);

        if (hasActiveBooking)
            return BaseResponse<BookingDetailResponse>.Fail("Bạn đang có một chuyến đi chưa hoàn thành. Không thể đặt thêm chuyến mới.");

        // Server tự tính lại lộ trình, không tin km do client gửi
        var (fare, route) = await ComputeEstimateAsync(new EstimateFareRequest
        {
            PickupLatitude = req.PickupLatitude,
            PickupLongitude = req.PickupLongitude,
            DestinationLatitude = req.DestinationLatitude,
            DestinationLongitude = req.DestinationLongitude,
            VehicleType = vehicle.VehicleType,
            Transmission = vehicle.Transmission
        });

        // Voucher: kiểm tra theo giá ước tính server tự tính, rồi giữ 1 lượt dùng (atomic, không vượt UsageLimit)
        Voucher? voucher = null;
        var discount = 0m;
        if (!string.IsNullOrWhiteSpace(req.VoucherCode))
        {
            var (v, d, error) = await ResolveVoucherAsync(customer.Id, req.VoucherCode, fare.TotalEstimatedFare);
            if (error != null)
                return BaseResponse<BookingDetailResponse>.Fail(error);

            var claimed = await db.Vouchers
                .Where(x => x.Id == v!.Id && x.UsedCount < x.UsageLimit)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.UsedCount, x => x.UsedCount + 1));
            if (claimed == 0)
                return BaseResponse<BookingDetailResponse>.Fail("Mã khuyến mãi đã hết lượt sử dụng.");
            voucher = v;
            discount = d;
        }

        var bookingCode = $"DRV{DateTime.UtcNow:yyMMddHHmm}{Random.Shared.Next(100, 999)}";

        var booking = new Booking
        {
            BookingCode = bookingCode,
            CustomerId = customer.Id,
            CustomerVehicleId = vehicle.Id,
            PricingRuleId = fare.PricingRuleId,
            PickupAddress = req.PickupAddress,
            PickupLatitude = req.PickupLatitude,
            PickupLongitude = req.PickupLongitude,
            DestinationAddress = req.DestinationAddress,
            DestinationLatitude = req.DestinationLatitude,
            DestinationLongitude = req.DestinationLongitude,
            VehicleType = vehicle.VehicleType,
            Transmission = vehicle.Transmission,
            EstimatedDistanceKm = fare.EstimatedDistanceKm,
            EstimatedDurationMin = fare.EstimatedDurationMin,
            RoutePolyline = route.Polyline,
            BaseFare = fare.BaseFare,
            DistanceFare = fare.DistanceFare,
            TimeFare = fare.TimeFare,
            Surcharge = fare.NightSurcharge,
            Discount = discount,
            VoucherId = voucher?.Id,
            VoucherCode = voucher?.Code,
            PaymentMethod = req.PaymentMethod,
            EstimatedPrice = fare.TotalEstimatedFare,
            Status = BookingStatus.SearchingDriver,
            CustomerNote = req.CustomerNote,
            CreatedAt = DateTime.UtcNow
        };

        db.Bookings.Add(booking);
        await db.SaveChangesAsync();

        db.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = booking.Id,
            OldStatus = null,
            NewStatus = DrivoDbContext.ToSnakeUpper(BookingStatus.SearchingDriver.ToString()),
            ChangedByUserId = userId,
            Reason = "Khách hàng tạo cuốc mới",
            ChangedAt = DateTime.UtcNow
        });
        await db.SaveChangesAsync();

        // Gửi ngay lượt 1 cho tài xế điểm cao nhất
        await DispatchAsync(booking);

        await NotifyStatusAsync(booking);
        return await GetBookingByIdAsync(booking.Id, userId);
    }

    public async Task<BaseResponse<BookingDetailResponse?>> GetActiveBookingAsync(int userId)
    {
        var customer = await db.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BaseResponse<BookingDetailResponse?>.Ok(null);

        var booking = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .Include(b => b.Driver)
                .ThenInclude(d => d!.User)
            .Where(b => b.CustomerId == customer.Id &&
                        b.Status != BookingStatus.Completed &&
                        b.Status != BookingStatus.Cancelled)
            .OrderByDescending(b => b.CreatedAt)
            .FirstOrDefaultAsync();

        if (booking == null)
            return BaseResponse<BookingDetailResponse?>.Ok(null);

        return BaseResponse<BookingDetailResponse?>.Ok(MapToDetailResponse(booking));
    }

    public async Task<BaseResponse<BookingDetailResponse>> GetBookingByIdAsync(long bookingId, int userId)
    {
        var booking = await db.Bookings
            .Include(b => b.Customer)
            .Include(b => b.CustomerVehicle)
            .Include(b => b.Driver)
                .ThenInclude(d => d!.User)
            .FirstOrDefaultAsync(b => b.Id == bookingId);

        if (booking == null)
            return BaseResponse<BookingDetailResponse>.Fail("Không tìm thấy cuốc xe.");

        bool isCustomer = booking.Customer != null && booking.Customer.UserId == userId;
        bool isDriver = booking.Driver != null && booking.Driver.UserId == userId;

        if (!isCustomer && !isDriver)
            return BaseResponse<BookingDetailResponse>.Fail("Bạn không có quyền truy cập cuốc xe này.");

        return BaseResponse<BookingDetailResponse>.Ok(MapToDetailResponse(booking));
    }

    public async Task<BaseResponse<bool>> CancelBookingAsync(long bookingId, int userId, CancelBookingRequest req)
    {
        var customer = await db.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BaseResponse<bool>.Fail("Không tìm thấy thông tin khách hàng.");

        var booking = await db.Bookings.FirstOrDefaultAsync(b => b.Id == bookingId && b.CustomerId == customer.Id);
        if (booking == null)
            return BaseResponse<bool>.Fail("Không tìm thấy cuốc xe.");

        if (booking.Status == BookingStatus.Completed || booking.Status == BookingStatus.Cancelled)
            return BaseResponse<bool>.Fail("Cuốc xe đã kết thúc hoặc đã hủy trước đó.");

        var oldStatus = booking.Status;
        booking.Status = BookingStatus.Cancelled;
        booking.CancelledBy = "CUSTOMER";
        booking.CancellationReason = req.Reason ?? "Khách hàng hủy";
        booking.CancelledAt = DateTime.UtcNow;
        booking.UpdatedAt = DateTime.UtcNow;

        if (booking.DriverId.HasValue)
        {
            var driver = await db.Drivers.FirstOrDefaultAsync(d => d.Id == booking.DriverId.Value);
            if (driver != null && driver.DriverStatus == DriverStatus.Busy)
            {
                LogDriverStatusChange(driver.Id, driver.DriverStatus, DriverStatus.Online, "Khách hủy chuyến", DateTime.UtcNow);
                driver.DriverStatus = DriverStatus.Online;
                driver.UpdatedAt = DateTime.UtcNow;
            }
        }

        db.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = booking.Id,
            OldStatus = DrivoDbContext.ToSnakeUpper(oldStatus.ToString()),
            NewStatus = DrivoDbContext.ToSnakeUpper(BookingStatus.Cancelled.ToString()),
            ChangedByUserId = userId,
            Reason = req.Reason ?? "Khách hàng hủy",
            ChangedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync();
        await ReleaseVoucherAsync(booking);
        await NotifyStatusAsync(booking);
        return BaseResponse<bool>.Ok(true, "Hủy chuyến thành công.");
    }

    public async Task<BaseResponse<bool>> CancelBookingByDriverAsync(long bookingId, int userId, CancelBookingRequest req)
    {
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<bool>.Fail("Không tìm thấy thông tin tài xế.");

        var booking = await db.Bookings.FirstOrDefaultAsync(b => b.Id == bookingId && b.DriverId == driver.Id);
        if (booking == null)
            return BaseResponse<bool>.Fail("Không tìm thấy cuốc xe.");

        if (booking.Status == BookingStatus.Completed || booking.Status == BookingStatus.Cancelled)
            return BaseResponse<bool>.Fail("Cuốc xe đã kết thúc hoặc đã hủy trước đó.");

        var oldStatus = booking.Status;
        booking.Status = BookingStatus.Cancelled;
        booking.CancelledBy = "DRIVER";
        booking.CancellationReason = req.Reason ?? "Tài xế hủy";
        booking.CancelledAt = DateTime.UtcNow;
        booking.UpdatedAt = DateTime.UtcNow;

        LogDriverStatusChange(driver.Id, driver.DriverStatus, DriverStatus.Online, req.Reason ?? "Tài xế hủy chuyến", DateTime.UtcNow);
        driver.DriverStatus = DriverStatus.Online;
        driver.UpdatedAt = DateTime.UtcNow;

        db.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = booking.Id,
            OldStatus = DrivoDbContext.ToSnakeUpper(oldStatus.ToString()),
            NewStatus = DrivoDbContext.ToSnakeUpper(BookingStatus.Cancelled.ToString()),
            ChangedByUserId = userId,
            Reason = req.Reason ?? "Tài xế hủy",
            ChangedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync();
        await ReleaseVoucherAsync(booking);
        await NotifyStatusAsync(booking);
        return BaseResponse<bool>.Ok(true, "Hủy chuyến thành công.");
    }

    public async Task<BaseResponse<List<BookingDetailResponse>>> GetCustomerBookingsAsync(int userId, int page, int pageSize)
    {
        var customer = await db.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BaseResponse<List<BookingDetailResponse>>.Ok([]);

        var bookings = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .Include(b => b.Driver)
                .ThenInclude(d => d!.User)
            .Where(b => b.CustomerId == customer.Id)
            .OrderByDescending(b => b.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        var list = bookings.Select(b => MapToDetailResponse(b)).ToList();
        return BaseResponse<List<BookingDetailResponse>>.Ok(list);
    }

    private static T MapToDetailResponse<T>(Booking b, T dto) where T : BookingDetailResponse
    {
        dto.Id = b.Id;
        dto.BookingCode = b.BookingCode;
        dto.Status = b.Status.ToString();
        dto.PickupAddress = b.PickupAddress;
        dto.PickupLatitude = b.PickupLatitude;
        dto.PickupLongitude = b.PickupLongitude;
        dto.DestinationAddress = b.DestinationAddress;
        dto.DestinationLatitude = b.DestinationLatitude;
        dto.DestinationLongitude = b.DestinationLongitude;
        dto.EstimatedDistanceKm = b.EstimatedDistanceKm ?? 0;
        dto.EstimatedDurationMin = b.EstimatedDurationMin ?? 0;
        dto.BaseFare = b.BaseFare;
        dto.DistanceFare = b.DistanceFare;
        dto.TimeFare = b.TimeFare;
        dto.Surcharge = b.Surcharge;
        dto.EstimatedPrice = b.EstimatedPrice;
        dto.FinalPrice = b.FinalPrice;
        dto.CustomerNote = b.CustomerNote;
        dto.CreatedAt = b.CreatedAt;
        dto.RoutePolyline = b.RoutePolyline;
        dto.PickupDistanceKm = b.PickupDistanceKm;
        dto.PickupFee = b.PickupFee;
        dto.WaitingFee = b.WaitingFee;
        dto.ExtraDistanceFee = b.ExtraDistanceFee;
        dto.Discount = b.Discount;
        dto.ActualDistanceKm = b.ActualDistanceKm;
        dto.CommissionAmount = b.CommissionAmount;
        dto.DriverPayout = b.DriverPayout;
        dto.PaymentMethod = b.PaymentMethod.ToString();
        dto.VoucherCode = b.VoucherCode;
        dto.AcceptedAt = b.AcceptedAt;
        dto.ArrivedAt = b.ArrivedAt;
        dto.StartedAt = b.StartedAt;
        dto.CompletedAt = b.CompletedAt;
        dto.Vehicle = new BookingVehicleSummaryDto
        {
            Id = b.CustomerVehicle.Id,
            Brand = b.CustomerVehicle.Brand,
            Model = b.CustomerVehicle.Model,
            LicensePlate = b.CustomerVehicle.LicensePlate,
            Transmission = b.CustomerVehicle.Transmission.ToString()
        };
        if (b.Driver != null)
        {
            dto.Driver = new BookingDriverSummaryDto
            {
                Id = b.Driver.Id,
                FullName = b.Driver.User.FullName,
                Phone = b.Driver.User.Phone,
                AvatarUrl = b.Driver.User.AvatarUrl,
                Rating = b.Driver.RatingAverage
            };
            dto.DriverLatitude = b.Driver.CurrentLatitude;
            dto.DriverLongitude = b.Driver.CurrentLongitude;
            dto.DriverLastLocationAt = b.Driver.LastLocationAt;
        }
        return dto;
    }

    private static BookingDetailResponse MapToDetailResponse(Booking b) => MapToDetailResponse(b, new BookingDetailResponse());

    // ══════════════════════════════════════════════════════════
    //  DRIVER METHODS
    // ══════════════════════════════════════════════════════════

    public async Task<BaseResponse<bool>> ToggleDriverStatusAsync(int userId, bool isOnline, decimal? latitude = null, decimal? longitude = null)
    {
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<bool>.Fail("Không tìm thấy thông tin tài xế.");

        if (isOnline && driver.VerificationStatus != VerificationStatus.Approved)
            return BaseResponse<bool>.Fail("Tài khoản tài xế chưa được duyệt, chưa thể bật trực tuyến.");

        if (!isOnline && driver.DriverStatus == DriverStatus.Busy)
            return BaseResponse<bool>.Fail("Bạn đang có cuốc chưa hoàn thành, không thể ngoại tuyến.");

        var hasLocation = latitude.HasValue && longitude.HasValue && GeoUtils.IsValid(latitude.Value, longitude.Value);
        var now = DateTime.UtcNow;

        var newStatus = isOnline ? DriverStatus.Online : DriverStatus.Offline;
        LogDriverStatusChange(driver.Id, driver.DriverStatus, newStatus,
            isOnline ? "Tài xế bật trực tuyến" : "Tài xế tắt trực tuyến", now);
        if (!isOnline)
        {
            // Nhả các cuốc đang ưu tiên cho mình để chuyển ngay cho tài xế khác
            await db.BookingDriverOffers
                .Where(o => o.DriverId == driver.Id && o.OfferStatus == OfferStatus.Sent)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.OfferStatus, OfferStatus.Cancelled).SetProperty(o => o.RespondedAt, now));
        }
        driver.DriverStatus = newStatus;
        driver.UpdatedAt = now;
        if (hasLocation)
        {
            driver.CurrentLatitude = Math.Round(latitude!.Value, 7);
            driver.CurrentLongitude = Math.Round(longitude!.Value, 7);
            driver.LastLocationAt = now;
        }
        await db.SaveChangesAsync();

        if (hasLocation)
        {
            await notifier.DriverLocationAsync(new DriverLocationEvent
            {
                DriverId = driver.Id,
                Latitude = driver.CurrentLatitude!.Value,
                Longitude = driver.CurrentLongitude!.Value,
                DriverStatus = driver.DriverStatus.ToString(),
                RecordedAt = now
            });
        }

        return BaseResponse<bool>.Ok(true, isOnline ? "Bạn đang trực tuyến." : "Bạn đã ngoại tuyến.");
    }

    // ══════════════════════════════════════════════════════════
    //  ĐIỀU PHỐI CUỐC: gửi lần lượt cho tài xế điểm cao nhất
    // ══════════════════════════════════════════════════════════
    //  Mỗi lượt: 1 tài xế được ưu tiên trong OfferTimeout. Bỏ qua / hết giờ -> lượt sau.
    //  Hết MaxOfferRounds lượt hoặc không còn ứng viên -> mở cho mọi tài xế trong bán kính.
    //  Không có tiến trình nền: trạng thái được đẩy tiếp mỗi khi tài xế lấy danh sách cuốc (5 giây/lần).

    private static readonly TimeSpan OfferTimeout = TimeSpan.FromMinutes(3);
    private const int MaxOfferRounds = 3;
    /// <summary>Lượt ghi nhận tài xế bấm Bỏ qua khi cuốc đã mở cho mọi người (không tính vào lượt ưu tiên).</summary>
    private const int BroadcastSkipRound = MaxOfferRounds + 1;
    private const double WeightDistance = 0.6, WeightRating = 0.2, WeightCompletion = 0.2;
    /// <summary>Tài xế chưa đủ dữ liệu được tính mức trung bình khá (≈ 4,5 sao / 90% hoàn thành).</summary>
    private const double DefaultRatingScore = 0.9, DefaultCompletionScore = 0.9;
    private const int MinTripsForCompletionRate = 3;

    private sealed record DriverCandidate(int DriverId, double Km, double Score);

    /// <summary>Tài xế trực tuyến, đã duyệt, vị trí mới, trong bán kính; xếp theo điểm giảm dần.</summary>
    private async Task<List<DriverCandidate>> RankCandidatesAsync(Booking b, ICollection<int> excludeDriverIds)
    {
        var since = DateTime.UtcNow - FreshLocationWindow;
        var drivers = await db.Drivers.AsNoTracking()
            .Where(d => d.DriverStatus == DriverStatus.Online &&
                        d.VerificationStatus == VerificationStatus.Approved &&
                        d.User.Status == UserStatus.Active &&
                        d.CurrentLatitude != null && d.CurrentLongitude != null &&
                        d.LastLocationAt != null && d.LastLocationAt >= since &&
                        !excludeDriverIds.Contains(d.Id))
            .Select(d => new { d.Id, Lat = d.CurrentLatitude!.Value, Lng = d.CurrentLongitude!.Value, d.RatingAverage, d.RatingCount })
            .ToListAsync();

        var nearby = drivers
            .Where(d => GeoUtils.IsValid(d.Lat, d.Lng))
            .Select(d => new { d.Id, d.RatingAverage, d.RatingCount, Km = GeoUtils.HaversineKm(d.Lat, d.Lng, b.PickupLatitude, b.PickupLongitude) })
            .Where(d => d.Km <= PendingSearchRadiusKm)
            .ToList();
        if (nearby.Count == 0) return [];

        // Tỉ lệ hoàn thành 30 ngày: hoàn thành / (hoàn thành + tài xế tự hủy). Khách hủy không tính cho tài xế.
        var ids = nearby.Select(d => d.Id).ToList();
        var from = DateTime.UtcNow.AddDays(-30);
        var stats = await db.Bookings.AsNoTracking()
            .Where(x => x.DriverId != null && ids.Contains(x.DriverId.Value) && x.CreatedAt >= from &&
                        (x.Status == BookingStatus.Completed || (x.Status == BookingStatus.Cancelled && x.CancelledBy == "DRIVER")))
            .GroupBy(x => x.DriverId!.Value)
            .Select(g => new { DriverId = g.Key, Completed = g.Count(x => x.Status == BookingStatus.Completed), Total = g.Count() })
            .ToDictionaryAsync(x => x.DriverId);

        return nearby
            .Select(d =>
            {
                var distance = 1.0 - d.Km / PendingSearchRadiusKm;
                var rating = d.RatingCount > 0 ? (double)d.RatingAverage / 5.0 : DefaultRatingScore;
                var completion = stats.TryGetValue(d.Id, out var s) && s.Total >= MinTripsForCompletionRate
                    ? (double)s.Completed / s.Total
                    : DefaultCompletionScore;
                return new DriverCandidate(d.Id, d.Km, WeightDistance * distance + WeightRating * rating + WeightCompletion * completion);
            })
            .OrderByDescending(c => c.Score)
            .ThenBy(c => c.Km)
            .ToList();
    }

    /// <summary>
    /// Đẩy trạng thái điều phối của 1 cuốc: hết giờ -> Expired, rồi gửi lượt tiếp cho ứng viên tốt nhất chưa được gửi.
    /// Trả về các offer hiện có của cuốc (đã cập nhật).
    /// </summary>
    private async Task<List<BookingDriverOffer>> DispatchAsync(Booking b)
    {
        var now = DateTime.UtcNow;
        var offers = await db.BookingDriverOffers.AsNoTracking().Where(o => o.BookingId == b.Id && o.OfferRound <= BroadcastSkipRound).ToListAsync();

        var stale = offers.Where(o => o.OfferStatus == OfferStatus.Sent && o.SentAt + OfferTimeout <= now).Select(o => o.Id).ToList();
        if (stale.Count > 0)
        {
            await db.BookingDriverOffers
                .Where(o => stale.Contains(o.Id) && o.OfferStatus == OfferStatus.Sent)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.OfferStatus, OfferStatus.Expired).SetProperty(o => o.RespondedAt, now));
            foreach (var o in offers.Where(o => stale.Contains(o.Id))) { o.OfferStatus = OfferStatus.Expired; o.RespondedAt = now; }
        }

        if (offers.Any(o => o.OfferStatus == OfferStatus.Sent)) return offers;

        var round = offers.Where(o => o.OfferRound <= MaxOfferRounds).Select(o => o.OfferRound).DefaultIfEmpty(0).Max();
        if (round >= MaxOfferRounds) return offers;

        var best = (await RankCandidatesAsync(b, offers.Select(o => o.DriverId).ToList())).FirstOrDefault();
        if (best == null) return offers;

        var offer = new BookingDriverOffer
        {
            BookingId = b.Id,
            DriverId = best.DriverId,
            OfferRound = round + 1,
            DistanceToPickupKm = Math.Round((decimal)best.Km, 2),
            EstimatedArrivalMin = Math.Max(1, (int)Math.Ceiling(best.Km * GeoUtils.RoadFactor / GeoUtils.ScooterSpeedKmh * 60.0)),
            OfferStatus = OfferStatus.Sent,
            SentAt = now
        };
        db.BookingDriverOffers.Add(offer);
        try
        {
            await db.SaveChangesAsync();
            offers.Add(offer);
        }
        catch (DbUpdateException)
        {
            // Tài xế khác lấy danh sách cùng lúc đã tạo đúng offer này (UQ Booking+Driver+Round)
            db.Entry(offer).State = EntityState.Detached;
            offers = await db.BookingDriverOffers.AsNoTracking().Where(o => o.BookingId == b.Id && o.OfferRound <= BroadcastSkipRound).ToListAsync();
        }
        return offers;
    }

    /// <summary>Đang ưu tiên riêng cho 1 tài xế (còn hạn) hay đã mở cho mọi người.</summary>
    private static BookingDriverOffer? ActiveOffer(IEnumerable<BookingDriverOffer> offers, DateTime now) =>
        offers.FirstOrDefault(o => o.OfferStatus == OfferStatus.Sent && o.SentAt + OfferTimeout > now);

    public async Task<BaseResponse<List<BookingDetailResponse>>> GetPendingBookingsAsync(int userId)
    {
        var driver = await db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<List<BookingDetailResponse>>.Ok([]);
        if (driver.CurrentLatitude is not { } dLat || driver.CurrentLongitude is not { } dLng || !GeoUtils.IsValid(dLat, dLng))
            return BaseResponse<List<BookingDetailResponse>>.Ok([]); // chưa có vị trí -> không ghép được cuốc gần

        var candidates = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .Include(b => b.Driver)
                .ThenInclude(d => d!.User)
            .Where(b => b.Status == BookingStatus.SearchingDriver && b.DriverId == null)
            .OrderBy(b => b.CreatedAt)
            .Take(200)
            .ToListAsync();

        var nearby = candidates
            .Where(b => GeoUtils.IsValid(b.PickupLatitude, b.PickupLongitude))
            .Select(b => (Booking: b, Km: GeoUtils.HaversineKm(dLat, dLng, b.PickupLatitude, b.PickupLongitude)))
            .Where(x => x.Km <= PendingSearchRadiusKm)
            .OrderBy(x => x.Km)
            .Take(10)
            .ToList();

        var result = new List<BookingDetailResponse>();
        foreach (var (booking, km) in nearby)
        {
            var offers = await DispatchAsync(booking);
            var now = DateTime.UtcNow;
            if (offers.Any(o => o.DriverId == driver.Id && o.OfferStatus == OfferStatus.Rejected))
                continue; // tài xế đã bấm Bỏ qua cuốc này

            var active = ActiveOffer(offers, now);
            if (active != null && active.DriverId != driver.Id)
                continue; // đang ưu tiên cho tài xế khác

            var dto = MapToDetailResponse(booking);
            dto.DistanceToPickupKm = Math.Round((decimal)km, 2);
            if (active != null)
                dto.OfferSecondsLeft = Math.Max(1, (int)Math.Ceiling((active.SentAt + OfferTimeout - now).TotalSeconds));
            result.Add(dto);
        }

        // Cuốc đang ưu tiên riêng cho mình lên đầu
        return BaseResponse<List<BookingDetailResponse>>.Ok(
            result.OrderBy(d => d.OfferSecondsLeft == null).ThenBy(d => d.DistanceToPickupKm).ToList());
    }

    public async Task<BaseResponse<bool>> RejectBookingAsync(long bookingId, int userId)
    {
        var driver = await db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<bool>.Fail("Không tìm thấy thông tin tài xế.");

        var booking = await db.Bookings.AsNoTracking().FirstOrDefaultAsync(b => b.Id == bookingId);
        if (booking == null)
            return BaseResponse<bool>.Fail("Không tìm thấy cuốc xe.");

        var now = DateTime.UtcNow;
        var rejected = await db.BookingDriverOffers
            .Where(o => o.BookingId == bookingId && o.DriverId == driver.Id && o.OfferStatus == OfferStatus.Sent)
            .ExecuteUpdateAsync(s => s.SetProperty(o => o.OfferStatus, OfferStatus.Rejected).SetProperty(o => o.RespondedAt, now));

        if (rejected == 0 && !await db.BookingDriverOffers.AnyAsync(o => o.BookingId == bookingId && o.DriverId == driver.Id && o.OfferRound <= BroadcastSkipRound && o.OfferStatus == OfferStatus.Rejected))
        {
            // Cuốc đang mở cho mọi người: ghi nhận để không hiện lại cho tài xế này
            var skip = new BookingDriverOffer
            {
                BookingId = bookingId,
                DriverId = driver.Id,
                OfferRound = BroadcastSkipRound,
                OfferStatus = OfferStatus.Rejected,
                SentAt = now,
                RespondedAt = now
            };
            db.BookingDriverOffers.Add(skip);
            try { await db.SaveChangesAsync(); }
            catch (DbUpdateException) { db.Entry(skip).State = EntityState.Detached; }
        }

        // Chuyển ngay sang tài xế tiếp theo, không đợi lượt poll sau
        if (booking.Status == BookingStatus.SearchingDriver && booking.DriverId == null)
            await DispatchAsync(booking);

        return BaseResponse<bool>.Ok(true, "Đã bỏ qua cuốc.");
    }

    /// <summary>
    /// Khách bấm "Làm mới" khi chờ lâu: bắt đầu lượt tìm mới từ lượt 1 (gồm cả tài xế vừa trực tuyến
    /// và người đã bỏ qua). Offer cũ được dời sang số lượt +10 để giữ lịch sử mà không tính vào lượt tìm mới.
    /// </summary>
    public async Task<BaseResponse<bool>> RetrySearchAsync(long bookingId, int userId)
    {
        var customer = await db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.UserId == userId);
        var booking = customer == null ? null : await db.Bookings.FirstOrDefaultAsync(b => b.Id == bookingId && b.CustomerId == customer.Id);
        if (booking == null)
            return BaseResponse<bool>.Fail("Không tìm thấy chuyến đi.");
        if (booking.Status != BookingStatus.SearchingDriver || booking.DriverId != null)
            return BaseResponse<bool>.Fail("Chuyến đi không còn ở trạng thái tìm tài xế.");

        var now = DateTime.UtcNow;
        await db.BookingDriverOffers
            .Where(o => o.BookingId == bookingId && o.OfferStatus == OfferStatus.Sent)
            .ExecuteUpdateAsync(s => s.SetProperty(o => o.OfferStatus, OfferStatus.Cancelled).SetProperty(o => o.RespondedAt, now));
        await db.BookingDriverOffers
            .Where(o => o.BookingId == bookingId)
            .ExecuteUpdateAsync(s => s.SetProperty(o => o.OfferRound, o => o.OfferRound + 10));

        var offers = await DispatchAsync(booking);
        var active = ActiveOffer(offers, DateTime.UtcNow);
        return BaseResponse<bool>.Ok(true, active != null
            ? "Đã tìm lại, đang gửi yêu cầu cho tài xế gần bạn."
            : "Đã tìm lại. Hiện chưa có tài xế trực tuyến gần bạn.");
    }

    public async Task<BaseResponse<BookingDetailResponse>> AcceptBookingAsync(long bookingId, int userId)
    {
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<BookingDetailResponse>.Fail("Không tìm thấy tài xế.");

        if (driver.DriverStatus != DriverStatus.Online)
            return BaseResponse<BookingDetailResponse>.Fail("Bạn cần bật trực tuyến để nhận cuốc.");

        // Check if driver already has an active booking
        var hasActive = await db.Bookings.AnyAsync(b =>
            b.DriverId == driver.Id &&
            b.Status != BookingStatus.Completed &&
            b.Status != BookingStatus.Cancelled);
        if (hasActive)
            return BaseResponse<BookingDetailResponse>.Fail("Bạn đang có cuốc chưa hoàn thành.");

        var now = DateTime.UtcNow;

        // Đang trong lượt ưu tiên của tài xế khác thì chưa được nhận (cho thêm 3 giây bù độ trễ mạng)
        var offers = await db.BookingDriverOffers.AsNoTracking().Where(o => o.BookingId == bookingId && o.OfferRound <= BroadcastSkipRound).ToListAsync();
        if (offers.Any(o => o.DriverId == driver.Id && o.OfferStatus == OfferStatus.Rejected))
            return BaseResponse<BookingDetailResponse>.Fail("Bạn đã bỏ qua cuốc này.");
        var mine = offers.FirstOrDefault(o => o.DriverId == driver.Id && o.OfferStatus == OfferStatus.Sent &&
                                              o.SentAt + OfferTimeout + TimeSpan.FromSeconds(3) > now);
        if (mine == null && ActiveOffer(offers, now) is { } other && other.DriverId != driver.Id)
            return BaseResponse<BookingDetailResponse>.Fail("Cuốc này đang được ưu tiên cho tài xế khác.");

        // Giành cuốc bằng 1 UPDATE có điều kiện ở DB (atomic) -> 2 tài xế bấm nhận cùng lúc
        // chỉ 1 người giành được; nếu dùng SaveChangesAsync bình thường (đọc rồi ghi) người ghi
        // sau sẽ âm thầm đè lên người ghi trước mà không có lỗi gì (không có RowVersion).
        var claimed = await db.Bookings
            .Where(b => b.Id == bookingId && b.Status == BookingStatus.SearchingDriver && b.DriverId == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(b => b.DriverId, driver.Id)
                .SetProperty(b => b.Status, BookingStatus.DriverAccepted)
                .SetProperty(b => b.AcceptedAt, now)
                .SetProperty(b => b.UpdatedAt, now));

        if (claimed == 0)
            return BaseResponse<BookingDetailResponse>.Fail("Cuốc xe không còn khả dụng.");

        // Cùng lý do: giành quyền "bận" cho tài xế để tránh 1 tài xế nhận trúng 2 cuốc cùng lúc.
        var driverClaimed = await db.Drivers
            .Where(d => d.Id == driver.Id && d.DriverStatus == DriverStatus.Online)
            .ExecuteUpdateAsync(s => s
                .SetProperty(d => d.DriverStatus, DriverStatus.Busy)
                .SetProperty(d => d.UpdatedAt, now));

        if (driverClaimed == 0)
        {
            // Tài xế vừa nhận một cuốc khác đúng lúc này -> nhả lại cuốc vừa giành cho người khác.
            await db.Bookings
                .Where(b => b.Id == bookingId && b.DriverId == driver.Id && b.Status == BookingStatus.DriverAccepted)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(b => b.DriverId, (int?)null)
                    .SetProperty(b => b.Status, BookingStatus.SearchingDriver)
                    .SetProperty(b => b.AcceptedAt, (DateTime?)null));
            return BaseResponse<BookingDetailResponse>.Fail("Bạn vừa nhận một cuốc khác.");
        }

        // Lịch sử điều phối: offer của mình -> Accepted, offer còn treo của người khác -> Cancelled
        await db.BookingDriverOffers
            .Where(o => o.BookingId == bookingId && o.DriverId == driver.Id && o.OfferStatus == OfferStatus.Sent)
            .ExecuteUpdateAsync(s => s.SetProperty(o => o.OfferStatus, OfferStatus.Accepted).SetProperty(o => o.RespondedAt, now));
        await db.BookingDriverOffers
            .Where(o => o.BookingId == bookingId && o.OfferStatus == OfferStatus.Sent)
            .ExecuteUpdateAsync(s => s.SetProperty(o => o.OfferStatus, OfferStatus.Cancelled).SetProperty(o => o.RespondedAt, now));

        var booking = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .FirstAsync(b => b.Id == bookingId);

        // ExecuteUpdateAsync không đụng tới entity đang track -> driver.DriverStatus trong bộ nhớ vẫn là Online.
        LogDriverStatusChange(driver.Id, DriverStatus.Online, DriverStatus.Busy, $"Nhận chuyến {booking.BookingCode}", now);

        // Chặng đón: tài xế (xe điện gấp) → điểm đón. Chỉ mình tài xế này còn giữ cuốc nên an toàn để ghi tiếp.
        if (driver.CurrentLatitude is { } dLat && driver.CurrentLongitude is { } dLng &&
            GeoUtils.IsValid(dLat, dLng) && GeoUtils.IsValid(booking.PickupLatitude, booking.PickupLongitude))
        {
            var rule = await GetPricingRuleForBookingAsync(booking);
            var pickupRoute = await maps.GetRouteAsync(
                (double)dLat, (double)dLng,
                (double)booking.PickupLatitude, (double)booking.PickupLongitude, "TWO_WHEELER");
            booking.PickupDistanceKm = pickupRoute.DistanceKm;
            booking.PickupFee = CalcPickupFee(pickupRoute.DistanceKm, rule);
            booking.UpdatedAt = DateTime.UtcNow;
        }

        db.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = booking.Id,
            OldStatus = DrivoDbContext.ToSnakeUpper(BookingStatus.SearchingDriver.ToString()),
            NewStatus = DrivoDbContext.ToSnakeUpper(BookingStatus.DriverAccepted.ToString()),
            ChangedByUserId = userId,
            Reason = "Tài xế nhận cuốc",
            ChangedAt = now
        });

        await db.SaveChangesAsync();
        await NotifyStatusAsync(booking);
        return await GetBookingByIdAsync(booking.Id, userId);
    }

    public async Task<BaseResponse<BookingDetailResponse>> UpdateBookingStatusAsync(long bookingId, int userId, string newStatus)
    {
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<BookingDetailResponse>.Fail("Không tìm thấy tài xế.");

        var booking = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .Include(b => b.Driver)
                .ThenInclude(d => d!.User)
            .FirstOrDefaultAsync(b => b.Id == bookingId && b.DriverId == driver.Id);

        if (booking == null)
            return BaseResponse<BookingDetailResponse>.Fail("Không tìm thấy cuốc xe.");

        if (!Enum.TryParse<BookingStatus>(newStatus, out var parsedStatus))
            return BaseResponse<BookingDetailResponse>.Fail("Trạng thái không hợp lệ.");

        // Validate transition
        var validTransitions = new Dictionary<BookingStatus, BookingStatus>
        {
            [BookingStatus.DriverAccepted] = BookingStatus.DriverArriving,
            [BookingStatus.DriverArriving] = BookingStatus.DriverArrived,
            [BookingStatus.DriverArrived] = BookingStatus.InProgress,
            [BookingStatus.InProgress] = BookingStatus.Completed,
        };

        if (!validTransitions.TryGetValue(booking.Status, out var expectedNext) || expectedNext != parsedStatus)
            return BaseResponse<BookingDetailResponse>.Fail($"Không thể chuyển từ {booking.Status} sang {parsedStatus}.");

        var now = DateTime.UtcNow;
        var oldStatus = booking.Status;
        booking.Status = parsedStatus;
        booking.UpdatedAt = now;

        switch (parsedStatus)
        {
            case BookingStatus.DriverArrived:
                booking.ArrivedAt = now;
                break;
            case BookingStatus.InProgress:
                booking.StartedAt = now;
                break;
            case BookingStatus.Completed:
                await CompleteBookingAsync(booking, driver, now);
                break;
        }

        db.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = booking.Id,
            OldStatus = DrivoDbContext.ToSnakeUpper(oldStatus.ToString()),
            NewStatus = DrivoDbContext.ToSnakeUpper(parsedStatus.ToString()),
            ChangedByUserId = userId,
            Reason = "Cập nhật trạng thái",
            ChangedAt = now
        });

        await db.SaveChangesAsync();
        await NotifyStatusAsync(booking);
        return BaseResponse<BookingDetailResponse>.Ok(MapToDetailResponse(booking));
    }

    /// <summary>Ghi lịch sử đổi DriverStatus (Online/Busy/Offline) để hiển thị ở trang chi tiết tài xế trên admin.</summary>
    private void LogDriverStatusChange(int driverId, DriverStatus oldStatus, DriverStatus newStatus, string? reason, DateTime at)
    {
        if (oldStatus == newStatus) return;
        // CK_DriverStatusHistory_* chỉ chấp nhận 'ONLINE' | 'BUSY' | 'OFFLINE' | 'SUSPENDED'.
        db.DriverStatusHistories.Add(new DriverStatusHistory
        {
            DriverId = driverId,
            OldStatus = oldStatus.ToString().ToUpperInvariant(),
            NewStatus = newStatus.ToString().ToUpperInvariant(),
            Reason = reason,
            ChangedAt = at
        });
    }

    /// <summary>Chốt giá khi hoàn thành: phí chờ, quãng đường thực tế (GPS), phụ phí vượt quãng đường, Trip.</summary>
    private async Task CompleteBookingAsync(Booking booking, Driver driver, DateTime now)
    {
        booking.CompletedAt = now;
        var rule = await GetPricingRuleForBookingAsync(booking);

        // Phí chờ: từ lúc tài xế tới nơi đến lúc bắt đầu chạy, vượt quá số phút miễn phí
        if (booking.ArrivedAt.HasValue && booking.StartedAt.HasValue)
        {
            var waitedMin = Math.Floor((decimal)(booking.StartedAt.Value - booking.ArrivedAt.Value).TotalMinutes);
            booking.WaitingFee = GeoUtils.Round1000(Math.Max(0m, waitedMin - rule.FreeWaitingMin) * rule.WaitingPricePerMin);
        }

        // Quãng đường thực tế từ lịch sử GPS trong khoảng InProgress
        var estKm = booking.EstimatedDistanceKm ?? 0m;
        var actualKm = await ComputeActualDistanceKmAsync(booking.Id, booking.StartedAt, now) ?? estKm;
        booking.ActualDistanceKm = actualKm;

        var threshold = estKm * (1m + rule.OverDistanceTolerancePercent / 100m);
        booking.ExtraDistanceFee = actualKm > threshold
            ? GeoUtils.Round1000((actualKm - estKm) * rule.PricePerKm)
            : 0m;

        booking.FinalPrice = Math.Max(0m,
            booking.EstimatedPrice + booking.PickupFee + booking.WaitingFee + booking.ExtraDistanceFee - booking.Discount);

        // Chia doanh thu trên giá TRƯỚC voucher: nền tảng chịu toàn bộ tiền giảm giá, tài xế nhận đủ.
        // CommissionAmount = phần nền tảng thực thu (có thể âm khi voucher lớn hơn hoa hồng).
        var gross = booking.FinalPrice.Value + booking.Discount;
        booking.DriverPayout = gross - GeoUtils.Round1000(gross * rule.CommissionPercent / 100m);
        booking.CommissionAmount = booking.FinalPrice.Value - booking.DriverPayout;

        driver.TotalTrips += 1;
        driver.TotalEarnings += booking.DriverPayout;
        LogDriverStatusChange(driver.Id, driver.DriverStatus, DriverStatus.Online, $"Hoàn thành chuyến {booking.BookingCode}", now);
        driver.DriverStatus = DriverStatus.Online;
        driver.UpdatedAt = now;

        var durationMin = booking.StartedAt.HasValue
            ? Math.Max(0, (int)Math.Round((now - booking.StartedAt.Value).TotalMinutes))
            : booking.EstimatedDurationMin;

        var trip = new Trip
        {
            BookingId = booking.Id,
            DriverId = driver.Id,
            StartTime = booking.StartedAt,
            EndTime = now,
            StartLatitude = booking.PickupLatitude,
            StartLongitude = booking.PickupLongitude,
            EndLatitude = driver.CurrentLatitude ?? booking.DestinationLatitude,
            EndLongitude = driver.CurrentLongitude ?? booking.DestinationLongitude,
            ActualDistanceKm = actualKm,
            ActualDurationMin = durationMin,
            Status = "COMPLETED",
            CreatedAt = now
        };
        db.Trips.Add(trip);

        // Tiền mặt: tài xế thu tại chỗ khi hoàn thành. Ví/chuyển khoản hiện là giả lập -> coi như trừ thành công.
        var isCash = booking.PaymentMethod == PaymentMethod.Cash;
        db.Payments.Add(new Payment
        {
            Trip = trip,
            CustomerId = booking.CustomerId,
            Amount = booking.FinalPrice.Value,
            Currency = "VND",
            PaymentMethod = booking.PaymentMethod,
            PaymentStatus = PaymentStatus.Success,
            PaidAt = now,
            CreatedAt = now,
            Transactions =
            [
                new PaymentTransaction
                {
                    TransactionCode = $"PAY-{booking.BookingCode}",
                    TransactionType = "CHARGE",
                    Amount = booking.FinalPrice.Value,
                    Status = "SUCCESS",
                    Provider = isCash ? "CASH" : "MOCK",
                    CreatedAt = now,
                    CompletedAt = now
                }
            ]
        });
    }

    /// <summary>
    /// Tổng haversine giữa các điểm GPS liên tiếp của cuốc trong [from, to].
    /// Bỏ điểm có AccuracyMeters &gt; 50 và đoạn có vận tốc &gt; 150 km/h. Null nếu &lt; 2 điểm hợp lệ.
    /// </summary>
    private async Task<decimal?> ComputeActualDistanceKmAsync(long bookingId, DateTime? from, DateTime to)
    {
        if (!from.HasValue) return null;

        var points = await db.DriverLocationHistories.AsNoTracking()
            .Where(h => h.BookingId == bookingId && h.RecordedAt >= from.Value && h.RecordedAt <= to)
            .OrderBy(h => h.RecordedAt).ThenBy(h => h.Id)
            .Select(h => new { h.Latitude, h.Longitude, h.AccuracyMeters, h.RecordedAt })
            .ToListAsync();

        var valid = points.Where(p => p.AccuracyMeters == null || (double)p.AccuracyMeters <= MaxGpsAccuracyMeters).ToList();
        if (valid.Count < 2) return null;

        double total = 0;
        var prev = valid[0];
        var used = 1;
        foreach (var p in valid.Skip(1))
        {
            var km = GeoUtils.HaversineKm(prev.Latitude, prev.Longitude, p.Latitude, p.Longitude);
            var hours = (p.RecordedAt - prev.RecordedAt).TotalHours;
            if (hours <= 0) continue;                          // trùng thời điểm
            if (km / hours > MaxPlausibleSpeedKmh) continue;   // GPS nhảy bất thường
            total += km;
            prev = p;
            used++;
        }

        return used < 2 ? null : Math.Round((decimal)total, 2);
    }

    public async Task<BaseResponse<object>> UpdateDriverLocationAsync(int userId, UpdateDriverLocationRequest req)
    {
        if (!GeoUtils.IsValid(req.Latitude, req.Longitude))
            return BaseResponse<object>.Fail("Tọa độ không hợp lệ.");

        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<object>.Fail("Không tìm thấy tài xế.");

        var now = DateTime.UtcNow;
        if (driver.LastLocationAt.HasValue && now - driver.LastLocationAt.Value < LocationThrottle)
            return BaseResponse<object>.Ok(new { ok = true });

        var lat = Math.Round(req.Latitude, 7);
        var lng = Math.Round(req.Longitude, 7);
        decimal? accuracy = req.AccuracyMeters is { } a && a >= 0 ? Math.Round(Math.Min(a, 999_999m), 2) : null;
        decimal? speed = req.SpeedKmh is { } s && s >= 0 ? Math.Round(Math.Min(s, 999_999m), 2) : null;
        decimal? heading = req.Heading is { } h ? Math.Round(((h % 360m) + 360m) % 360m, 2) : null;

        driver.CurrentLatitude = lat;
        driver.CurrentLongitude = lng;
        driver.LastLocationAt = now;

        var activeBookingId = await db.Bookings
            .Where(b => b.DriverId == driver.Id)
            .Where(IsDriverActiveStatus)
            .OrderByDescending(b => b.CreatedAt)
            .Select(b => (long?)b.Id)
            .FirstOrDefaultAsync();

        var saveHistory = activeBookingId.HasValue;
        if (!saveHistory)
        {
            var lastIdle = await db.DriverLocationHistories
                .Where(x => x.DriverId == driver.Id && x.BookingId == null)
                .MaxAsync(x => (DateTime?)x.RecordedAt);
            saveHistory = lastIdle == null || now - lastIdle.Value >= IdleHistoryInterval;
        }

        if (saveHistory)
        {
            db.DriverLocationHistories.Add(new DriverLocationHistory
            {
                DriverId = driver.Id,
                BookingId = activeBookingId,
                Latitude = lat,
                Longitude = lng,
                AccuracyMeters = accuracy,
                SpeedKmh = speed,
                Heading = heading,
                RecordedAt = now
            });
        }

        await db.SaveChangesAsync();

        await notifier.DriverLocationAsync(new DriverLocationEvent
        {
            DriverId = driver.Id,
            BookingId = activeBookingId,
            Latitude = lat,
            Longitude = lng,
            Heading = heading,
            SpeedKmh = speed,
            DriverStatus = driver.DriverStatus.ToString(),
            RecordedAt = now
        });

        return BaseResponse<object>.Ok(new { ok = true });
    }

    public async Task<BaseResponse<BookingDetailResponse?>> GetDriverActiveBookingAsync(int userId)
    {
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<BookingDetailResponse?>.Ok(null);

        var booking = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .Include(b => b.Driver)
                .ThenInclude(d => d!.User)
            .Where(b => b.DriverId == driver.Id &&
                        b.Status != BookingStatus.Completed &&
                        b.Status != BookingStatus.Cancelled)
            .OrderByDescending(b => b.CreatedAt)
            .FirstOrDefaultAsync();

        return BaseResponse<BookingDetailResponse?>.Ok(booking != null ? MapToDetailResponse(booking) : null);
    }

    public async Task<BaseResponse<DriverEarningsResponse>> GetDriverEarningsAsync(int userId, string period, DateTime? date)
    {
        var driver = await db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<DriverEarningsResponse>.Fail("Không tìm thấy thông tin tài xế.");

        period = (period ?? "day").ToLowerInvariant();
        var anchor = (date ?? VnClock.Today).Date;
        DateTime fromLocal;
        int days;
        switch (period)
        {
            case "week":
                fromLocal = anchor.AddDays(-(((int)anchor.DayOfWeek + 6) % 7)); // thứ Hai
                days = 7;
                break;
            case "month":
                fromLocal = new DateTime(anchor.Year, anchor.Month, 1);
                days = DateTime.DaysInMonth(anchor.Year, anchor.Month);
                break;
            default:
                period = "day";
                fromLocal = anchor;
                days = 1;
                break;
        }
        var fromUtc = VnClock.StartOfDayUtc(fromLocal);
        var toUtc = VnClock.StartOfDayUtc(fromLocal.AddDays(days));

        var bookings = await db.Bookings.AsNoTracking()
            .Where(b => b.DriverId == driver.Id && b.Status == BookingStatus.Completed && b.FinalPrice != null)
            .Where(b => (b.CompletedAt ?? b.UpdatedAt ?? b.CreatedAt) >= fromUtc &&
                        (b.CompletedAt ?? b.UpdatedAt ?? b.CreatedAt) < toUtc)
            .Select(b => new
            {
                b.Id, b.BookingCode, b.PickupAddress, b.DestinationAddress,
                CompletedAt = b.CompletedAt ?? b.UpdatedAt ?? b.CreatedAt,
                FinalPrice = b.FinalPrice!.Value, b.Discount, b.DriverPayout, b.PaymentMethod
            })
            .OrderByDescending(b => b.CompletedAt)
            .ToListAsync();

        var trips = bookings.Select(b =>
        {
            var gross = b.FinalPrice + b.Discount;
            return new DriverEarningsTripDto
            {
                Id = b.Id,
                BookingCode = b.BookingCode,
                CompletedAt = b.CompletedAt,
                PickupAddress = b.PickupAddress,
                DestinationAddress = b.DestinationAddress,
                GrossFare = gross,
                Discount = b.Discount,
                CustomerPaid = b.FinalPrice,
                Commission = gross - b.DriverPayout,
                Payout = b.DriverPayout,
                PaymentMethod = b.PaymentMethod.ToString()
            };
        }).ToList();

        var res = new DriverEarningsResponse
        {
            Period = period,
            From = fromLocal.ToString("yyyy-MM-dd"),
            To = fromLocal.AddDays(days - 1).ToString("yyyy-MM-dd"),
            TripCount = trips.Count,
            GrossFare = trips.Sum(t => t.GrossFare),
            Commission = trips.Sum(t => t.Commission),
            VoucherSupport = trips.Sum(t => t.Discount),
            Payout = trips.Sum(t => t.Payout),
            CustomerPaid = trips.Sum(t => t.CustomerPaid),
            CashCollected = trips.Where(t => t.PaymentMethod == nameof(PaymentMethod.Cash)).Sum(t => t.CustomerPaid),
            Trips = trips
        };
        res.BalanceWithPlatform = res.Payout - res.CashCollected;

        if (days > 1)
        {
            string[] weekday = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"];
            for (var i = 0; i < days; i++)
            {
                var d = fromLocal.AddDays(i);
                var dayTrips = trips.Where(t => VnClock.ToLocal(t.CompletedAt).Date == d).ToList();
                res.Buckets.Add(new EarningsBucketDto
                {
                    Date = d.ToString("yyyy-MM-dd"),
                    Label = period == "week" ? weekday[(int)d.DayOfWeek] : d.Day.ToString(),
                    Trips = dayTrips.Count,
                    Payout = dayTrips.Sum(t => t.Payout)
                });
            }
        }

        return BaseResponse<DriverEarningsResponse>.Ok(res);
    }

    public async Task<BaseResponse<List<BookingDetailResponse>>> GetDriverBookingHistoryAsync(int userId, int page, int pageSize)
    {
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<List<BookingDetailResponse>>.Ok([]);

        var bookings = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .Include(b => b.Driver)
                .ThenInclude(d => d!.User)
            .Where(b => b.DriverId == driver.Id)
            .OrderByDescending(b => b.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        return BaseResponse<List<BookingDetailResponse>>.Ok(bookings.Select(b => MapToDetailResponse(b)).ToList());
    }


    public async Task<BaseResponse<bool>> RateBookingAsync(long bookingId, int userId, byte score, string comment)
    {
        // userId là User.Id (JWT); Booking.CustomerId trỏ tới Customer.Id, khác bảng.
        var customer = await db.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
            return BaseResponse<bool>.Fail("Không tìm thấy thông tin khách hàng.");

        var booking = await db.Bookings
            .Include(b => b.Trip)
            .FirstOrDefaultAsync(b => b.Id == bookingId && b.CustomerId == customer.Id);

        if (booking == null)
            return BaseResponse<bool>.Fail("Không tìm thấy chuyến đi.");

        if (booking.Status != BookingStatus.Completed)
            return BaseResponse<bool>.Fail("Chỉ có thể đánh giá chuyến đi đã hoàn thành.");

        if (booking.Trip == null)
            return BaseResponse<bool>.Fail("Không tìm thấy thông tin chi tiết chuyến đi (Trip).");

        var existingRating = await db.Ratings.FirstOrDefaultAsync(r => r.TripId == booking.Trip.Id);
        if (existingRating != null)
            return BaseResponse<bool>.Fail("Chuyến đi này đã được đánh giá.");

        var rating = new Rating
        {
            TripId = booking.Trip.Id,
            CustomerId = customer.Id,
            DriverId = booking.Trip.DriverId,
            Score = score,
            Comment = comment,
            CreatedAt = DateTime.UtcNow
        };

        db.Ratings.Add(rating);
        await db.SaveChangesAsync();

        // Feature #1: Recalculate driver's RatingAverage and RatingCount
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.Id == booking.Trip.DriverId);
        if (driver != null)
        {
            var allRatings = await db.Ratings
                .Where(r => r.DriverId == driver.Id)
                .ToListAsync();
            driver.RatingCount = allRatings.Count;
            driver.RatingAverage = allRatings.Count > 0
                ? (decimal)allRatings.Average(r => r.Score)
                : 0;
            driver.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }

        return BaseResponse<bool>.Ok(true, "Đánh giá thành công.");
    }

    // ══════════════════════════════════════════════════════════
    //  ADMIN METHODS
    // ══════════════════════════════════════════════════════════

    public async Task<BaseResponse<AdminBookingDetailResponse>> GetAdminBookingDetailAsync(long bookingId)
    {
        var b = await db.Bookings.AsNoTracking()
            .Include(x => x.Customer).ThenInclude(c => c.User)
            .Include(x => x.CustomerVehicle)
            .Include(x => x.Driver).ThenInclude(d => d!.User)
            .Include(x => x.PricingRule)
            .FirstOrDefaultAsync(x => x.Id == bookingId);

        if (b == null)
            return BaseResponse<AdminBookingDetailResponse>.Fail("Không tìm thấy chuyến đi");

        var dto = MapToDetailResponse(b, new AdminBookingDetailResponse());

        dto.Offers = await db.BookingDriverOffers.AsNoTracking()
            .Where(o => o.BookingId == bookingId)
            .OrderBy(o => o.SentAt).ThenBy(o => o.Id)
            .Select(o => new BookingOfferDto
            {
                DriverId = o.DriverId,
                DriverName = o.Driver.User.FullName,
                Round = o.OfferRound,
                DistanceToPickupKm = o.DistanceToPickupKm,
                Status = o.OfferStatus.ToString(),
                SentAt = o.SentAt,
                RespondedAt = o.RespondedAt
            })
            .ToListAsync();
        dto.Customer = new AdminBookingCustomerDto
        {
            Id = b.Customer.Id,
            FullName = b.Customer.User.FullName,
            Phone = b.Customer.User.Phone
        };
        dto.CancelledBy = b.CancelledBy;
        dto.CancellationReason = b.CancellationReason;
        dto.CancelledAt = b.CancelledAt;

        dto.Trail = await db.DriverLocationHistories.AsNoTracking()
            .Where(h => h.BookingId == bookingId)
            .OrderBy(h => h.RecordedAt).ThenBy(h => h.Id)
            .Take(10000)
            .Select(h => new TrailPointDto { Latitude = h.Latitude, Longitude = h.Longitude, RecordedAt = h.RecordedAt })
            .ToListAsync();

        var history = await db.BookingStatusHistories.AsNoTracking()
            .Where(h => h.BookingId == bookingId)
            .OrderBy(h => h.ChangedAt).ThenBy(h => h.Id)
            .ToListAsync();
        dto.StatusHistory = history.Select(h => new BookingStatusHistoryDto
        {
            Status = DrivoDbContext.FromSnakeUpper<BookingStatus>(h.NewStatus).ToString(),
            OldStatus = h.OldStatus != null ? DrivoDbContext.FromSnakeUpper<BookingStatus>(h.OldStatus).ToString() : null,
            ChangedAt = h.ChangedAt,
            Note = h.Reason
        }).ToList();

        if (b.PricingRule is { } r)
        {
            dto.PricingRule = new PricingRuleSnapshotDto
            {
                Id = r.Id,
                VehicleType = r.VehicleType.ToString(),
                BaseFare = r.BaseFare,
                PricePerKm = r.PricePerKm,
                PricePerMinute = r.PricePerMinute,
                NightSurcharge = r.NightSurcharge,
                WaitingPricePerMin = r.WaitingPricePerMin,
                FreePickupKm = r.FreePickupKm,
                PickupFeePerKm = r.PickupFeePerKm,
                FreeWaitingMin = r.FreeWaitingMin,
                OverDistanceTolerancePercent = r.OverDistanceTolerancePercent
            };
        }

        return BaseResponse<AdminBookingDetailResponse>.Ok(dto);
    }

    public async Task<BaseResponse<bool>> CancelBookingByAdminAsync(long bookingId, int adminUserId, string? reason)
    {
        var booking = await db.Bookings.FirstOrDefaultAsync(b => b.Id == bookingId);
        if (booking == null)
            return BaseResponse<bool>.Fail("Không tìm thấy chuyến đi");

        if (booking.Status == BookingStatus.Completed || booking.Status == BookingStatus.Cancelled)
            return BaseResponse<bool>.Fail("Chuyến đi đã kết thúc hoặc đã hủy trước đó.");

        var now = DateTime.UtcNow;
        var oldStatus = booking.Status;
        booking.Status = BookingStatus.Cancelled;
        booking.CancelledBy = "ADMIN";
        booking.CancellationReason = string.IsNullOrWhiteSpace(reason) ? "Admin hủy chuyến" : reason;
        booking.CancelledAt = now;
        booking.UpdatedAt = now;

        if (booking.DriverId.HasValue)
        {
            var driver = await db.Drivers.FirstOrDefaultAsync(d => d.Id == booking.DriverId.Value);
            if (driver != null && driver.DriverStatus == DriverStatus.Busy)
            {
                LogDriverStatusChange(driver.Id, driver.DriverStatus, DriverStatus.Online, "Admin hủy chuyến", now);
                driver.DriverStatus = DriverStatus.Online;
                driver.UpdatedAt = now;
            }
        }

        db.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = booking.Id,
            OldStatus = DrivoDbContext.ToSnakeUpper(oldStatus.ToString()),
            NewStatus = DrivoDbContext.ToSnakeUpper(BookingStatus.Cancelled.ToString()),
            ChangedByUserId = adminUserId > 0 ? adminUserId : null,
            Reason = booking.CancellationReason,
            ChangedAt = now
        });

        await db.SaveChangesAsync();
        await ReleaseVoucherAsync(booking);
        await NotifyStatusAsync(booking);
        return BaseResponse<bool>.Ok(true, "Đã hủy chuyến đi thành công");
    }
}
