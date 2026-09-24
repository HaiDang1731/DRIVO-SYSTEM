using System.Globalization;
using System.Text.Json;
using DrivoApi.Application.Common;
using DrivoApi.Application.DTOs.Maps;
using DrivoApi.Application.Services;
using DrivoApi.Application.Settings;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace DrivoApi.Infrastructure;

/// <summary>
/// Bản đồ miễn phí OpenStreetMap: Photon (autocomplete), Nominatim (reverse + lookup), OSRM (routing).
/// Mọi lỗi đều được log warning và trả về giá trị dự phòng, không ném exception.
/// </summary>
public class OsmMapsService(HttpClient http, IOptions<MapsSettings> options, IMemoryCache cache,
    ILogger<OsmMapsService> logger) : IMapsService
{
    private const string VietnamBbox = "102.1,8.4,109.5,23.4";
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan ReverseCacheTtl = TimeSpan.FromHours(1);

    // Nominatim: tối đa 1 request/giây cho toàn bộ tiến trình
    private static readonly SemaphoreSlim NominatimGate = new(1, 1);
    private static DateTime _lastNominatimCallUtc = DateTime.MinValue;

    private readonly MapsSettings _cfg = options.Value;

    public string Provider => "osm";

    // ── Route (OSRM) ─────────────────────────────────────────

    public async Task<RouteResult> GetRouteAsync(double originLat, double originLng, double destLat, double destLng,
        string mode = "DRIVE", CancellationToken ct = default)
    {
        // Server OSRM công khai chỉ có profile "driving" → dùng chung cho DRIVE và TWO_WHEELER.
        if (GeoUtils.IsValid(originLat, originLng) && GeoUtils.IsValid(destLat, destLng))
        {
            try
            {
                var coords = string.Create(CultureInfo.InvariantCulture,
                    $"{originLng},{originLat};{destLng},{destLat}");
                var url = $"{Base(_cfg.OsrmUrl)}/route/v1/driving/{coords}?overview=full&geometries=polyline";

                using var doc = await GetJsonAsync(url, ct);
                if (doc != null)
                {
                    var root = doc.RootElement;
                    var code = root.TryGetProperty("code", out var c) ? c.GetString() : null;
                    if (code == "Ok" && root.TryGetProperty("routes", out var routes) &&
                        routes.ValueKind == JsonValueKind.Array && routes.GetArrayLength() > 0)
                    {
                        var r = routes[0];
                        var meters = r.TryGetProperty("distance", out var d) ? d.GetDouble() : 0;
                        var seconds = r.TryGetProperty("duration", out var du) ? du.GetDouble() : 0;
                        var polyline = r.TryGetProperty("geometry", out var g) && g.ValueKind == JsonValueKind.String
                            ? g.GetString() : null;

                        return new RouteResult
                        {
                            DistanceKm = Math.Round((decimal)(meters / 1000.0), 1),
                            DurationMin = Math.Max(1, (int)Math.Ceiling(seconds / 60.0)),
                            Polyline = polyline,
                            FromRouter = true
                        };
                    }
                    logger.LogWarning("OSRM không trả về tuyến đường (code={Code}, mode={Mode}).", code, mode);
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
            {
                logger.LogWarning(ex, "Gọi OSRM thất bại, dùng ước tính haversine.");
            }
        }

        return FallbackRoute(originLat, originLng, destLat, destLng);
    }

    /// <summary>Ước tính: haversine × 1.3 (tối thiểu 1 km), thời gian = max(5, km × 2.5) phút.</summary>
    public static RouteResult FallbackRoute(double originLat, double originLng, double destLat, double destLng)
    {
        var km = GeoUtils.HaversineKm(originLat, originLng, destLat, destLng) * GeoUtils.RoadFactor;
        var distKm = Math.Max(1.0m, Math.Round((decimal)km, 1));
        return new RouteResult
        {
            DistanceKm = distKm,
            DurationMin = (int)Math.Max(5, Math.Ceiling(distKm * 2.5m)),
            Polyline = null,
            FromRouter = false
        };
    }

    // ── Autocomplete (Photon) ────────────────────────────────

    public async Task<List<PlaceSuggestionDto>> AutocompleteAsync(string input, double? lat, double? lng,
        string? sessionToken, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(input)) return [];

        try
        {
            var url = $"{Base(_cfg.PhotonUrl)}/api/?q={Uri.EscapeDataString(input.Trim())}&limit=8&lang=default&bbox={VietnamBbox}";
            if (lat.HasValue && lng.HasValue && GeoUtils.IsValid(lat.Value, lng.Value))
                url += string.Create(CultureInfo.InvariantCulture, $"&lat={lat.Value}&lon={lng.Value}");

            using var doc = await GetJsonAsync(url, ct);
            if (doc == null) return [];

            var list = new List<PlaceSuggestionDto>();
            if (!doc.RootElement.TryGetProperty("features", out var features) || features.ValueKind != JsonValueKind.Array)
                return list;

            var seen = new HashSet<string>();
            foreach (var f in features.EnumerateArray())
            {
                if (!f.TryGetProperty("geometry", out var geo) || !geo.TryGetProperty("coordinates", out var coords) ||
                    coords.ValueKind != JsonValueKind.Array || coords.GetArrayLength() < 2) continue;
                if (!f.TryGetProperty("properties", out var p)) continue;

                var fLng = coords[0].GetDouble();
                var fLat = coords[1].GetDouble();

                if (!FormatPhoton(p, out var main, out var secondary)) continue;

                var osmType = Str(p, "osm_type") ?? "";
                var osmId = p.TryGetProperty("osm_id", out var idEl) ? idEl.ToString() : "";
                var placeId = string.IsNullOrEmpty(osmId)
                    ? string.Create(CultureInfo.InvariantCulture, $"osm:{fLat:F6},{fLng:F6}")
                    : $"osm:{osmType}{osmId}";
                if (!seen.Add(placeId)) continue;

                list.Add(new PlaceSuggestionDto
                {
                    PlaceId = placeId,
                    MainText = main,
                    SecondaryText = secondary,
                    Latitude = fLat,
                    Longitude = fLng
                });
            }
            return list;
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
        {
            logger.LogWarning(ex, "Gọi Photon autocomplete thất bại.");
            return [];
        }
    }

    // ── Place details (Nominatim lookup) ─────────────────────

    public async Task<PlaceDetailsDto?> GetPlaceDetailsAsync(string placeId, string? sessionToken, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(placeId)) return null;
        var id = placeId.Trim();
        if (id.StartsWith("osm:", StringComparison.OrdinalIgnoreCase)) id = id[4..];

        // Id dạng "osm:{lat},{lng}" → trả thẳng tọa độ
        var ll = id.Split(',');
        if (ll.Length == 2 &&
            double.TryParse(ll[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var pLat) &&
            double.TryParse(ll[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var pLng) &&
            GeoUtils.IsValid(pLat, pLng))
        {
            var rev = await ReverseGeocodeAsync(pLat, pLng, ct);
            return new PlaceDetailsDto { PlaceId = placeId, Address = rev?.Address ?? id, Latitude = pLat, Longitude = pLng };
        }

        if (id.Length < 2 || !"NWR".Contains(char.ToUpperInvariant(id[0])) || !id[1..].All(char.IsDigit)) return null;
        id = char.ToUpperInvariant(id[0]) + id[1..];

        try
        {
            var url = $"{Base(_cfg.NominatimUrl)}/lookup?osm_ids={id}&format=jsonv2&accept-language=vi";
            using var doc = await NominatimGetAsync(url, ct);
            if (doc == null || doc.RootElement.ValueKind != JsonValueKind.Array || doc.RootElement.GetArrayLength() == 0)
                return null;

            var r = doc.RootElement[0];
            if (!TryLatLon(r, out var la, out var lo)) return null;
            var address = Str(r, "display_name");
            var name = Str(r, "name");
            if (!string.IsNullOrWhiteSpace(name) &&
                (address == null || !address.Contains(name, StringComparison.OrdinalIgnoreCase)))
                address = address == null ? name : $"{name}, {address}";

            return new PlaceDetailsDto { PlaceId = placeId, Address = address ?? placeId, Latitude = la, Longitude = lo };
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
        {
            logger.LogWarning(ex, "Gọi Nominatim lookup thất bại.");
            return null;
        }
    }

    // ── Reverse geocode (Nominatim) ──────────────────────────

    public async Task<ReverseGeocodeDto?> ReverseGeocodeAsync(double lat, double lng, CancellationToken ct = default)
    {
        if (!GeoUtils.IsValid(lat, lng)) return null;

        var key = string.Create(CultureInfo.InvariantCulture, $"osm-rev:{Math.Round(lat, 5):F5},{Math.Round(lng, 5):F5}");
        if (cache.TryGetValue(key, out string? cached) && cached != null)
            return new ReverseGeocodeDto { Address = cached, Latitude = lat, Longitude = lng };

        // Photon là nguồn chính, Nominatim chỉ là dự phòng
        var photon = await PhotonReverseAsync(lat, lng, ct);
        if (!string.IsNullOrWhiteSpace(photon))
        {
            cache.Set(key, photon, ReverseCacheTtl);
            return new ReverseGeocodeDto { Address = photon, Latitude = lat, Longitude = lng };
        }

        try
        {
            var q = string.Create(CultureInfo.InvariantCulture, $"lat={lat}&lon={lng}");
            var url = $"{Base(_cfg.NominatimUrl)}/reverse?format=jsonv2&{q}&accept-language=vi&zoom=18";
            using var doc = await NominatimGetAsync(url, ct);
            if (doc == null || doc.RootElement.ValueKind != JsonValueKind.Object) return null;

            var address = Str(doc.RootElement, "display_name");
            if (string.IsNullOrWhiteSpace(address)) return null;

            cache.Set(key, address, ReverseCacheTtl);
            return new ReverseGeocodeDto { Address = address, Latitude = lat, Longitude = lng };
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
        {
            logger.LogWarning(ex, "Gọi Nominatim reverse thất bại.");
            return null;
        }
    }

    // ── Helpers ──────────────────────────────────────────────

    /// <summary>Nominatim: tuần tự hóa, cách nhau ≥ 1 giây.</summary>
    private async Task<JsonDocument?> NominatimGetAsync(string url, CancellationToken ct)
    {
        await NominatimGate.WaitAsync(ct);
        try
        {
            var wait = _lastNominatimCallUtc.AddSeconds(1) - DateTime.UtcNow;
            if (wait > TimeSpan.Zero) await Task.Delay(wait, ct);
            try { return await GetJsonAsync(url, ct); }
            finally { _lastNominatimCallUtc = DateTime.UtcNow; }
        }
        finally
        {
            NominatimGate.Release();
        }
    }

    /// <summary>GET JSON với User-Agent và timeout 5 s; trả null nếu HTTP lỗi.</summary>
    private async Task<JsonDocument?> GetJsonAsync(string url, CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(RequestTimeout);

        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.TryAddWithoutValidation("User-Agent", _cfg.UserAgent);
        req.Headers.TryAddWithoutValidation("Accept-Language", "vi");

        using var res = await http.SendAsync(req, cts.Token);
        var json = await res.Content.ReadAsStringAsync(cts.Token);
        if (!res.IsSuccessStatusCode)
        {
            logger.LogWarning("Maps request {Url} lỗi {Status}: {Body}", url, (int)res.StatusCode,
                json.Length <= 300 ? json : json[..300] + "...");
            return null;
        }
        return JsonDocument.Parse(json);
    }

    /// <summary>mainText = tên hoặc "số nhà đường"; secondaryText = đường/quận/thành phố/tỉnh (bỏ rỗng, trùng).</summary>
    private static bool FormatPhoton(JsonElement p, out string main, out string? secondary)
    {
        var name = Str(p, "name");
        var streetLine = JoinNonEmpty(" ", Str(p, "housenumber"), Str(p, "street"));
        var m = name ?? streetLine;
        if (string.IsNullOrWhiteSpace(m)) m = Str(p, "city") ?? Str(p, "state");
        main = m ?? "";
        secondary = null;
        if (string.IsNullOrWhiteSpace(m)) return false;

        var parts = new List<string>();
        void Add(string? s)
        {
            if (string.IsNullOrWhiteSpace(s)) return;
            s = s.Trim();
            if (string.Equals(s, m, StringComparison.OrdinalIgnoreCase)) return;
            if (parts.Any(x => string.Equals(x, s, StringComparison.OrdinalIgnoreCase))) return;
            parts.Add(s);
        }
        Add(name != null ? streetLine : null);
        Add(Str(p, "district"));
        Add(Str(p, "city") ?? Str(p, "county"));
        Add(Str(p, "state"));
        secondary = parts.Count > 0 ? string.Join(", ", parts) : Str(p, "country");
        return true;
    }

    private async Task<string?> PhotonReverseAsync(double lat, double lng, CancellationToken ct)
    {
        try
        {
            var q = string.Create(CultureInfo.InvariantCulture, $"lat={lat}&lon={lng}");
            using var doc = await GetJsonAsync($"{Base(_cfg.PhotonUrl)}/reverse?{q}&limit=1&lang=default", ct);
            if (doc == null || !doc.RootElement.TryGetProperty("features", out var fs) ||
                fs.ValueKind != JsonValueKind.Array || fs.GetArrayLength() == 0 ||
                !fs[0].TryGetProperty("properties", out var p)) return null;
            if (!FormatPhoton(p, out var main, out var secondary)) return null;
            return string.IsNullOrWhiteSpace(secondary) ? main : $"{main}, {secondary}";
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !ct.IsCancellationRequested)
        {
            logger.LogWarning(ex, "Gọi Photon reverse thất bại, thử Nominatim.");
            return null;
        }
    }

    private static string Base(string url) => url.TrimEnd('/');

    private static string? Str(JsonElement el, string name) =>
        el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(v.GetString())
            ? v.GetString()!.Trim() : null;

    private static string? JoinNonEmpty(string sep, params string?[] items)
    {
        var s = string.Join(sep, items.Where(x => !string.IsNullOrWhiteSpace(x)));
        return s.Length == 0 ? null : s;
    }

    private static bool TryLatLon(JsonElement el, out double lat, out double lon)
    {
        lat = lon = 0;
        return double.TryParse(Str(el, "lat"), NumberStyles.Float, CultureInfo.InvariantCulture, out lat) &&
               double.TryParse(Str(el, "lon"), NumberStyles.Float, CultureInfo.InvariantCulture, out lon);
    }
}
