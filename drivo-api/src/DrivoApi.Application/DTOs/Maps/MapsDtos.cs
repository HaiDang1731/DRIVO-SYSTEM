using System.Text.Json.Serialization;

namespace DrivoApi.Application.DTOs.Maps;

public class RouteRequest
{
    public double OriginLatitude { get; set; }
    public double OriginLongitude { get; set; }
    public double DestinationLatitude { get; set; }
    public double DestinationLongitude { get; set; }
    /// <summary>"DRIVE" (mặc định) hoặc "TWO_WHEELER"</summary>
    public string? Mode { get; set; }
}

public class RouteResult
{
    public decimal DistanceKm { get; set; }
    public int DurationMin { get; set; }
    public string? Polyline { get; set; }

    /// <summary>true nếu lấy từ OSRM, false nếu là ước tính haversine.</summary>
    [JsonIgnore]
    public bool FromRouter { get; set; }
}

public class PlaceSuggestionDto
{
    public string PlaceId { get; set; } = null!;
    public string MainText { get; set; } = null!;
    public string? SecondaryText { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
}

public class PlaceDetailsDto
{
    public string PlaceId { get; set; } = null!;
    public string Address { get; set; } = null!;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
}

public class ReverseGeocodeDto
{
    public string Address { get; set; } = null!;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
}

public class MapsStatusDto
{
    public string Provider { get; set; } = "osm";
}
