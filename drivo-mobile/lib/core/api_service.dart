import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Model classes ──────────────────────────────────────────────
class AuthUser {
  final int id;
  final String fullName;
  final String phone;
  final String? email;
  final List<String> roles;

  AuthUser({required this.id, required this.fullName, required this.phone, this.email, required this.roles});

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
    id: j['id'],
    fullName: j['fullName'],
    phone: j['phone'],
    email: j['email'],
    roles: List<String>.from(j['roles'] ?? []),
  );

  bool get isDriver => roles.contains('DRIVER');
  bool get isCustomer => roles.contains('CUSTOMER');
}

class CustomerVehicle {
  final int id;
  final String? brand;
  final String? model;
  final String? color;
  final String licensePlate;
  final String vehicleType;
  final String transmission;
  final bool isDefault;

  CustomerVehicle({
    required this.id,
    this.brand,
    this.model,
    this.color,
    required this.licensePlate,
    required this.vehicleType,
    required this.transmission,
    required this.isDefault,
  });

  factory CustomerVehicle.fromJson(Map<String, dynamic> j) => CustomerVehicle(
    id: j['id'],
    brand: j['brand'],
    model: j['model'],
    color: j['color'],
    licensePlate: j['licensePlate'],
    vehicleType: j['vehicleType'] ?? 'Car',
    transmission: j['transmission'] ?? 'Automatic',
    isDefault: j['isDefault'] ?? false,
  );

  String get displayInfo => '${brand ?? ''} ${model ?? ''} - $licensePlate'.trim();

  String get displayName {
    final name = '${brand ?? ""} ${model ?? ""}'.trim();
    return name.isEmpty ? licensePlate : '$name ($licensePlate)';
  }
}

double? _toD(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int? _toI(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));
/// Mốc thời gian từ API (UTC) -> giờ máy.
DateTime? _toDt(dynamic v) => _utcToLocal(v);

class FareEstimate {
  final double estimatedDistanceKm;
  final int estimatedDurationMin;
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double nightSurcharge;
  final double totalEstimatedFare;
  // Maps / phí đón (xe điện gấp của tài xế -> điểm đón)
  final String? routePolyline;
  final double? estimatedPickupKm;
  final double? estimatedPickupFee;
  final int? nearestDriverEtaMin;
  final double freePickupKm;
  final double pickupFeePerKm;
  final double waitingPricePerMin;
  final int freeWaitingMin;

  FareEstimate({
    required this.estimatedDistanceKm,
    required this.estimatedDurationMin,
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.nightSurcharge,
    required this.totalEstimatedFare,
    this.routePolyline,
    this.estimatedPickupKm,
    this.estimatedPickupFee,
    this.nearestDriverEtaMin,
    this.freePickupKm = 0,
    this.pickupFeePerKm = 0,
    this.waitingPricePerMin = 0,
    this.freeWaitingMin = 0,
  });

  factory FareEstimate.fromJson(Map<String, dynamic> j) => FareEstimate(
    estimatedDistanceKm: _toD(j['estimatedDistanceKm']) ?? 0,
    estimatedDurationMin: _toI(j['estimatedDurationMin']) ?? 0,
    baseFare: _toD(j['baseFare']) ?? 0,
    distanceFare: _toD(j['distanceFare']) ?? 0,
    timeFare: _toD(j['timeFare']) ?? 0,
    nightSurcharge: _toD(j['nightSurcharge']) ?? 0,
    totalEstimatedFare: _toD(j['totalEstimatedFare']) ?? 0,
    routePolyline: j['routePolyline'],
    estimatedPickupKm: _toD(j['estimatedPickupKm']),
    estimatedPickupFee: _toD(j['estimatedPickupFee']),
    nearestDriverEtaMin: _toI(j['nearestDriverEtaMin']),
    freePickupKm: _toD(j['freePickupKm']) ?? 0,
    pickupFeePerKm: _toD(j['pickupFeePerKm']) ?? 0,
    waitingPricePerMin: _toD(j['waitingPricePerMin']) ?? 0,
    freeWaitingMin: _toI(j['freeWaitingMin']) ?? 0,
  );
}

