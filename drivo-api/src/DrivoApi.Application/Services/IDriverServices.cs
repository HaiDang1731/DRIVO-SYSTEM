using DrivoApi.Application.DTOs.Admin;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Driver;

namespace DrivoApi.Application.Services;

// ── Admin quản lý tài xế ───────────────────────────────────
public interface IAdminDriverService
{
    /// <summary>Admin tạo tài khoản tài xế, password mặc định = SĐT</summary>
    Task<BaseResponse<DriverDetailResponse>> CreateDriverAsync(CreateDriverRequest request, int adminUserId);

    /// <summary>Admin duyệt / từ chối hồ sơ tài xế</summary>
    Task<BaseResponse<DriverDetailResponse>> VerifyDriverAsync(int driverId, VerifyDriverRequest request, int adminUserId);

    /// <summary>Admin thêm giấy tờ cho tài xế (CCCD, GPLX, bảo hiểm...)</summary>
    Task<BaseResponse<DriverDocumentDto>> AddDocumentAsync(int driverId, AddDriverDocumentRequest request);

    /// <summary>Admin xem chi tiết tài xế</summary>
    Task<BaseResponse<DriverDetailResponse>> GetDriverByIdAsync(int driverId);

    /// <summary>Admin lấy danh sách tài xế (có filter theo status)</summary>
    Task<BaseResponse<List<DriverListResponse>>> GetDriversAsync(string? verificationStatus, int page, int pageSize);

    /// <summary>Admin khóa / mở khóa tài khoản tài xế</summary>
    Task<BaseResponse<bool>> SetDriverAccountStatusAsync(int driverId, string status, int adminUserId);
}

// ── Tài xế tự quản lý ─────────────────────────────────────
public interface IDriverProfileService
{
    /// <summary>Tài xế xem profile của mình</summary>
    Task<BaseResponse<DriverProfileResponse>> GetMyProfileAsync(int userId);

    /// <summary>Tài xế cập nhật thông tin cá nhân</summary>
    Task<BaseResponse<DriverProfileResponse>> UpdateProfileAsync(int userId, UpdateDriverProfileRequest request);

    /// <summary>Tài xế đổi mật khẩu</summary>
    Task<BaseResponse<bool>> ChangePasswordAsync(int userId, ChangePasswordRequest request);
}
