using DrivoApi.Application.DTOs.Maps;

namespace DrivoApi.Application.Services;

/// <summary>
/// Proxy bản đồ miễn phí OpenStreetMap (Photon, Nominatim, OSRM).
/// Không bao giờ ném lỗi ra ngoài: route → ước tính haversine×1.3,
/// autocomplete → rỗng, place/reverse → null.
/// </summary>
public interface IMapsService
{
    /// <summary>Tên nhà cung cấp bản đồ, hiện là "osm".</summary>
    string Provider { get; }

    Task<RouteResult> GetRouteAsync(double originLat, double originLng, double destLat, double destLng,
        string mode = "DRIVE", CancellationToken ct = default);

    Task<List<PlaceSuggestionDto>> AutocompleteAsync(string input, double? lat, double? lng, string? sessionToken,
        CancellationToken ct = default);

    Task<PlaceDetailsDto?> GetPlaceDetailsAsync(string placeId, string? sessionToken, CancellationToken ct = default);

    Task<ReverseGeocodeDto?> ReverseGeocodeAsync(double lat, double lng, CancellationToken ct = default);
}
