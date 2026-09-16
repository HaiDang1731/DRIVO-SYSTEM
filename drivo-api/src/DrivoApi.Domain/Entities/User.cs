using DrivoApi.Domain.Enums;

namespace DrivoApi.Domain.Entities;

public class User
{
    public int Id { get; set; }
    public string FullName { get; set; } = null!;
    public string Phone { get; set; } = null!;
    public string? Email { get; set; }
    public string PasswordHash { get; set; } = null!;
    public UserStatus Status { get; set; } = UserStatus.Active;
    public string? AvatarUrl { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public bool IsDeleted { get; set; }

    // Navigation
    public Customer? Customer { get; set; }
    public Driver? Driver { get; set; }
    public ICollection<UserRole> UserRoles { get; set; } = [];
    public ICollection<RefreshToken> RefreshTokens { get; set; } = [];
    public ICollection<Notification> Notifications { get; set; } = [];
}
