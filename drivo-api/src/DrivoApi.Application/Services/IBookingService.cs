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
    Task<BaseResponse<List<BookingDetailResponse>>> GetCustomerBookingsAsync(int userId, int page, int pageSize);
}
