namespace DrivoApi.Application.Settings;

/// <summary>Cấu hình tùy chọn "Maps" cho các dịch vụ OpenStreetMap miễn phí (không cần API key).</summary>
public class MapsSettings
{
    public string UserAgent { get; set; } = "DrivoApp/1.0 (student project)";
    public string PhotonUrl { get; set; } = "https://photon.komoot.io";
    public string NominatimUrl { get; set; } = "https://nominatim.openstreetmap.org";
    public string OsrmUrl { get; set; } = "https://router.project-osrm.org";
}
