using DrivoApi.Domain.Enums;

namespace DrivoApi.Application.DTOs.Admin;

/// <summary>
/// Body cho POST/PUT /admin/pricing. Các trường nullable: khi PUT mà bỏ trống → giữ giá trị cũ;
/// khi POST mà bỏ trống → dùng mặc định.
/// </summary>
public class PricingRuleUpsertRequest
{
    public VehicleType? VehicleType { get; set; }
    public decimal BaseFare { get; set; }
    public decimal PricePerKm { get; set; }
    public decimal PricePerMinute { get; set; }
    public decimal NightSurcharge { get; set; }
    public decimal WaitingPricePerMin { get; set; }
    public decimal? FreePickupKm { get; set; }
    public decimal? PickupFeePerKm { get; set; }
    public int? FreeWaitingMin { get; set; }
    public decimal? OverDistanceTolerancePercent { get; set; }
    /// <summary>% nền tảng DRIVO giữ lại trên giá cuối cùng của chuyến, riêng theo từng loại xe.</summary>
    public decimal? CommissionPercent { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime? EffectiveFrom { get; set; }
    public DateTime? EffectiveTo { get; set; }
}