// ── Maps models ────────────────────────────────────────────────
class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;
  /// Toạ độ đi kèm gợi ý (OSM/Photon) — có thì không cần gọi /maps/place.
  final double? latitude;
  final double? longitude;

  PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    this.latitude,
    this.longitude,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> j) => PlaceSuggestion(
    placeId: j['placeId'] ?? '',
    mainText: j['mainText'] ?? '',
    secondaryText: j['secondaryText'] ?? '',
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
  );
}

/// Kết quả /maps/place/{id} và /maps/reverse-geocode.
class GeoPlace {
  final String? placeId;
  final String address;
  final double latitude;
  final double longitude;

  GeoPlace({this.placeId, required this.address, required this.latitude, required this.longitude});

  factory GeoPlace.fromJson(Map<String, dynamic> j) => GeoPlace(
    placeId: j['placeId'],
    address: j['address'] ?? '',
    latitude: _toD(j['latitude']) ?? 0,
    longitude: _toD(j['longitude']) ?? 0,
  );
}

class RouteInfo {
  final double distanceKm;
  final int durationMin;
  final String? polyline;

  RouteInfo({required this.distanceKm, required this.durationMin, this.polyline});

  factory RouteInfo.fromJson(Map<String, dynamic> j) => RouteInfo(
    distanceKm: _toD(j['distanceKm']) ?? 0,
    durationMin: _toI(j['durationMin']) ?? 0,
    polyline: j['polyline'],
  );
}

class BookingDetail {
  final int id;
  final String bookingCode;
  final String status;
  final String pickupAddress;
  final String destinationAddress;
  final double estimatedPrice;
  final double? finalPrice;
  final DateTime createdAt;
  final String vehicleInfo;
  final String? driverName;
  final String? driverPhone;
  final int? driverId;
  final String? customerNote;
  // Toạ độ & lộ trình
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final double estimatedDistanceKm;
  final int estimatedDurationMin;
  final String? routePolyline;
  // Phí phát sinh
  final double? pickupDistanceKm;
  final double pickupFee;
  final double waitingFee;
  final double extraDistanceFee;
  final double discount;
  final double? actualDistanceKm;
  // Mốc thời gian
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  // Vị trí tài xế (khi đã có tài xế)
  final double? driverLatitude;
  final double? driverLongitude;
  final DateTime? driverLastLocationAt;

  BookingDetail({
    required this.id,
    required this.bookingCode,
    required this.status,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.estimatedPrice,
    this.finalPrice,
    required this.createdAt,
    required this.vehicleInfo,
    this.driverName,
    this.driverPhone,
    this.driverId,
    this.customerNote,
    this.pickupLatitude,
    this.pickupLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.estimatedDistanceKm = 0,
    this.estimatedDurationMin = 0,
    this.routePolyline,
    this.pickupDistanceKm,
    this.pickupFee = 0,
    this.waitingFee = 0,
    this.extraDistanceFee = 0,
    this.discount = 0,
    this.actualDistanceKm,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.driverLatitude,
    this.driverLongitude,
    this.driverLastLocationAt,
  });

