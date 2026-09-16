using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Customer;

namespace DrivoApi.Application.Services;

public interface ICustomerVehicleService
{
    Task<BaseResponse<List<CustomerVehicleResponse>>> GetVehiclesAsync(int userId);
    Task<BaseResponse<CustomerVehicleResponse>> AddVehicleAsync(int userId, CreateCustomerVehicleRequest request);
    Task<BaseResponse<bool>> DeleteVehicleAsync(int userId, int vehicleId);
}
