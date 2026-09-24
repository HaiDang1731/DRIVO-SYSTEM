import 'dart:async';

import 'package:signalr_netcore/signalr_client.dart';

import 'api_service.dart';

double? _d(dynamic v) => v == null ? null : (v as num).toDouble();

/// Sự kiện `DriverLocation` từ hub.
class DriverLocationEvent {
  final int driverId;
  final int? bookingId;
  final double latitude;
  final double longitude;
  final double? heading;
  final double? speedKmh;
  final String? driverStatus;
  final DateTime recordedAt;

  DriverLocationEvent({
    required this.driverId,
    this.bookingId,
    required this.latitude,
    required this.longitude,
    this.heading,
    this.speedKmh,
    this.driverStatus,
    required this.recordedAt,
  });

  factory DriverLocationEvent.fromJson(Map<String, dynamic> j) => DriverLocationEvent(
    driverId: (j['driverId'] as num?)?.toInt() ?? 0,
    bookingId: (j['bookingId'] as num?)?.toInt(),
    latitude: _d(j['latitude']) ?? 0,
    longitude: _d(j['longitude']) ?? 0,
    heading: _d(j['heading']),
    speedKmh: _d(j['speedKmh']),
    driverStatus: j['driverStatus']?.toString(),
    recordedAt: DateTime.tryParse(j['recordedAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

/// Sự kiện `BookingStatusChanged` từ hub.
class BookingStatusEvent {
  final int bookingId;
  final String? bookingCode;
  final String status;
  final double? finalPrice;
  final double pickupFee;
  final double waitingFee;
  final double extraDistanceFee;

  BookingStatusEvent({
    required this.bookingId,
    this.bookingCode,
    required this.status,
    this.finalPrice,
    this.pickupFee = 0,
    this.waitingFee = 0,
    this.extraDistanceFee = 0,
  });

  factory BookingStatusEvent.fromJson(Map<String, dynamic> j) => BookingStatusEvent(
    bookingId: (j['bookingId'] as num?)?.toInt() ?? 0,
    bookingCode: j['bookingCode']?.toString(),
    status: j['status']?.toString() ?? '',
    finalPrice: _d(j['finalPrice']),
    pickupFee: _d(j['pickupFee']) ?? 0,
    waitingFee: _d(j['waitingFee']) ?? 0,
    extraDistanceFee: _d(j['extraDistanceFee']) ?? 0,
  );
}

/// Kết nối SignalR tới `/hubs/tracking` (JWT qua access_token).
/// Mọi lỗi đều được nuốt: nếu hub không khả dụng, màn hình vẫn dùng polling như cũ.
class TrackingService {
  TrackingService._();
  static final TrackingService instance = TrackingService._();

  HubConnection? _conn;
  Future<bool>? _connecting;
  Timer? _retryTimer;
  final Set<int> _groups = {};

  final _locationCtrl = StreamController<DriverLocationEvent>.broadcast();
  final _statusCtrl = StreamController<BookingStatusEvent>.broadcast();
  final _connectedCtrl = StreamController<bool>.broadcast();

  Stream<DriverLocationEvent> get driverLocations => _locationCtrl.stream;
  Stream<BookingStatusEvent> get bookingStatusChanges => _statusCtrl.stream;
  Stream<bool> get connectionChanges => _connectedCtrl.stream;

  bool get isConnected => _conn?.state == HubConnectionState.Connected;

  /// `http://host:port/api/v1` -> `http://host:port/hubs/tracking`
  static String get hubUrl {
    var base = ApiService.baseUrl;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (base.endsWith('/api/v1')) base = base.substring(0, base.length - '/api/v1'.length);
    return '$base/hubs/tracking';
  }

  Future<bool> connect() {
    if (isConnected) return Future.value(true);
    if (ApiService.getToken() == null) return Future.value(false);
    return _connecting ??= _doConnect().whenComplete(() => _connecting = null);
  }

  Future<bool> _doConnect() async {
    try {
      final conn = HubConnectionBuilder()
          .withUrl(
            hubUrl,
            options: HttpConnectionOptions(
              accessTokenFactory: () async => ApiService.getToken() ?? '',
              requestTimeout: 10000,
            ),
          )
          .withAutomaticReconnect(retryDelays: [0, 2000, 5000, 10000, 20000, 30000])
          .build();

      conn.on('DriverLocation', (args) {
        final m = _firstMap(args);
        if (m != null) {
          try {
            _locationCtrl.add(DriverLocationEvent.fromJson(m));
          } catch (_) {}
        }
      });
      conn.on('BookingStatusChanged', (args) {
        final m = _firstMap(args);
        if (m != null) {
          try {
            _statusCtrl.add(BookingStatusEvent.fromJson(m));
          } catch (_) {}
        }
      });
      conn.onreconnected(({connectionId}) {
        _connectedCtrl.add(true);
        _rejoinAll();
      });
      conn.onreconnecting(({error}) => _connectedCtrl.add(false));
      conn.onclose(({error}) {
        _connectedCtrl.add(false);
        _scheduleRetry();
      });

      _conn = conn;
      await conn.start()?.timeout(const Duration(seconds: 12));
      _connectedCtrl.add(true);
      await _rejoinAll();
      return true;
    } catch (_) {
      try {
        await _conn?.stop();
      } catch (_) {}
      _conn = null;
      _scheduleRetry();
      return false;
    }
  }

  Map<String, dynamic>? _firstMap(List<Object?>? args) {
    if (args == null || args.isEmpty) return null;
    final a = args.first;
    if (a is Map) return Map<String, dynamic>.from(a);
    return null;
  }

  /// Tự thử kết nối lại mỗi 30 s khi vẫn còn chuyến cần theo dõi.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_groups.isEmpty) return;
    _retryTimer = Timer(const Duration(seconds: 30), () {
      if (_groups.isNotEmpty && !isConnected) connect();
    });
  }

  Future<void> _rejoinAll() async {
    for (final id in _groups.toList()) {
      try {
        await _conn?.invoke('JoinBooking', args: <Object>[id]);
      } catch (_) {}
    }
  }

  Future<void> joinBooking(int bookingId) async {
    final isNew = _groups.add(bookingId);
    if (isConnected) {
      if (isNew) {
        try {
          await _conn!.invoke('JoinBooking', args: <Object>[bookingId]);
        } catch (_) {}
      }
    } else {
      await connect(); // connect() tự join các group đang theo dõi
    }
  }

  Future<void> leaveBooking(int bookingId) async {
    if (!_groups.remove(bookingId)) return;
    if (isConnected) {
      try {
        await _conn!.invoke('LeaveBooking', args: <Object>[bookingId]);
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    _groups.clear();
    _retryTimer?.cancel();
    final c = _conn;
    _conn = null;
    try {
      await c?.stop();
    } catch (_) {}
  }
}