  factory BookingDetail.fromJson(Map<String, dynamic> j) {
    final v = j['vehicle'];
    final d = j['driver'];
    String vInfo = 'Ô tô';
    if (v != null) {
      vInfo = '${v['brand'] ?? ""} ${v['model'] ?? ""} - ${v['licensePlate']}'.trim();
    }
    return BookingDetail(
      id: j['id'],
      bookingCode: j['bookingCode'],
      status: j['status'],
      pickupAddress: j['pickupAddress'],
      destinationAddress: j['destinationAddress'],
      estimatedPrice: (j['estimatedPrice'] as num).toDouble(),
      finalPrice: j['finalPrice'] != null ? (j['finalPrice'] as num).toDouble() : null,
      createdAt: _toDt(j['createdAt']) ?? DateTime.now(),
      vehicleInfo: vInfo,
      driverName: d != null ? d['fullName'] : null,
      driverPhone: d != null ? d['phone'] : null,
      driverId: d != null ? _toI(d['id']) : null,
      customerNote: j['customerNote'],
      pickupLatitude: _toD(j['pickupLatitude']),
      pickupLongitude: _toD(j['pickupLongitude']),
      destinationLatitude: _toD(j['destinationLatitude']),
      destinationLongitude: _toD(j['destinationLongitude']),
      estimatedDistanceKm: _toD(j['estimatedDistanceKm']) ?? 0,
      estimatedDurationMin: _toI(j['estimatedDurationMin']) ?? 0,
      routePolyline: j['routePolyline'],
      pickupDistanceKm: _toD(j['pickupDistanceKm']),
      pickupFee: _toD(j['pickupFee']) ?? 0,
      waitingFee: _toD(j['waitingFee']) ?? 0,
      extraDistanceFee: _toD(j['extraDistanceFee']) ?? 0,
      discount: _toD(j['discount']) ?? 0,
      actualDistanceKm: _toD(j['actualDistanceKm']),
      acceptedAt: _toDt(j['acceptedAt']),
      arrivedAt: _toDt(j['arrivedAt']),
      startedAt: _toDt(j['startedAt']),
      completedAt: _toDt(j['completedAt']),
      driverLatitude: _toD(j['driverLatitude']),
      driverLongitude: _toD(j['driverLongitude']),
      driverLastLocationAt: _toDt(j['driverLastLocationAt']),
    );
  }

  bool get hasPickupCoords =>
      pickupLatitude != null && pickupLongitude != null && !(pickupLatitude == 0 && pickupLongitude == 0);
  bool get hasDestinationCoords =>
      destinationLatitude != null && destinationLongitude != null &&
      !(destinationLatitude == 0 && destinationLongitude == 0);
  bool get hasDriverCoords => driverLatitude != null && driverLongitude != null;

  String get statusDisplay {
    switch (status) {
      case 'Pending':
      case 'SearchingDriver':
        return 'Đang tìm tài xế';
      case 'DriverAssigned':
      case 'DriverAccepted':
        return 'Tài xế đã nhận';
      case 'DriverArriving':
        return 'Tài xế đang đến';
      case 'DriverArrived':
        return 'Tài xế đã đến điểm đón';
      case 'InProgress':
        return 'Đang di chuyển';
      case 'Completed':
        return 'Đã hoàn thành';
      case 'Cancelled':
        return 'Đã hủy';
      default:
        return status;
    }
  }
}

/// API trả DateTime UTC không kèm 'Z' -> ép hiểu là UTC rồi đổi sang giờ máy.
DateTime? _utcToLocal(dynamic v) {
  if (v == null) return null;
  var s = v.toString();
  if (!RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(s)) s = '${s}Z';
  return DateTime.tryParse(s)?.toLocal();
}

class VoucherInfo {
  final String code;
  final String title;
  final String? description;
  final String discountType;
  final double discountValue;
  final double? maxDiscountAmount;
  final double minOrderAmount;
  final DateTime? endDate;

  VoucherInfo.fromJson(Map<String, dynamic> j)
      : code = j['code'] ?? '',
        title = j['title'] ?? '',
        description = j['description'],
        discountType = j['discountType'] ?? 'FIXED',
        discountValue = _toD(j['discountValue']) ?? 0,
        maxDiscountAmount = _toD(j['maxDiscountAmount']),
        minOrderAmount = _toD(j['minOrderAmount']) ?? 0,
        endDate = _utcToLocal(j['endDate']);

  static String _money(double v) =>
      '${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}đ';

  /// VD: "Giảm 20%, tối đa 50.000đ · đơn từ 50.000đ · HSD 22/11"
  String get summary {
    final parts = <String>[
      discountType == 'PERCENT'
          ? 'Giảm ${discountValue.toStringAsFixed(0)}%'
              '${maxDiscountAmount != null && maxDiscountAmount! > 0 ? ', tối đa ${_money(maxDiscountAmount!)}' : ''}'
          : 'Giảm ${_money(discountValue)}',
      if (minOrderAmount > 0) 'đơn từ ${_money(minOrderAmount)}',
      if (endDate != null) 'HSD ${endDate!.day.toString().padLeft(2, '0')}/${endDate!.month.toString().padLeft(2, '0')}',
    ];
    return parts.join(' · ');
  }
}

