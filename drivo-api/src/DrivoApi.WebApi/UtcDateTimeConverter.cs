using System.Text.Json;
using System.Text.Json.Serialization;

namespace DrivoApi.WebApi;

/// <summary>
/// Mọi DateTime trong DB đều là UTC nhưng EF đọc ra với Kind = Unspecified, nên JSON mặc định thiếu 'Z'
/// và trình duyệt hiểu nhầm là giờ địa phương (lệch 7 tiếng). Converter này luôn ghi kèm 'Z'.
/// </summary>
public sealed class UtcDateTimeConverter : JsonConverter<DateTime>
{
    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.GetDateTime();

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options)
    {
        var utc = value.Kind switch
        {
            DateTimeKind.Utc => value,
            DateTimeKind.Local => value.ToUniversalTime(),
            _ => DateTime.SpecifyKind(value, DateTimeKind.Utc),
        };
        writer.WriteStringValue(utc.ToString("yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'"));
    }
}
