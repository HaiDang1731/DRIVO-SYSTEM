using DrivoApi.Application.DTOs.Booking;
using DrivoApi.Application.DTOs.Common;

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

    // Driver methods
    Task<BaseResponse<bool>> ToggleDriverStatusAsync(int userId, bool isOnline);
    Task<BaseResponse<List<BookingDetailResponse>>> GetPendingBookingsAsync(int driverId);
    Task<BaseResponse<BookingDetailResponse>> AcceptBookingAsync(long bookingId, int userId);
    Task<BaseResponse<BookingDetailResponse>> UpdateBookingStatusAsync(long bookingId, int userId, string newStatus);
    Task<BaseResponse<BookingDetailResponse?>> GetDriverActiveBookingAsync(int userId);
    Task<BaseResponse<List<BookingDetailResponse>>> GetDriverBookingHistoryAsync(int userId, int page, int pageSize);
    Task<BaseResponse<bool>> RateBookingAsync(long bookingId, int customerId, byte score, string comment);
}