class EarningsTrip {
  final int id;
  final String bookingCode;
  final DateTime completedAt;
  final String pickupAddress;
  final String destinationAddress;
  final double grossFare;
  final double discount;
  final double customerPaid;
  final double commission;
  final double payout;
  final String paymentMethod;

  EarningsTrip.fromJson(Map<String, dynamic> j)
      : id = _toI(j['id']) ?? 0,
        bookingCode = j['bookingCode'] ?? '',
        completedAt = _utcToLocal(j['completedAt']) ?? DateTime.now(),
        pickupAddress = j['pickupAddress'] ?? '',
        destinationAddress = j['destinationAddress'] ?? '',
        grossFare = _toD(j['grossFare']) ?? 0,
        discount = _toD(j['discount']) ?? 0,
        customerPaid = _toD(j['customerPaid']) ?? 0,
        commission = _toD(j['commission']) ?? 0,
        payout = _toD(j['payout']) ?? 0,
        paymentMethod = j['paymentMethod'] ?? 'Cash';
}

class EarningsBucket {
  final String date;
  final String label;
  final int trips;
  final double payout;

  EarningsBucket.fromJson(Map<String, dynamic> j)
      : date = j['date'] ?? '',
        label = j['label'] ?? '',
        trips = _toI(j['trips']) ?? 0,
        payout = _toD(j['payout']) ?? 0;
}

class DriverEarnings {
  final String period;
  final DateTime from;
  final DateTime to;
  final int tripCount;
  final double grossFare;
  final double commission;
  final double voucherSupport;
  final double payout;
  final double customerPaid;
  final double cashCollected;
  final double balanceWithPlatform;
  final List<EarningsBucket> buckets;
  final List<EarningsTrip> trips;

  DriverEarnings.fromJson(Map<String, dynamic> j)
      : period = j['period'] ?? 'day',
        from = DateTime.tryParse(j['from'] ?? '') ?? DateTime.now(),
        to = DateTime.tryParse(j['to'] ?? '') ?? DateTime.now(),
        tripCount = _toI(j['tripCount']) ?? 0,
        grossFare = _toD(j['grossFare']) ?? 0,
        commission = _toD(j['commission']) ?? 0,
        voucherSupport = _toD(j['voucherSupport']) ?? 0,
        payout = _toD(j['payout']) ?? 0,
        customerPaid = _toD(j['customerPaid']) ?? 0,
        cashCollected = _toD(j['cashCollected']) ?? 0,
        balanceWithPlatform = _toD(j['balanceWithPlatform']) ?? 0,
        buckets = ((j['buckets'] as List?) ?? []).map((x) => EarningsBucket.fromJson(x)).toList(),
        trips = ((j['trips'] as List?) ?? []).map((x) => EarningsTrip.fromJson(x)).toList();
}

class DriverProfile {
  final int driverId;
  final String fullName;
  final String phone;
  final String? email;
  final String? avatarUrl;
  final String licenseNumber;
  final String? licenseClass;
  final String verificationStatus;
  final String driverStatus;
  final double ratingAverage;
  final int totalTrips;
  final double totalEarnings;
  final bool isFirstLogin;

