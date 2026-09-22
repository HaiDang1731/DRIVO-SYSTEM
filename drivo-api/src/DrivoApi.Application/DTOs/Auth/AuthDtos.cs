namespace DrivoApi.Application.DTOs.Auth;

public class RegisterRequest
{
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public string? Email { get; set; }
    public string Password { get; set; } = null!;

    /// <summary>CUSTOMER hoặc DRIVER</summary>
    public string Role { get; set; } = "CUSTOMER";
}

public class LoginRequest
{
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string Password { get; set; } = null!;
}

public class RefreshTokenRequest
{
    public string RefreshToken { get; set; } = null!;
}

public class AuthResponse
{
    public string AccessToken { get; set; } = null!;
    public string RefreshToken { get; set; } = null!;
    public DateTime AccessTokenExpiresAt { get; set; }
    public UserInfo User { get; set; } = null!;
}

public class UserInfo
{
    public int Id { get; set; }
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public string? Email { get; set; }
    public string? AvatarUrl { get; set; }
    public List<string> Roles { get; set; } = [];
}

public class UpdateProfileRequest
{
    public string FullName { get; set; } = null!;
    public string? Email { get; set; }
}

public class ChangePasswordRequest
{
    public string CurrentPassword { get; set; } = null!;
    public string NewPassword { get; set; } = null!;
}
