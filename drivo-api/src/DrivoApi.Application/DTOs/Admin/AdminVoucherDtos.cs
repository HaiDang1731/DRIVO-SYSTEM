namespace DrivoApi.Application.DTOs.Admin;

/// <summary>Body cho POST/PUT /admin/vouchers. Ngày gửi dạng ISO có múi giờ (client đổi sang UTC).</summary>
public class VoucherUpsertRequest
{
    public string Code { get; set; } = null!;
    public string Title { get; set; } = null!;
    public string? Description { get; set; }
    /// <summary>PERCENT | FIXED</summary>
    public string DiscountType { get; set; } = "PERCENT";
    public decimal DiscountValue { get; set; }
    public decimal? MaxDiscountAmount { get; set; }
    public decimal MinOrderAmount { get; set; }
    public int UsageLimit { get; set; } = 100;
    public bool IsActive { get; set; } = true;
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
}