  DriverProfile({
    required this.driverId, required this.fullName, required this.phone,
    this.email, this.avatarUrl, required this.licenseNumber, this.licenseClass,
    required this.verificationStatus, required this.driverStatus,
    required this.ratingAverage, required this.totalTrips,
    required this.totalEarnings, required this.isFirstLogin,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> j) => DriverProfile(
    driverId: j['driverId'],
    fullName: j['fullName'],
    phone: j['phone'],
    email: j['email'],
    avatarUrl: j['avatarUrl'],
    licenseNumber: j['licenseNumber'],
    licenseClass: j['licenseClass'],
    verificationStatus: j['verificationStatus'],
    driverStatus: j['driverStatus'],
    ratingAverage: (j['ratingAverage'] as num).toDouble(),
    totalTrips: j['totalTrips'],
    totalEarnings: (j['totalEarnings'] as num).toDouble(),
    isFirstLogin: j['isFirstLogin'] ?? false,
  );
}


// ── Driver Booking model ───────────────────────────────────────
class DriverBooking {
  final int id;
  final String bookingCode;
  final String status;
  final String pickupAddress;
  final String destinationAddress;
  final double estimatedPrice;
  final double estimatedDistanceKm;
  final int estimatedDurationMin;
  final String vehiclePlate;
  final String vehicleBrand;
  final String vehicleModel;
  final String vehicleTransmission;
  final String? customerNote;
  final double? finalPrice;
  final DateTime createdAt;
  // Maps / phí
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final String? routePolyline;
  final double? distanceToPickupKm;
  /// Số giây còn lại của lượt ưu tiên riêng cho tài xế này (null = cuốc đang mở cho mọi tài xế).
  final int? offerSecondsLeft;
  final double? pickupDistanceKm;
  final double pickupFee;
  final double waitingFee;
  final double extraDistanceFee;
  final double discount;
  final double? actualDistanceKm;
  final double commissionAmount;
  final double driverPayout;
  final String paymentMethod;
  final String? voucherCode;
  final String? customerName;
  final String? customerPhone;

  DriverBooking({
    required this.id,
    required this.bookingCode,
    required this.status,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.estimatedPrice,
    required this.estimatedDistanceKm,
    required this.estimatedDurationMin,
    required this.vehiclePlate,
    required this.vehicleBrand,
    required this.vehicleModel,
    required this.vehicleTransmission,
    this.customerNote,
    this.finalPrice,
    required this.createdAt,
    this.pickupLatitude,
    this.pickupLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.routePolyline,
    this.distanceToPickupKm,
    this.offerSecondsLeft,
    this.pickupDistanceKm,
    this.pickupFee = 0,
    this.waitingFee = 0,
    this.extraDistanceFee = 0,
    this.discount = 0,
    this.actualDistanceKm,
    this.commissionAmount = 0,
    this.driverPayout = 0,
    this.paymentMethod = 'Cash',
    this.voucherCode,
    this.customerName,
    this.customerPhone,
  });

  bool get hasPickupCoords =>
      pickupLatitude != null && pickupLongitude != null && !(pickupLatitude == 0 && pickupLongitude == 0);
  bool get hasDestinationCoords =>
      destinationLatitude != null && destinationLongitude != null &&
      !(destinationLatitude == 0 && destinationLongitude == 0);

  factory DriverBooking.fromJson(Map<String, dynamic> j) {
    final v = j['vehicle'] ?? {};
    final c = j['customer'];
    return DriverBooking(
      finalPrice: _toD(j['finalPrice']),
      pickupLatitude: _toD(j['pickupLatitude']),
      pickupLongitude: _toD(j['pickupLongitude']),
      destinationLatitude: _toD(j['destinationLatitude']),
      destinationLongitude: _toD(j['destinationLongitude']),
      routePolyline: j['routePolyline'],
      distanceToPickupKm: _toD(j['distanceToPickupKm']),
      offerSecondsLeft: _toI(j['offerSecondsLeft']),
      pickupDistanceKm: _toD(j['pickupDistanceKm']),
      pickupFee: _toD(j['pickupFee']) ?? 0,
      waitingFee: _toD(j['waitingFee']) ?? 0,
      extraDistanceFee: _toD(j['extraDistanceFee']) ?? 0,
      discount: _toD(j['discount']) ?? 0,
      actualDistanceKm: _toD(j['actualDistanceKm']),
      commissionAmount: _toD(j['commissionAmount']) ?? 0,
      driverPayout: _toD(j['driverPayout']) ?? 0,
      paymentMethod: j['paymentMethod'] ?? 'Cash',
      voucherCode: j['voucherCode'],
      customerName: c is Map ? c['fullName'] : j['customerName'],
      customerPhone: c is Map ? c['phone'] : j['customerPhone'],
      id: j['id'],
      bookingCode: j['bookingCode'] ?? '',
      status: j['status'] ?? '',
      pickupAddress: j['pickupAddress'] ?? '',
      destinationAddress: j['destinationAddress'] ?? '',
      estimatedPrice: (j['estimatedPrice'] as num?)?.toDouble() ?? 0,
      estimatedDistanceKm: (j['estimatedDistanceKm'] as num?)?.toDouble() ?? 0,
      estimatedDurationMin: j['estimatedDurationMin'] ?? 0,
      vehiclePlate: v['licensePlate'] ?? '',
      vehicleBrand: v['brand'] ?? '',
      vehicleModel: v['model'] ?? '',
      vehicleTransmission: v['transmission'] ?? '',
      customerNote: j['customerNote'],
      createdAt: _toDt(j['createdAt']) ?? DateTime.now(),
    );
  }

