import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';

import 'geo_utils.dart';

export 'package:flutter_map/flutter_map.dart' show LatLngBounds;
export 'package:latlong2/latlong.dart' show LatLng;

/// Tâm mặc định (Hồ Hoàn Kiếm, Hà Nội) khi không lấy được GPS.
const LatLng kDefaultMapCenter = LatLng(21.0285, 105.8542);

/// Kiểu nền bản đồ (đều miễn phí, không cần key).
enum DrivoMapStyle { standard, voyager }

/// Loại marker dùng chung.
enum MapMarkerKind { pickup, destination, scooter, myLocation }

class MapMarker {
  final String id;
  final LatLng position;
  final MapMarkerKind kind;
  final String? title;

  const MapMarker({required this.id, required this.position, required this.kind, this.title});
}

class MapLine {
  final String id;
  final List<LatLng> points;
  final Color color;
  final double width;
  final bool dashed;

  const MapLine({
    required this.id,
    required this.points,
    required this.color,
    this.width = 5,
    this.dashed = false,
  });
}

/// Điều khiển camera của [DrivoMap] (bọc [fm.MapController], nuốt lỗi khi map chưa sẵn sàng).
class DrivoMapController {
  final fm.MapController _c;
  DrivoMapController._(this._c);

  LatLng get center => _c.camera.center;
  double get zoom => _c.camera.zoom;

  void move(LatLng target, {double? zoom}) {
    try {
      _c.move(target, zoom ?? _c.camera.zoom);
    } catch (_) {}
  }

