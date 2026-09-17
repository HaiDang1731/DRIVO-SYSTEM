import 'dart:convert';
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

  String get displayName {
    final name = '${brand ?? ""} ${model ?? ""}'.trim();
    return name.isEmpty ? licensePlate : '$name ($licensePlate)';
  }
}

class FareEstimate {
  final double estimatedDistanceKm;
  final int estimatedDurationMin;
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double nightSurcharge;
  final double totalEstimatedFare;

  FareEstimate({
    required this.estimatedDistanceKm,
    required this.estimatedDurationMin,
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.nightSurcharge,
    required this.totalEstimatedFare,
  });

  factory FareEstimate.fromJson(Map<String, dynamic> j) => FareEstimate(
    estimatedDistanceKm: (j['estimatedDistanceKm'] as num).toDouble(),
    estimatedDurationMin: j['estimatedDurationMin'],
    baseFare: (j['baseFare'] as num).toDouble(),
    distanceFare: (j['distanceFare'] as num).toDouble(),
    timeFare: (j['timeFare'] as num).toDouble(),
    nightSurcharge: (j['nightSurcharge'] as num).toDouble(),
    totalEstimatedFare: (j['totalEstimatedFare'] as num).toDouble(),
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
  final String? customerNote;

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
    this.customerNote,
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
      createdAt: DateTime.parse(j['createdAt']),
      vehicleInfo: vInfo,
      driverName: d != null ? d['fullName'] : null,
      driverPhone: d != null ? d['phone'] : null,
      customerNote: j['customerNote'],
    );
  }

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

// ── API Service ────────────────────────────────────────────────
class ApiService {
  static const String baseUrl = 'http://192.168.110.65:5270/api/v1';
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

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static Future<Map<String, dynamic>> get(String path) async {
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final res = await http.delete(Uri.parse('$baseUrl$path'), headers: _headers);
    return jsonDecode(utf8.decode(res.bodyBytes));
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

  static Future<Map<String, dynamic>> getMe() => get('/auth/me');

  // Customer Vehicles
  static Future<Map<String, dynamic>> getCustomerVehicles() => get('/customer/vehicles');
  static Future<Map<String, dynamic>> addCustomerVehicle(Map<String, dynamic> data) => post('/customer/vehicles', data);
  static Future<Map<String, dynamic>> deleteCustomerVehicle(int id) => delete('/customer/vehicles/$id');

  // Bookings
  static Future<Map<String, dynamic>> estimateFare(Map<String, dynamic> data) => post('/bookings/estimate', data);
  static Future<Map<String, dynamic>> createBooking(Map<String, dynamic> data) => post('/bookings', data);
  static Future<Map<String, dynamic>> getActiveBooking() => get('/bookings/active');
  static Future<Map<String, dynamic>> cancelBooking(int id, String reason) => post('/bookings/$id/cancel', {'reason': reason});
  static Future<Map<String, dynamic>> getCustomerHistory() => get('/bookings/customer-history');

  // Driver
  static Future<Map<String, dynamic>> getDriverProfile() => get('/driver/profile');
  static Future<Map<String, dynamic>> updateDriverProfile(Map<String, dynamic> data) => put('/driver/profile', data);
  static Future<Map<String, dynamic>> changePassword(String current, String newPw) =>
      post('/driver/change-password', {'currentPassword': current, 'newPassword': newPw});
}