  String get statusDisplay {
    switch (status) {
      case 'SearchingDriver': return 'Đang tìm tài xế';
      case 'DriverAccepted': return 'Đã nhận cuốc';
      case 'DriverArriving': return 'Đang đến điểm đón';
      case 'DriverArrived': return 'Đã đến điểm đón';
      case 'InProgress': return 'Đang chạy';
      case 'Completed': return 'Hoàn thành';
      case 'Cancelled': return 'Đã hủy';
      default: return status;
    }
  }

  String get nextStatusAction {
    switch (status) {
      case 'DriverAccepted': return 'DriverArriving';
      case 'DriverArriving': return 'DriverArrived';
      case 'DriverArrived': return 'InProgress';
      case 'InProgress': return 'Completed';
      default: return '';
    }
  }

  String get nextStatusLabel {
    switch (status) {
      case 'DriverAccepted': return '🚗 Bắt đầu đến đón';
      case 'DriverArriving': return '📍 Đã đến điểm đón';
      case 'DriverArrived': return '▶️ Bắt đầu chạy';
      case 'InProgress': return '✅ Hoàn thành chuyến';
      default: return '';
    }
  }
}

// ── API Service ────────────────────────────────────────────────
class ApiService {
  // IP máy chạy API, truyền lúc build: flutter run --dart-define=API_HOST=192.168.x.x
  // (script run-mobile.ps1 ở thư mục gốc tự dò IP và truyền vào).
  // Không truyền: web dùng host của trang, Android emulator dùng 10.0.2.2.
  static const String _apiHost = String.fromEnvironment('API_HOST');
  static const String _apiPort = String.fromEnvironment('API_PORT', defaultValue: '5270');
  static final String baseUrl = 'http://${_resolveHost()}:$_apiPort/api/v1';

  static String _resolveHost() {
    if (_apiHost.isNotEmpty) return _apiHost;
    if (kIsWeb) return Uri.base.host;
    return '10.0.2.2';
  }
  static String? _token;
  static String? _refreshToken;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
  }

  static Future<void> saveTokens(String access, String refresh) async {
    _token = access;
    _refreshToken = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  static Future<void> clearTokens() async {
    _token = null;
    _refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_json');
  }

  static String? getToken() => _token;

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Map<String, dynamic> _decode(http.Response res) {
    final body = utf8.decode(res.bodyBytes).trim();
    if (body.isEmpty) return {'success': false, 'message': 'Empty response'};
    try {
      return jsonDecode(body);
    } catch (_) {
      return {'success': false, 'message': 'Invalid JSON response'};
    }
  }

  /// Refresh token đang chạy dở (gộp các lệnh gọi song song bị 401 cùng lúc thành 1 lần refresh).
  static Future<bool>? _refreshing;

  /// Làm mới access token bằng refresh token đã lưu. true nếu thành công.
  static Future<bool> _refreshAccessToken() {
    return _refreshing ??= () async {
      final rt = _refreshToken;
      if (rt == null || rt.isEmpty) return false;
      try {
        final res = await http.post(
          Uri.parse('$baseUrl/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': rt}),
        );
        final data = _decode(res);
        if (res.statusCode == 200 && data['success'] == true) {
          final d = data['data'];
          if (d != null && d['accessToken'] != null && d['refreshToken'] != null) {
            await saveTokens(d['accessToken'], d['refreshToken']);
            return true;
          }
        }
      } catch (_) {}
      return false;
    }()
      ..whenComplete(() => _refreshing = null);
  }

