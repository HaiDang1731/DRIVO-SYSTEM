import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

/// Tiện ích địa lý dùng chung: giải mã polyline (OSRM, precision 5), khoảng cách haversine, khung bao.
class GeoUtils {
  /// Giải mã Encoded Polyline (precision 5).
  static List<LatLng> decodePolyline(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    final len = encoded.length;
    try {
      while (index < len) {
        int shift = 0, result = 0, b;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20 && index < len);
        // Không dùng `~`: trên Flutter web phép bit trả về số không âm 32-bit -> toạ độ sai (kinh độ ~43000).
        lat += (result & 1) != 0 ? -(result >> 1) - 1 : (result >> 1);

        shift = 0;
        result = 0;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20 && index < len);
        lng += (result & 1) != 0 ? -(result >> 1) - 1 : (result >> 1);

        final p = LatLng(lat / 1e5, lng / 1e5);
        if (p.latitude.abs() > 90 || p.longitude.abs() > 180) return const []; // chuỗi hỏng
        points.add(p);
      }
    } catch (_) {
      // Chuỗi hỏng -> trả phần đã giải mã được.
    }
    return points;
  }

  /// Khoảng cách đường chim bay (km).
  static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
  }

  static double _rad(double d) => d * math.pi / 180;

  /// Tổng chiều dài (km) của một đường gồm nhiều điểm.
  static double polylineKm(List<LatLng> pts) {
    var km = 0.0;
    for (var i = 1; i < pts.length; i++) {
      km += haversineKm(pts[i - 1].latitude, pts[i - 1].longitude, pts[i].latitude, pts[i].longitude);
    }
    return km;
  }

  /// Ước tính quãng đường xe điện gấp của tài xế tới điểm đón (haversine × 1.3, như backend).
  static double roadKm(LatLng a, LatLng b) =>
      haversineKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1.3;

  /// ETA (phút) với tốc độ xe điện gấp ~15 km/h, tối thiểu 1 phút.
  static int scooterEtaMin(double km) => math.max(1, (km / 15 * 60).ceil());

  /// Khung bao chứa tất cả điểm (null nếu rỗng).
  static LatLngBounds? boundsOf(Iterable<LatLng> points) {
    double? minLat, maxLat, minLng, maxLng;
    for (final p in points) {
      minLat = minLat == null ? p.latitude : math.min(minLat, p.latitude);
      maxLat = maxLat == null ? p.latitude : math.max(maxLat, p.latitude);
      minLng = minLng == null ? p.longitude : math.min(minLng, p.longitude);
      maxLng = maxLng == null ? p.longitude : math.max(maxLng, p.longitude);
    }
    if (minLat == null) return null;
    // Tránh khung bao suy biến (1 điểm) làm camera zoom tối đa.
    if ((maxLat! - minLat).abs() < 0.002 && (maxLng! - minLng!).abs() < 0.002) {
      minLat -= 0.002;
      maxLat += 0.002;
      minLng -= 0.002;
      maxLng += 0.002;
    }
    return LatLngBounds(LatLng(minLat, minLng!), LatLng(maxLat, maxLng!));
  }

  static String formatKm(double? km) => km == null ? '—' : '${km.toStringAsFixed(1)} km';
}