  /// Trả về false nếu map chưa sẵn sàng (caller nên thử lại sau).
  bool fitBounds(fm.LatLngBounds bounds, {double padding = 60, double maxZoom = 17}) {
    try {
      // Map chưa layout xong (size 0) hoặc quá nhỏ so với padding -> zoom âm, toạ độ vượt ±180 (assert crash).
      final size = _c.camera.nonRotatedSize;
      final minSide = math.min(size.width, size.height);
      if (!minSide.isFinite || minSide < 40) return false;
      final pad = math.min(padding, minSide / 4);
      _c.fitCamera(fm.CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(pad),
        maxZoom: maxZoom,
        minZoom: 3,
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Đưa camera bao trọn các điểm. Trả về false nếu map chưa sẵn sàng.
  bool fitPoints(Iterable<LatLng> points, {double padding = 60}) {
    final list = points.toList();
    if (list.isEmpty) return false;
    if (list.length == 1) {
      move(list.first, zoom: 15);
      return true;
    }
    final b = GeoUtils.boundsOf(list);
    return b != null && fitBounds(b, padding: padding);
  }
}

/// Bản đồ OpenStreetMap (flutter_map) dùng chung cho khách & tài xế.
class DrivoMap extends StatefulWidget {
  final LatLng initialTarget;
  final double initialZoom;
  final List<MapMarker> markers;
  final List<MapLine> polylines;
  final LatLng? myLocation;
  final DrivoMapStyle style;
  final void Function(DrivoMapController controller)? onMapCreated;
  final void Function(LatLng center)? onCameraMove;
  final VoidCallback? onCameraIdle;

  const DrivoMap({
    super.key,
    required this.initialTarget,
    this.initialZoom = 15,
    this.markers = const [],
    this.polylines = const [],
    this.myLocation,
    this.style = DrivoMapStyle.standard,
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraIdle,
  });

  static const String userAgentPackageName = 'com.drivo.drivo_mobile';

  /// Tiện ích tĩnh: căn camera bao trọn các điểm.
  static bool fitPoints(DrivoMapController? c, Iterable<LatLng> points, {double padding = 60}) =>
      c?.fitPoints(points, padding: padding) ?? false;

  @override
  State<DrivoMap> createState() => _DrivoMapState();
}

class _DrivoMapState extends State<DrivoMap> {
  final fm.MapController _mapController = fm.MapController();
  late final DrivoMapController _ctrl = DrivoMapController._(_mapController);

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _onEvent(fm.MapEvent e) {
    widget.onCameraMove?.call(e.camera.center);
    // Di chuyển bằng code (move/fitCamera) không có sự kiện "End" -> coi như idle ngay.
    final programmatic = e is fm.MapEventMove &&
        (e.source == fm.MapEventSource.mapController || e.source == fm.MapEventSource.fitCamera);
    if (programmatic ||
        e is fm.MapEventMoveEnd ||
        e is fm.MapEventFlingAnimationEnd ||
        e is fm.MapEventDoubleTapZoomEnd ||
        e is fm.MapEventScrollWheelZoom) {
      widget.onCameraIdle?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final voyager = widget.style == DrivoMapStyle.voyager;
    final lines = <fm.Polyline>[
      for (final l in widget.polylines)
        // Đường gần như dài 0 làm vòng lặp nét đứt của flutter_map chạy mãi (treo cả màn hình) -> bỏ qua.
        if (l.points.length >= 2 && GeoUtils.polylineKm(l.points) >= 0.005)
          fm.Polyline(
            points: l.points,
            color: l.color,
            strokeWidth: l.width,
            // patternFit.none: không co giãn mẫu theo độ dài đường (hệ số 0 khi đường quá ngắn).
            pattern: l.dashed
                ? fm.StrokePattern.dashed(segments: const [18, 10], patternFit: fm.PatternFit.none)
                : const fm.StrokePattern.solid(),
          ),
    ];
    final markers = <fm.Marker>[
      if (widget.myLocation != null)
        fm.Marker(point: widget.myLocation!, width: 22, height: 22, child: const _MyLocationDot()),
      for (final m in widget.markers.where((m) => m.kind != MapMarkerKind.scooter)) _toMarker(m),
      for (final m in widget.markers.where((m) => m.kind == MapMarkerKind.scooter)) _toMarker(m),
    ];

    return fm.FlutterMap(
      mapController: _mapController,
      options: fm.MapOptions(
        initialCenter: widget.initialTarget,
        initialZoom: widget.initialZoom,
        minZoom: 3,
        maxZoom: 19,
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
        ),
        onMapReady: () => widget.onMapCreated?.call(_ctrl),
        onMapEvent: _onEvent,
      ),
      children: [
        fm.TileLayer(
          urlTemplate: voyager
              // Kiểu "Humanitarian" của OSM Pháp (miễn phí; CARTO giờ đòi API key)
              ? 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png'
              // tile.openstreetmap.org bị chặn ở một số mạng VN -> dùng mirror openstreetmap.de
              : 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
          subdomains: voyager ? const ['a', 'b', 'c'] : const [],
          userAgentPackageName: DrivoMap.userAgentPackageName,
          maxZoom: 19,
        ),
        if (lines.isNotEmpty) fm.PolylineLayer(polylines: lines),
        if (markers.isNotEmpty) fm.MarkerLayer(markers: markers),
        fm.SimpleAttributionWidget(
          source: Text(voyager ? '© OpenStreetMap, OSM France' : '© OpenStreetMap'),
          backgroundColor: Colors.white70,
        ),
      ],
    );
  }

  fm.Marker _toMarker(MapMarker m) {
    final icon = MapIcons.widgetFor(m.kind);
    return fm.Marker(
      point: m.position,
      width: 40,
      height: 40,
      child: m.title == null ? icon : Tooltip(message: m.title!, child: icon),
    );
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A73E8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: const Color(0xFF1A73E8).withValues(alpha: 0.35), blurRadius: 8, spreadRadius: 3)],
      ),
    );
  }
}

/// Icon marker dùng chung (widget tròn từ Material icon).
class MapIcons {
  static Widget widgetFor(MapMarkerKind kind) {
    switch (kind) {
      case MapMarkerKind.scooter:
        return _circle(Icons.electric_scooter_rounded, const Color(0xFF10B981));
      case MapMarkerKind.pickup:
        return _circle(Icons.my_location_rounded, const Color(0xFF0070E0));
      case MapMarkerKind.destination:
        return _circle(Icons.location_on_rounded, const Color(0xFFFF3B30));
      case MapMarkerKind.myLocation:
        return const Center(child: SizedBox(width: 22, height: 22, child: _MyLocationDot()));
    }
  }

  static Widget _circle(IconData icon, Color color) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