  /// Gửi request có xác thực; nếu bị 401 (token hết hạn) thì tự refresh rồi thử lại đúng 1 lần.
  static Future<http.Response> _send(Future<http.Response> Function() request) async {
    var res = await request();
    if (res.statusCode == 401 && _refreshToken != null) {
      if (await _refreshAccessToken()) res = await request();
    }
    return res;
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await _send(() => http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    ));
    return _decode(res);
  }

  static Future<Map<String, dynamic>> get(String path) async {
    final res = await _send(() => http.get(Uri.parse('$baseUrl$path'), headers: _headers));
    return _decode(res);
  }

  static Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final res = await _send(() => http.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    ));
    return _decode(res);
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final res = await _send(() => http.delete(Uri.parse('$baseUrl$path'), headers: _headers));
    return _decode(res);
  }

  // Auth
  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String phone,
    required String password,
    String role = 'CUSTOMER',
  }) => post('/auth/register', {
    'fullName': fullName,
    'phone': phone,
    'password': password,
    'role': role,
  });

  static Future<Map<String, dynamic>> login(String phone, String password) =>
      post('/auth/login', {'phone': phone, 'password': password});

  static Future<Map<String, dynamic>> logout() =>
      post('/auth/logout', {'refreshToken': _refreshToken ?? ''});

  static Future<Map<String, dynamic>> updateUserProfile(Map<String, dynamic> data) => put('/auth/profile', data);
  static Future<Map<String, dynamic>> changeUserPassword(String current, String newPw) => put('/auth/password', {'currentPassword': current, 'newPassword': newPw});
  static Future<Map<String, dynamic>> getMe() => get('/auth/me');

  // Customer Vehicles
  static Future<Map<String, dynamic>> getCustomerVehicles() => get('/customer/vehicles');
  static Future<Map<String, dynamic>> addCustomerVehicle(Map<String, dynamic> data) => post('/customer/vehicles', data);
  static Future<Map<String, dynamic>> deleteCustomerVehicle(int id) => delete('/customer/vehicles/$id');

  // Maps (proxy qua backend, dịch vụ OSM miễn phí)
  static Future<Map<String, dynamic>> _safeGet(String path) async {
    try {
      return await get(path);
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  static Future<List<PlaceSuggestion>> mapsAutocomplete(String input,
      {double? lat, double? lng, String? sessionToken}) async {
    final q = <String, String>{
      'input': input,
      if (lat != null) 'lat': '$lat',
      if (lng != null) 'lng': '$lng',
      'sessionToken': ?sessionToken,
    };
    final res = await _safeGet('/maps/autocomplete?${Uri(queryParameters: q).query}');
    final data = res['data'];
    if (res['success'] == true && data is List) {
      return data.map((x) => PlaceSuggestion.fromJson(Map<String, dynamic>.from(x))).toList();
    }
    return [];
  }

  static Future<GeoPlace?> mapsPlace(String placeId, {String? sessionToken}) async {
    final q = sessionToken != null ? '?${Uri(queryParameters: {'sessionToken': sessionToken}).query}' : '';
    final res = await _safeGet('/maps/place/${Uri.encodeComponent(placeId)}$q');
    if (res['success'] == true && res['data'] is Map) {
      return GeoPlace.fromJson(Map<String, dynamic>.from(res['data']));
    }
    return null;
  }

  static Future<GeoPlace?> reverseGeocode(double lat, double lng) async {
    final res = await _safeGet('/maps/reverse-geocode?lat=$lat&lng=$lng');
    if (res['success'] == true && res['data'] is Map) {
      final p = GeoPlace.fromJson(Map<String, dynamic>.from(res['data']));
      if (p.address.isNotEmpty) return p;
    }
    return null;
  }

  static Future<RouteInfo?> mapsRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String mode = 'DRIVE',
  }) async {
    try {
      final res = await post('/maps/route', {
        'originLatitude': originLat,
        'originLongitude': originLng,
        'destinationLatitude': destLat,
        'destinationLongitude': destLng,
        'mode': mode,
      });
      if (res['success'] == true && res['data'] is Map) {
        return RouteInfo.fromJson(Map<String, dynamic>.from(res['data']));
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> mapsStatus() async {
    final res = await _safeGet('/maps/status');
    final data = res['data'];
    return res['success'] == true && data is Map && data['provider'] != null;
  }

  // Bookings
  // estimateFare: gửi pickupLatitude/pickupLongitude/destinationLatitude/destinationLongitude
  // (+ vehicleType, transmission). createBooking: thêm pickupAddress/destinationAddress.
  static Future<Map<String, dynamic>> estimateFare(Map<String, dynamic> data) => post('/bookings/estimate', data);
  static Future<Map<String, dynamic>> createBooking(Map<String, dynamic> data) => post('/bookings', data);
  static Future<Map<String, dynamic>> getAvailableVouchers() => get('/bookings/vouchers');
  static Future<Map<String, dynamic>> retryDriverSearch(int bookingId) => post('/bookings/$bookingId/retry-search', {});
  static Future<Map<String, dynamic>> checkVoucher(String code, double orderAmount) =>
      post('/bookings/vouchers/check', {'code': code, 'orderAmount': orderAmount});
  static Future<Map<String, dynamic>> getActiveBooking() => get('/bookings/active');
  static Future<Map<String, dynamic>> getBookingById(int id) => get('/bookings/$id');
  static Future<Map<String, dynamic>> rateDriver(int bookingId, int score, String comment) => post('/bookings/$bookingId/rate', {'score': score, 'comment': comment});
  static Future<Map<String, dynamic>> cancelBooking(int id, String reason) => post('/bookings/$id/cancel', {'reason': reason});
  static Future<Map<String, dynamic>> getCustomerHistory() => get('/bookings/customer-history');

  // Driver
  static Future<Map<String, dynamic>> getDriverProfile() => get('/driver/profile');
  static Future<Map<String, dynamic>> updateDriverProfile(Map<String, dynamic> data) => put('/driver/profile', data);
  static Future<Map<String, dynamic>> changePassword(String current, String newPw) =>
      post('/driver/change-password', {'currentPassword': current, 'newPassword': newPw});
  // Driver Booking
  static Future<Map<String, dynamic>> toggleDriverStatus(bool isOnline, {double? latitude, double? longitude}) =>
      post('/driver/toggle-status', {
        'isOnline': isOnline,
        if (latitude != null && longitude != null) 'latitude': latitude,
        if (latitude != null && longitude != null) 'longitude': longitude,
      });
  static Future<Map<String, dynamic>> updateDriverLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    double? speedKmh,
    double? heading,
  }) => post('/driver/location', {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': ?accuracyMeters,
    'speedKmh': ?speedKmh,
    'heading': ?heading,
  });
  static Future<Map<String, dynamic>> getDriverPendingBookings() =>
      get('/driver/pending-bookings');
  static Future<Map<String, dynamic>> acceptBooking(int id) =>
      post('/driver/bookings/$id/accept', {});
  static Future<Map<String, dynamic>> rejectBooking(int id) =>
      post('/driver/bookings/$id/reject', {});
  static Future<Map<String, dynamic>> updateBookingStatus(int id, String status) =>
      post('/driver/bookings/$id/update-status', {'status': status});
  static Future<Map<String, dynamic>> cancelBookingByDriver(int id, String reason) =>
      post('/driver/bookings/$id/cancel', {'reason': reason});
  static Future<Map<String, dynamic>> getDriverActiveBooking() =>
      get('/driver/bookings/active');
  /// period: day | week | month; date: ngày bất kỳ trong kỳ (giờ VN)
  static Future<Map<String, dynamic>> getDriverEarnings(String period, DateTime date) =>
      get('/driver/earnings?period=$period&date=${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
  static Future<Map<String, dynamic>> getDriverHistory({int page = 1}) =>
      get('/driver/bookings/history?page=$page');

}
