namespace DrivoApi.Application.Common;

/// <summary>Giờ Việt Nam (UTC+7, không có giờ mùa hè). DB lưu UTC; ngày/tuần/tháng báo cáo tính theo giờ VN.</summary>
public static class VnClock
{
    public static readonly TimeSpan Offset = TimeSpan.FromHours(7);

    public static DateTime Today => (DateTime.UtcNow + Offset).Date;

    /// <summary>Nửa đêm (giờ VN) của một ngày, đổi ra UTC.</summary>
    public static DateTime StartOfDayUtc(DateTime localDate) => localDate.Date - Offset;

    public static DateTime ToLocal(DateTime utc) => utc + Offset;
}
