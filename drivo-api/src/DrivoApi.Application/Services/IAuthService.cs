using DrivoApi.Application.DTOs.Auth;
using DrivoApi.Application.DTOs.Common;

namespace DrivoApi.Application.Services;

public interface IAuthService
{
    Task<BaseResponse<AuthResponse>> RegisterAsync(RegisterRequest request);
    Task<BaseResponse<AuthResponse>> LoginAsync(LoginRequest request);
    Task<BaseResponse<AuthResponse>> RefreshTokenAsync(string refreshToken);
    Task<BaseResponse<bool>> LogoutAsync(string refreshToken);

    Task<BaseResponse<UserInfo>> UpdateProfileAsync(int userId, UpdateProfileRequest request);
    Task<BaseResponse<bool>> ChangePasswordAsync(int userId, ChangePasswordRequest request);
}

