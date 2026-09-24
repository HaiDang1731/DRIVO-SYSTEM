namespace DrivoApi.Domain.Entities;

public class Voucher
{
    public int Id { get; set; }
    public string Code { get; set; } = null!;
    public string Title { get; set; } = null!;
    public string? Description { get; set; }
    public string DiscountType { get; set; } = "PERCENT"; // PERCENT | FIXED
    public decimal DiscountValue { get; set; }
    public decimal? MaxDiscountAmount { get; set; }
    public decimal MinOrderAmount { get; set; } = 0;
    public int UsageLimit { get; set; } = 100;
    public int UsedCount { get; set; } = 0;
    public bool IsActive { get; set; } = true;
    public DateTime StartDate { get; set; } = DateTime.UtcNow;
    public DateTime EndDate { get; set; } = DateTime.UtcNow.AddMonths(1);
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
