using DrivoApi.Application.DTOs.Booking;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Driver;
using DrivoApi.Application.DTOs.Tracking;

namespace DrivoApi.Application.Services;

public interface IBookingService
{
    Task<BaseResponse<EstimateFareResponse>> EstimateFareAsync(EstimateFareRequest request);
    Task<BaseResponse<BookingDetailResponse>> CreateBookingAsync(int userId, CreateBookingRequest request);
    Task<BaseResponse<BookingDetailResponse?>> GetActiveBookingAsync(int userId);
    Task<BaseResponse<BookingDetailResponse>> GetBookingByIdAsync(long bookingId, int userId);
    Task<BaseResponse<bool>> CancelBookingAsync(long bookingId, int userId, CancelBookingRequest request);
    Task<BaseResponse<bool>> CancelBookingByDriverAsync(long bookingId, int userId, CancelBookingRequest request);
    Task<BaseResponse<List<BookingDetailResponse>>> GetCustomerBookingsAsync(int userId, int page, int pageSize);
    Task<BaseResponse<List<VoucherResponse>>> GetAvailableVouchersAsync(int userId);
    Task<BaseResponse<CheckVoucherResponse>> CheckVoucherAsync(int userId, CheckVoucherRequest request);

    // Driver methods
    Task<BaseResponse<bool>> ToggleDriverStatusAsync(int userId, bool isOnline, decimal? latitude = null, decimal? longitude = null);
    Task<BaseResponse<List<BookingDetailResponse>>> GetPendingBookingsAsync(int userId);
    Task<BaseResponse<BookingDetailResponse>> AcceptBookingAsync(long bookingId, int userId);
    Task<BaseResponse<bool>> RejectBookingAsync(long bookingId, int userId);
    Task<BaseResponse<BookingDetailResponse>> UpdateBookingStatusAsync(long bookingId, int userId, string newStatus);
    Task<BaseResponse<BookingDetailResponse?>> GetDriverActiveBookingAsync(int userId);
    Task<BaseResponse<List<BookingDetailResponse>>> GetDriverBookingHistoryAsync(int userId, int page, int pageSize);
    Task<BaseResponse<DriverEarningsResponse>> GetDriverEarningsAsync(int userId, string period, DateTime? date);
    Task<BaseResponse<object>> UpdateDriverLocationAsync(int userId, UpdateDriverLocationRequest request);
    Task<BaseResponse<bool>> RateBookingAsync(long bookingId, int customerId, byte score, string comment);

    // Admin
    Task<BaseResponse<AdminBookingDetailResponse>> GetAdminBookingDetailAsync(long bookingId);
    Task<BaseResponse<bool>> CancelBookingByAdminAsync(long bookingId, int adminUserId, string? reason);
}
