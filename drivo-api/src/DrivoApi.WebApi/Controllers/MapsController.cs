using DrivoApi.Application.Common;
using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Maps;
using DrivoApi.Application.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DrivoApi.WebApi.Controllers;

/// <summary>
/// Proxy bản đồ OpenStreetMap (Photon / Nominatim / OSRM). Khi dịch vụ lỗi:
/// route → ước tính haversine, autocomplete → [], place/reverse-geocode → 404.
/// </summary>
[ApiController]
[Route("api/v1/maps")]
[Authorize]
public class MapsController(IMapsService maps) : ControllerBase
{
    [HttpGet("status")]
    public IActionResult Status() =>
        Ok(BaseResponse<MapsStatusDto>.Ok(new MapsStatusDto { Provider = maps.Provider }));

    [HttpGet("autocomplete")]
    public async Task<IActionResult> Autocomplete([FromQuery] string? input, [FromQuery] double? lat,
        [FromQuery] double? lng, [FromQuery] string? sessionToken, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(input))
            return Ok(BaseResponse<List<PlaceSuggestionDto>>.Ok([]));

        var list = await maps.AutocompleteAsync(input, lat, lng, sessionToken, ct);
        return Ok(BaseResponse<List<PlaceSuggestionDto>>.Ok(list));
    }

    [HttpGet("place/{placeId}")]
    public async Task<IActionResult> PlaceDetails(string placeId, [FromQuery] string? sessionToken, CancellationToken ct)
    {
        var place = await maps.GetPlaceDetailsAsync(placeId, sessionToken, ct);
        return place == null
            ? NotFound(BaseResponse<PlaceDetailsDto>.Fail("Không tìm thấy địa điểm."))
            : Ok(BaseResponse<PlaceDetailsDto>.Ok(place));
    }

    [HttpGet("reverse-geocode")]
    public async Task<IActionResult> ReverseGeocode([FromQuery] double lat, [FromQuery] double lng, CancellationToken ct)
    {
        if (!GeoUtils.IsValid(lat, lng))
            return BadRequest(BaseResponse<ReverseGeocodeDto>.Fail("Tọa độ không hợp lệ."));

        var result = await maps.ReverseGeocodeAsync(lat, lng, ct);
        return result == null
            ? NotFound(BaseResponse<ReverseGeocodeDto>.Fail("Không xác định được địa chỉ."))
            : Ok(BaseResponse<ReverseGeocodeDto>.Ok(result));
    }

    [HttpPost("route")]
    public async Task<IActionResult> Route([FromBody] RouteRequest req, CancellationToken ct)
    {
        if (!GeoUtils.IsValid(req.OriginLatitude, req.OriginLongitude) ||
            !GeoUtils.IsValid(req.DestinationLatitude, req.DestinationLongitude))
            return BadRequest(BaseResponse<RouteResult>.Fail("Tọa độ không hợp lệ."));

        var route = await maps.GetRouteAsync(req.OriginLatitude, req.OriginLongitude,
            req.DestinationLatitude, req.DestinationLongitude, req.Mode ?? "DRIVE", ct);
        return Ok(BaseResponse<RouteResult>.Ok(route));
    }
}
