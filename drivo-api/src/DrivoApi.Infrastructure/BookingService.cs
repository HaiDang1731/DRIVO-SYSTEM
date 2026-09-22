using DrivoApi.Application.DTOs.Booking;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.Services;
using DrivoApi.Domain.Entities;
using DrivoApi.Domain.Enums;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure;

public class BookingService(DrivoDbContext db) : IBookingService
{
    private static double ToRadians(double degrees) => degrees * Math.PI / 180.0;

    private static decimal CalculateDistanceKm(decimal lat1, decimal lon1, decimal lat2, decimal lon2)
    {
        if (lat1 == 0 && lon1 == 0 && lat2 == 0 && lon2 == 0) return 5.0m;
        const double r = 6371.0;
        var dLat = ToRadians((double)(lat2 - lat1));
        var dLon = ToRadians((double)(lon2 - lon1));
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(ToRadians((double)lat1)) * Math.Cos(ToRadians((double)lat2)) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        var dist = (decimal)(r * c);
        return Math.Max(1.0m, Math.Round(dist, 1));
    }

    private async Task<PricingRule> GetApplicablePricingRuleAsync(VehicleType vehicleType)
    {
        var rule = await db.PricingRules
            .Where(p => p.VehicleType == vehicleType && p.IsActive)
            .OrderByDescending(p => p.EffectiveFrom)
            .FirstOrDefaultAsync();

        if (rule == null)
        {
            rule = await db.PricingRules.Where(p => p.IsActive).FirstOrDefaultAsync();
        }

        return rule ?? new PricingRule
        {
            Id = 0,
            VehicleType = VehicleType.Car,
            BaseFare = 150000m,
            PricePerKm = 16000m,
            PricePerMinute = 1000m,
            NightSurcharge = 30000m
        };
    }

    public async Task<BaseResponse<EstimateFareResponse>> EstimateFareAsync(EstimateFareRequest req)
    {
        var distKm = CalculateDistanceKm(req.PickupLatitude, req.PickupLongitude, req.DestinationLatitude, req.DestinationLongitude);
        var estMinutes = (int)Math.Max(10, Math.Round(distKm * 2.5m));

        var pricing = await GetApplicablePricingRuleAsync(req.VehicleType);

        var baseFare = pricing.BaseFare;
        var distanceFare = distKm > 2m ? (distKm - 2m) * pricing.PricePerKm : 0m;
        var timeFare = estMinutes * pricing.PricePerMinute;

        var now = DateTime.UtcNow.AddHours(7);
        var isNight = now.Hour >= 22 || now.Hour < 6;
        var nightSurcharge = isNight ? pricing.NightSurcharge : 0m;

        var total = Math.Round((baseFare + distanceFare + timeFare + nightSurcharge) / 1000m) * 1000m;

        var res = new EstimateFareResponse
        {
            EstimatedDistanceKm = distKm,
            EstimatedDurationMin = estMinutes,
            BaseFare = baseFare,
            DistanceFare = distanceFare,
            TimeFare = timeFare,
            NightSurcharge = nightSurcharge,
            TotalEstimatedFare = total,
            PricingRuleId = pricing.Id > 0 ? pricing.Id : null
        };

        return BaseResponse<EstimateFareResponse>.Ok(res);
    }

    public async Task<BaseResponse<BookingDetailResponse>> CreateBookingAsync(int userId, CreateBookingRequest req)
    {
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

        var estimate = await EstimateFareAsync(new EstimateFareRequest
        {
            PickupLatitude = req.PickupLatitude,
            PickupLongitude = req.PickupLongitude,
            DestinationLatitude = req.DestinationLatitude,
            DestinationLongitude = req.DestinationLongitude,
            VehicleType = vehicle.VehicleType,
            Transmission = vehicle.Transmission
        });

        var fare = estimate.Data!;
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
            BaseFare = fare.BaseFare,
            DistanceFare = fare.DistanceFare,
            TimeFare = fare.TimeFare,
            Surcharge = fare.NightSurcharge,
            Discount = 0,
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

        var list = bookings.Select(MapToDetailResponse).ToList();
        return BaseResponse<List<BookingDetailResponse>>.Ok(list);
    }

    private static BookingDetailResponse MapToDetailResponse(Booking b)
    {
        return new BookingDetailResponse
        {
            Id = b.Id,
            BookingCode = b.BookingCode,
            Status = b.Status.ToString(),
            PickupAddress = b.PickupAddress,
            PickupLatitude = b.PickupLatitude,
            PickupLongitude = b.PickupLongitude,
            DestinationAddress = b.DestinationAddress,
            DestinationLatitude = b.DestinationLatitude,
            DestinationLongitude = b.DestinationLongitude,
            EstimatedDistanceKm = b.EstimatedDistanceKm ?? 0,
            EstimatedDurationMin = b.EstimatedDurationMin ?? 0,
            BaseFare = b.BaseFare,
            DistanceFare = b.DistanceFare,
            Surcharge = b.Surcharge,
            EstimatedPrice = b.EstimatedPrice,
            FinalPrice = b.FinalPrice,
            CustomerNote = b.CustomerNote,
            CreatedAt = b.CreatedAt,
            Vehicle = new BookingVehicleSummaryDto
            {
                Id = b.CustomerVehicle.Id,
                Brand = b.CustomerVehicle.Brand,
                Model = b.CustomerVehicle.Model,
                LicensePlate = b.CustomerVehicle.LicensePlate,
                Transmission = b.CustomerVehicle.Transmission.ToString()
            },
            Driver = b.Driver != null ? new BookingDriverSummaryDto
            {
                Id = b.Driver.Id,
                FullName = b.Driver.User.FullName,
                Phone = b.Driver.User.Phone,
                AvatarUrl = b.Driver.User.AvatarUrl,
                Rating = b.Driver.RatingAverage
            } : null
        };
    }
    // ══════════════════════════════════════════════════════════
    //  DRIVER METHODS
    // ══════════════════════════════════════════════════════════

