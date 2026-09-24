import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

/// Kết quả xin quyền / lấy vị trí, kèm thông báo tiếng Việt khi thất bại.
class LocationResult {
  final Position? position;
  final String? error;
  const LocationResult({this.position, this.error});
  bool get ok => position != null;
}

/// Bọc geolocator: xin quyền, lấy vị trí hiện tại, stream vị trí (chỉ khi app ở foreground).
class LocationService {
  /// Kiểm tra dịch vụ vị trí + xin quyền. Trả về null nếu OK, ngược lại là thông báo lỗi.
  static Future<String?> ensurePermission() async {
    try {
      if (!kIsWeb) {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (!enabled) {
          return 'Dịch vụ định vị (GPS) đang tắt. Vui lòng bật định vị trong Cài đặt.';
        }
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        return 'Bạn đã từ chối quyền truy cập vị trí. DRIVO cần vị trí để xác định điểm đón.';
      }
      if (perm == LocationPermission.deniedForever) {
        return 'Quyền vị trí đã bị chặn vĩnh viễn. Vui lòng mở Cài đặt ứng dụng để cấp lại quyền.';
      }
      return null;
    } catch (e) {
      return 'Không thể truy cập vị trí trên thiết bị này.';
    }
  }

  /// Lấy vị trí hiện tại (thử vị trí gần nhất đã biết nếu lấy mới quá lâu).
  static Future<LocationResult> getCurrent({Duration timeout = const Duration(seconds: 12)}) async {
    final err = await ensurePermission();
    if (err != null) return LocationResult(error: err);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
      return LocationResult(position: pos);
    } catch (_) {
      try {
        if (!kIsWeb) {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) return LocationResult(position: last);
        }
      } catch (_) {}
      return const LocationResult(error: 'Không lấy được vị trí hiện tại. Vui lòng thử lại.');
    }
  }

  /// Stream vị trí liên tục (distanceFilter mặc định 10 m). Cần gọi [ensurePermission] trước.
  static Stream<Position> positionStream({int distanceFilterMeters = 10}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    );
  }

  static Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }
}
