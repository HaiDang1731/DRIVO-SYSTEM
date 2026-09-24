namespace DrivoApi.Application.Common;

public static class GeoUtils
{
    /// <summary>Hệ số quy đổi đường chim bay → đường thực tế khi không gọi được dịch vụ định tuyến.</summary>
    public const double RoadFactor = 1.3;

    /// <summary>Tốc độ xe điện gấp của tài xế (km/h) để ước tính ETA đến điểm đón.</summary>
    public const double ScooterSpeedKmh = 15.0;

    private static double ToRadians(double degrees) => degrees * Math.PI / 180.0;

    public static double HaversineKm(double lat1, double lon1, double lat2, double lon2)
    {
        const double r = 6371.0;
        var dLat = ToRadians(lat2 - lat1);
        var dLon = ToRadians(lon2 - lon1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(ToRadians(lat1)) * Math.Cos(ToRadians(lat2)) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return r * c;
    }

    public static double HaversineKm(decimal lat1, decimal lon1, decimal lat2, decimal lon2) =>
        HaversineKm((double)lat1, (double)lon1, (double)lat2, (double)lon2);

    /// <summary>Tọa độ (0,0) hoặc ngoài phạm vi → coi như không hợp lệ.</summary>
    public static bool IsValid(double lat, double lng) =>
        !(lat == 0 && lng == 0) && lat is >= -90 and <= 90 && lng is >= -180 and <= 180;

    public static bool IsValid(decimal lat, decimal lng) => IsValid((double)lat, (double)lng);

    /// <summary>Làm tròn đến 1.000đ.</summary>
    public static decimal Round1000(decimal amount) =>
        Math.Round(amount / 1000m, MidpointRounding.AwayFromZero) * 1000m;
}