    public async Task<BaseResponse<bool>> ToggleDriverStatusAsync(int userId, bool isOnline)
    {
        var driver = await db.Drivers.FirstOrDefaultAsync(d => d.UserId == userId);
        if (driver == null)
            return BaseResponse<bool>.Fail("Không tìm thấy thông tin tài xế.");

        driver.DriverStatus = isOnline ? DriverStatus.Online : DriverStatus.Offline;
        driver.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return BaseResponse<bool>.Ok(true, isOnline ? "Bạn đang trực tuyến." : "Bạn đã ngoại tuyến.");
    }

    public async Task<BaseResponse<List<BookingDetailResponse>>> GetPendingBookingsAsync(int driverId)
    {
        // Lấy các cuốc đang tìm tài xế (chưa có driver nào nhận)
        var bookings = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .Include(b => b.Driver)
                .ThenInclude(d => d!.User)
            .Where(b => b.Status == BookingStatus.SearchingDriver && b.DriverId == null)
            .OrderBy(b => b.CreatedAt)
            .Take(10)
            .ToListAsync();

        return BaseResponse<List<BookingDetailResponse>>.Ok(bookings.Select(MapToDetailResponse).ToList());
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

        var booking = await db.Bookings
            .Include(b => b.CustomerVehicle)
            .FirstOrDefaultAsync(b => b.Id == bookingId && b.Status == BookingStatus.SearchingDriver && b.DriverId == null);

        if (booking == null)
            return BaseResponse<BookingDetailResponse>.Fail("Cuốc xe không còn khả dụng.");

        var oldStatus = booking.Status;
        booking.DriverId = driver.Id;
        booking.Status = BookingStatus.DriverAccepted;
        booking.UpdatedAt = DateTime.UtcNow;

        driver.DriverStatus = DriverStatus.Busy;
        driver.UpdatedAt = DateTime.UtcNow;

        db.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = booking.Id,
            OldStatus = DrivoDbContext.ToSnakeUpper(oldStatus.ToString()),
            NewStatus = DrivoDbContext.ToSnakeUpper(BookingStatus.DriverAccepted.ToString()),
            ChangedByUserId = userId,
            Reason = "Tài xế nhận cuốc",
            ChangedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync();
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

        var oldStatus = booking.Status;
        booking.Status = parsedStatus;
        booking.UpdatedAt = DateTime.UtcNow;

        if (parsedStatus == BookingStatus.Completed)
        {
            booking.FinalPrice = booking.EstimatedPrice;
            driver.TotalTrips += 1;
            driver.TotalEarnings += booking.EstimatedPrice;
            driver.DriverStatus = DriverStatus.Online;
            driver.UpdatedAt = DateTime.UtcNow;
            
            // Create Trip record
            db.Trips.Add(new Trip
            {
                BookingId = booking.Id,
                DriverId = driver.Id,
                StartTime = booking.UpdatedAt, // using this as proxy
                EndTime = DateTime.UtcNow,
                StartLatitude = booking.PickupLatitude,
                StartLongitude = booking.PickupLongitude,
                EndLatitude = booking.DestinationLatitude,
                EndLongitude = booking.DestinationLongitude,
                ActualDistanceKm = booking.EstimatedDistanceKm,
                ActualDurationMin = booking.EstimatedDurationMin,
                Status = "COMPLETED",
                CreatedAt = DateTime.UtcNow
            });
        }

        db.BookingStatusHistories.Add(new BookingStatusHistory
        {
            BookingId = booking.Id,
            OldStatus = DrivoDbContext.ToSnakeUpper(oldStatus.ToString()),
            NewStatus = DrivoDbContext.ToSnakeUpper(parsedStatus.ToString()),
            ChangedByUserId = userId,
            Reason = "Cập nhật trạng thái",
            ChangedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync();
        return BaseResponse<BookingDetailResponse>.Ok(MapToDetailResponse(booking));
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

        return BaseResponse<List<BookingDetailResponse>>.Ok(bookings.Select(MapToDetailResponse).ToList());
    }


    public async Task<BaseResponse<bool>> RateBookingAsync(long bookingId, int customerId, byte score, string comment)
    {
        var booking = await db.Bookings
            .Include(b => b.Trip)
            .FirstOrDefaultAsync(b => b.Id == bookingId && b.CustomerId == customerId);
            
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
            CustomerId = customerId,
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
}
