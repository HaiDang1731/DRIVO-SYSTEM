import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/api_service.dart';
import '../../../../core/drivo_map.dart';
import '../../../../core/geo_utils.dart';
import '../../../../core/location_service.dart';
import '../../../../core/tracking_service.dart';
import '../../../../core/widgets/trip_cancel_wait.dart';
import '../../profile/customer_account_screens.dart' show PaymentPreference;

/// Màn hình Đặt chuyến DRIVO
class CustomerBookingScreen extends StatefulWidget {
  final AuthUser user;
  final BookingDetail? initialActiveBooking;
  /// Mã khách chọn từ Home; tự áp khi đã có giá ước tính.
  final String? initialVoucherCode;

  const CustomerBookingScreen({
    super.key,
    required this.user,
    this.initialActiveBooking,
    this.initialVoucherCode,
  });

  @override
  State<CustomerBookingScreen> createState() => _CustomerBookingScreenState();
}

/// Đang chọn điểm nào bằng cách kéo bản đồ.
enum _PickTarget { pickup, destination }

class _CustomerBookingScreenState extends State<CustomerBookingScreen>
    with SingleTickerProviderStateMixin {
  // Điểm đón (mặc định = vị trí GPS hiện tại) & điểm đến (toạ độ thật)
  String _pickupAddress = 'Đang xác định vị trí của bạn...';
  LatLng? _pickupLatLng;
  String _destinationAddress = '';
  LatLng? _destinationLatLng;
  bool get _hasDestination => _destinationLatLng != null;

  // Tính năng độc quyền DRIVO: Cho phép mang xe điện gấp
  bool _allowFoldingScooter = true;

  // Dịch vụ và phương thức
  String _paymentMethod = 'Tiền mặt';
  String _customerNote = '';

  // Voucher đã áp: mã + số tiền giảm tính theo giá ước tính hiện tại
  String? _voucherCode;
  double _voucherDiscount = 0;
  late String? _pendingVoucherCode = widget.initialVoucherCode;

  static const Map<String, String> _paymentMethodApi = {
    'Tiền mặt': 'Cash',
    'Ví điện tử': 'MockEwallet',
    'Chuyển khoản QR': 'MockBanking',
  };

  // Quản lý xe
  List<CustomerVehicle> _vehicles = [];
  CustomerVehicle? _selectedVehicle;

  // Giá & tính toán cước
  FareEstimate? _estimate;
  bool _loadingEstimate = false;
  int _estimateSeq = 0;

  // Trạng thái chuyến đi
  BookingDetail? _activeBooking;
  bool _submitting = false;

  // Bản đồ
  DrivoMapController? _mapCtrl;
  LatLng _cameraTarget = kDefaultMapCenter;
  DrivoMapStyle _mapStyle = DrivoMapStyle.standard;
  LatLng? _myLocation;
  bool _hasLocationPermission = false;
  _PickTarget? _picking;
  String _pickingAddress = '';
  bool _pickingResolving = false;
  int _reverseSeq = 0;

  // Theo dõi tài xế realtime (SignalR) + fallback polling
  LatLng? _driverLatLng;
  int? _joinedBookingId;
  bool _fittedForBooking = false;
  StreamSubscription<DriverLocationEvent>? _locSub;
  StreamSubscription<BookingStatusEvent>? _statusSub;
  DateTime _lastPoll = DateTime.fromMillisecondsSinceEpoch(0);

  // Animation radar tìm tài xế
  late AnimationController _radarController;

  Timer? _pollingTimer;

  // Chiều cao ước lượng của phần UI phủ trên bản đồ (để căn khung camera)
  static const double _overlayTop = 230;
  static const double _overlayBottom = 400;

  @override
  void initState() {
    super.initState();
    _activeBooking = widget.initialActiveBooking;
    // Phương thức thanh toán mặc định chọn ở tab Tài khoản
    PaymentPreference.get().then((m) {
      if (mounted) setState(() => _paymentMethod = m);
    });
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();


    _locSub = TrackingService.instance.driverLocations.listen(_onDriverLocation);
    _statusSub = TrackingService.instance.bookingStatusChanges.listen(_onBookingStatus);

    _loadVehicles();
    if (_activeBooking != null) {
      _syncTrackingGroup();
      _startPolling();
      _applyBookingDriverLocation(_activeBooking!);
      _initMyLocation(setAsPickup: false);
    } else {
      _initMyLocation(setAsPickup: true);
    }
  }

  @override
  void dispose() {
    _radarController.dispose();
    _searchTicker?.cancel();
    _pollingTimer?.cancel();
    _locSub?.cancel();
    _statusSub?.cancel();
    if (_joinedBookingId != null) {
      TrackingService.instance.leaveBooking(_joinedBookingId!);
    }
    super.dispose();
  }

  // ── Vị trí hiện tại ─────────────────────────────────────────
  Future<void> _initMyLocation({required bool setAsPickup}) async {
    final r = await LocationService.getCurrent();
    if (!mounted) return;
    if (!r.ok) {
      if (setAsPickup) {
        // Không có GPS -> tâm Hà Nội, khách tự chọn điểm đón.
        setState(() {
          _pickupAddress = 'Chạm để chọn điểm đón';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.error ?? 'Không lấy được vị trí'), backgroundColor: const Color(0xFFF59E0B)),
        );
      }
      return;
    }
    final here = LatLng(r.position!.latitude, r.position!.longitude);
    setState(() {
      _hasLocationPermission = true;
      _myLocation = LatLng(r.position!.latitude, r.position!.longitude);
    });
    if (!setAsPickup) return;
    setState(() {
      _pickupLatLng = here;
      _pickupAddress = 'Vị trí hiện tại của bạn';
    });
    _moveCamera(here, zoom: 16);
    final place = await ApiService.reverseGeocode(here.latitude, here.longitude);
    if (!mounted) return;
    if (place != null && _pickupLatLng == here) {
      setState(() => _pickupAddress = place.address);
    }
    _fetchEstimate();
  }

  Future<void> _goToMyLocation() async {
    final r = await LocationService.getCurrent(timeout: const Duration(seconds: 8));
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.error ?? 'Không lấy được vị trí'),
        backgroundColor: const Color(0xFFF59E0B),
        action: SnackBarAction(label: 'Cài đặt', onPressed: LocationService.openSettings),
      ));
      return;
    }
    setState(() {
      _hasLocationPermission = true;
      _myLocation = LatLng(r.position!.latitude, r.position!.longitude);
    });
    _moveCamera(LatLng(r.position!.latitude, r.position!.longitude), zoom: 16);
  }

  void _moveCamera(LatLng target, {double? zoom}) {
    _cameraTarget = target;
    _mapCtrl?.move(target, zoom: zoom);
  }

  /// Căn camera để các điểm nằm trong vùng nhìn thấy (giữa header và bottom sheet).
  Future<void> _fitVisible(List<LatLng> points) async {
    final c = _mapCtrl;
    if (c == null || points.isEmpty) return;
    if (points.length == 1) {
      _moveCamera(points.first, zoom: 15);
      return;
    }
    final b = GeoUtils.boundsOf(points);
    if (b == null) return;
    final h = MediaQuery.of(context).size.height;
    final visible = (h - _overlayTop - _overlayBottom).clamp(120.0, h);
    final span = b.northEast.latitude - b.southWest.latitude;
    final total = span * h / visible;
    final north = b.northEast.latitude + total * _overlayTop / h;
    final south = b.southWest.latitude - total * _overlayBottom / h;
    final lngPad = (b.northEast.longitude - b.southWest.longitude) * 0.12;
    c.fitBounds(
      LatLngBounds(
        LatLng(south, b.southWest.longitude - lngPad),
        LatLng(north, b.northEast.longitude + lngPad),
      ),
      padding: 16,
    );
  }

  void _fitRoute() {
    final pts = <LatLng>[
      ?_pickupLatLng,
      ?_destinationLatLng,
      ...GeoUtils.decodePolyline(_estimate?.routePolyline),
    ];
    _fitVisible(pts);
  }

  // ── Xe của khách ────────────────────────────────────────────
  Future<void> _loadVehicles() async {
    try {
      final res = await ApiService.getCustomerVehicles();
      if (res['success'] == true && res['data'] != null) {
        final list = (res['data'] as List).map((x) => CustomerVehicle.fromJson(x)).toList();
        if (mounted) {
          setState(() {
            _vehicles = list;
            _selectedVehicle = list.isNotEmpty
                ? list.firstWhere((v) => v.isDefault, orElse: () => list.first)
                : null;
          });
        }
      }
    } catch (_) {}
  }

  // ── Ước tính cước (gửi toạ độ thật) ─────────────────────────
  Future<void> _fetchEstimate() async {
    final p = _pickupLatLng;
    final d = _destinationLatLng;
    if (p == null || d == null) {
      setState(() => _estimate = null);
      return;
    }
    final seq = ++_estimateSeq;
    setState(() => _loadingEstimate = true);
    try {
      final res = await ApiService.estimateFare({
        'pickupLatitude': p.latitude,
        'pickupLongitude': p.longitude,
        'destinationLatitude': d.latitude,
        'destinationLongitude': d.longitude,
        'vehicleType': _selectedVehicle?.vehicleType ?? 'Car',
        'transmission': _selectedVehicle?.transmission ?? 'Automatic',
      });
      if (!mounted || seq != _estimateSeq) return;
      if (res['success'] == true && res['data'] != null) {
        setState(() {
          _estimate = FareEstimate.fromJson(res['data']);
          _loadingEstimate = false;
        });
        _fitRoute();
        // Giá đổi (đổi điểm đến/xe) -> tính lại số tiền giảm của voucher đang áp
        if (_voucherCode != null) {
          _applyVoucher(_voucherCode!, silent: true);
        } else if (_pendingVoucherCode != null) {
          _applyPendingVoucher();
        }
      } else {
        setState(() {
          _estimate = null;
          _loadingEstimate = false;
        });
      }
    } catch (_) {
      if (mounted && seq == _estimateSeq) {
        setState(() {
          _estimate = null;
          _loadingEstimate = false;
        });
      }
    }
  }

  Future<void> _createBooking() async {
    if (_submitting) return;
    if (_pickupLatLng == null || _destinationLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn điểm đón và điểm đến trên bản đồ'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      if (_pickupLatLng == null) {
        _showPlaceSearchSheet(_PickTarget.pickup);
      } else {
        _showPlaceSearchSheet(_PickTarget.destination);
      }
      return;
    }
    if (_selectedVehicle == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn hoặc thêm xe của bạn để tiếp tục'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      _showVehicleSelectorSheet();
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await ApiService.createBooking({
        'pickupAddress': _pickupAddress,
        'pickupLatitude': _pickupLatLng!.latitude,
        'pickupLongitude': _pickupLatLng!.longitude,
        'destinationAddress': _destinationAddress,
        'destinationLatitude': _destinationLatLng!.latitude,
        'destinationLongitude': _destinationLatLng!.longitude,
        'customerVehicleId': _selectedVehicle!.id,
        'customerNote': '$_customerNote | Xe điện gấp: ${_allowFoldingScooter ? "Có" : "Không"}',
        'paymentMethod': _paymentMethodApi[_paymentMethod] ?? 'Cash',
        'voucherCode': ?_voucherCode,
      });

      if (res['success'] == true && res['data'] != null) {
        final booking = BookingDetail.fromJson(res['data']);
        if (mounted) {
          setState(() {
            _activeBooking = booking;
            _submitting = false;
            _driverLatLng = null;
            _fittedForBooking = false;
            _voucherCode = null;
            _voucherDiscount = 0;
          });
          _syncTrackingGroup();
          _startPolling();
          _fitBooking(booking);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã gửi yêu cầu chuyến đi #${booking.bookingCode}!'),
              backgroundColor: const Color(0xFF0070E0),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'Đặt chuyến thất bại'),
              backgroundColor: const Color(0xFFE53935),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: const Color(0xFFE53935)),
        );
      }
    }
  }

  // ── Theo dõi chuyến: SignalR + polling ──────────────────────
  void _syncTrackingGroup() {
    final id = _activeBooking?.id;
    if (_joinedBookingId == id) return;
    if (_joinedBookingId != null) {
      TrackingService.instance.leaveBooking(_joinedBookingId!);
    }
    _joinedBookingId = id;
    if (id != null) TrackingService.instance.joinBooking(id);
  }

  void _onDriverLocation(DriverLocationEvent e) {
    final b = _activeBooking;
    if (!mounted || b == null) return;
    final match = e.bookingId != null ? e.bookingId == b.id : (b.driverId != null && e.driverId == b.driverId);
    if (!match) return;
    final first = _driverLatLng == null;
    setState(() => _driverLatLng = LatLng(e.latitude, e.longitude));
    if (first) _fitBooking(b);
  }

  void _onBookingStatus(BookingStatusEvent e) {
    if (!mounted || _activeBooking == null || e.bookingId != _activeBooking!.id) return;
    _pollActiveBooking(force: true);
  }

  void _applyBookingDriverLocation(BookingDetail b) {
    if (!b.hasDriverCoords) return;
    // Khi hub đang kết nối, vị trí realtime mới hơn -> chỉ dùng dữ liệu polling nếu chưa có.
    if (_driverLatLng == null || !TrackingService.instance.isConnected) {
      _driverLatLng = LatLng(b.driverLatitude!, b.driverLongitude!);
    }
  }

  void _fitBooking(BookingDetail b) {
    final pts = <LatLng>[
      if (b.hasPickupCoords) LatLng(b.pickupLatitude!, b.pickupLongitude!),
      if (b.hasDestinationCoords) LatLng(b.destinationLatitude!, b.destinationLongitude!),
      ?_driverLatLng,
    ];
    if (pts.isNotEmpty) {
      _fittedForBooking = true;
      _fitVisible(pts);
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollActiveBooking());
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _endTracking() {
    _stopPolling();
    if (_joinedBookingId != null) {
      TrackingService.instance.leaveBooking(_joinedBookingId!);
      _joinedBookingId = null;
    }
    _driverLatLng = null;
    _fittedForBooking = false;
  }

  Future<void> _pollActiveBooking({bool force = false}) async {
    if (!mounted || _activeBooking == null) return;
    // Hub đang kết nối -> giãn polling còn 15 s (chỉ làm dự phòng).
    if (!force &&
        TrackingService.instance.isConnected &&
        DateTime.now().difference(_lastPoll) < const Duration(seconds: 15)) {
      return;
    }
    _lastPoll = DateTime.now();

    // Poll by booking ID to detect Completed status
    Map<String, dynamic> res;
    try {
      res = await ApiService.getBookingById(_activeBooking!.id);
    } catch (_) {
      return; // lỗi mạng tạm thời -> giữ nguyên, lần sau thử lại
    }
    if (!mounted || _activeBooking == null) return;
    if (res['success'] == true && res['data'] != null) {
      final updated = BookingDetail.fromJson(res['data']);
      if (updated.status == 'Cancelled') {
        setState(() {
          _activeBooking = null;
          _endTracking();
        });
        _showTripNotice(
          icon: Icons.cancel_rounded,
          color: const Color(0xFFEF4444),
          title: updated.cancelledBy == 'DRIVER' ? 'Tài xế đã hủy chuyến' : 'Chuyến đi đã bị hủy',
          message: updated.cancellationReason != null
              ? 'Lý do: ${updated.cancellationReason}'
              : 'Chuyến đi của bạn đã bị hủy.',
        );
      } else if (updated.status == 'Completed') {
        _endTracking();
        _showRatingDialog(updated);
      } else {
        final statusChanged = updated.status != _activeBooking!.status;
        // Tài xế vừa xác nhận tiếp tục chờ (đã hết thời gian chờ miễn phí) -> báo khách phí chờ đang tính
        if (updated.waitExtendedAt != null && _activeBooking!.waitExtendedAt == null) {
          _showTripNotice(
            icon: Icons.timer_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Tài xế tiếp tục chờ bạn',
            message: updated.waitingPricePerMin > 0
                ? 'Đã hết ${updated.freeWaitingMin} phút chờ miễn phí. Phí chờ ${_formatCurrency(updated.waitingPricePerMin)}/phút đang được tính, bạn ra điểm đón sớm nhé.'
                : 'Tài xế đang chờ bạn tại điểm đón, bạn ra sớm nhé.',
          );
        }
        setState(() {
          _activeBooking = updated;
          _applyBookingDriverLocation(updated);
        });
        _syncTrackingGroup();
        if (!_fittedForBooking || statusChanged) _fitBooking(updated);
      }
    } else {
      setState(() {
        _activeBooking = null;
        _endTracking();
      });
    }
  }

  Future<void> _callDriver(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Số tài xế: $phone')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Số tài xế: $phone')));
      }
    }
  }

  // ── Chờ tài xế quá lâu ──────────────────────────────────────
  static const Duration _searchWaitLimit = Duration(minutes: 5);
  /// Sau mốc này mới hiện thông báo "không tìm được tài xế" (đẩy lùi khi khách bấm Đợi thêm / Làm mới).
  DateTime? _noDriverNoticeAfter;
  bool _retryingSearch = false;
  Timer? _searchTicker;

  bool _isSearching(BookingDetail b) => b.status == 'SearchingDriver' || b.status == 'Pending';

  /// Cập nhật giao diện mỗi 10 giây khi đang tìm tài xế (thời gian đã chờ + thông báo); tự dừng khi hết tìm.
  void _ensureSearchTicker() {
    if (_searchTicker != null) return;
    _searchTicker = Timer.periodic(const Duration(seconds: 10), (t) {
      if (!mounted) return t.cancel();
      final b = _activeBooking;
      if (b == null || !_isSearching(b)) {
        t.cancel();
        _searchTicker = null;
        _noDriverNoticeAfter = null;
        return;
      }
      setState(() {});
    });
  }

  String _searchElapsedText(BookingDetail b) {
    final min = DateTime.now().difference(b.createdAt).inMinutes;
    return min >= 1 ? ' (đã tìm $min phút)' : '';
  }

  bool _showNoDriverNotice(BookingDetail b) {
    if (!_isSearching(b)) return false;
    final after = _noDriverNoticeAfter ?? b.createdAt.add(_searchWaitLimit);
    return DateTime.now().isAfter(after);
  }

  Future<void> _retryDriverSearch(BookingDetail b) async {
    if (_retryingSearch) return;
    setState(() => _retryingSearch = true);
    Map<String, dynamic> res;
    try {
      res = await ApiService.retryDriverSearch(b.id);
    } catch (_) {
      res = {'success': false, 'message': 'Không kết nối được máy chủ, vui lòng thử lại.'};
    }
    if (!mounted) return;
    setState(() {
      _retryingSearch = false;
      if (res['success'] == true) _noDriverNoticeAfter = DateTime.now().add(_searchWaitLimit);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['message']?.toString() ?? 'Đã tìm lại tài xế'),
      backgroundColor: res['success'] == true ? const Color(0xFF0070E0) : const Color(0xFFE53935),
    ));
  }

  Widget _buildNoDriverNotice(BookingDetail b) {
    final buttonStyle = ButtonStyle(
      // Theme đặt minimumSize width = infinity -> nút trong Row phải tự đặt lại
      minimumSize: WidgetStateProperty.all(const Size(0, 40)),
      padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12)),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFFEA580C), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Không tìm được tài xế, vui lòng đợi thêm hoặc làm mới',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF9A3412)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: buttonStyle.copyWith(
                    side: WidgetStateProperty.all(const BorderSide(color: Color(0xFFFDBA74))),
                  ),
                  onPressed: _retryingSearch
                      ? null
                      : () => setState(() => _noDriverNoticeAfter = DateTime.now().add(_searchWaitLimit)),
                  child: Text('Đợi thêm',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF9A3412))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: buttonStyle.copyWith(
                    backgroundColor: WidgetStateProperty.all(const Color(0xFFEA580C)),
                    elevation: WidgetStateProperty.all(0),
                  ),
                  onPressed: _retryingSearch ? null : () => _retryDriverSearch(b),
                  child: _retryingSearch
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Làm mới',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Đóng hộp đánh giá; màn đặt xe được đóng sau khi hộp đóng xong (xem _showRatingDialog).
  void _closeAfterTrip(BuildContext sheetContext) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(sheetContext);
  }

  Future<void> _showRatingDialog(BookingDetail completedBooking) async {
    int rating = 5;
    final commentController = TextEditingController();
    bool isSubmitting = false;

    // Đóng hộp đánh giá và màn đặt xe cùng 1 lúc (nhất là khi bàn phím đang mở) làm Flutter
    // báo lỗi '_dependents.isEmpty' -> chờ hộp đóng hẳn rồi mới quay về Home.
    await _showRatingSheet(completedBooking, rating, commentController, isSubmitting);
    await Future.delayed(const Duration(milliseconds: 350));
    commentController.dispose();
    if (!mounted) return;
    setState(() => _activeBooking = null);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _showRatingSheet(
      BookingDetail completedBooking, int rating, TextEditingController commentController, bool isSubmitting) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          // Bàn phím mở -> nội dung cao hơn chỗ trống, phải cuộn được (trước bị tràn).
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 64),
                const SizedBox(height: 12),
                const Text('Chuyến đi đã hoàn thành!',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Vui lòng đánh giá tài xế của bạn',
                    style: TextStyle(color: Colors.white60, fontSize: 14)),
                const SizedBox(height: 16),
                _buildFinalFareBreakdown(completedBooking),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => GestureDetector(
                    onTap: () => setModalState(() => rating = i + 1),
                    child: Icon(
                      i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: const Color(0xFFFACC15),
                      size: 44,
                    ),
                  )),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Nhận xét thêm (không bắt buộc)...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setModalState(() => isSubmitting = true);
                      try {
                        await ApiService.rateDriver(
                            completedBooking.id, rating, commentController.text);
                      } catch (_) {}
                      if (mounted && ctx.mounted) {
                        _closeAfterTrip(ctx);
                        messenger.showSnackBar(const SnackBar(
                          content: Text('Cảm ơn bạn đã đánh giá!'),
                          backgroundColor: Color(0xFF22C55E),
                        ));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: isSubmitting
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('Gửi Đánh Giá',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _closeAfterTrip(ctx),
                  child: const Text('Bỏ qua', style: TextStyle(color: Colors.white38)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Thông báo nổi bật trên màn khách (tài xế hủy / tài xế tiếp tục chờ).
  void _showTripNotice({required IconData icon, required Color color, required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: Icon(icon, color: color, size: 40),
        title: Text(title, textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
        content: Text(message, textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF475569))),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0070E0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text('Đã hiểu', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelBooking() async {
    final b = _activeBooking;
    if (b == null || _submitting) return;
    final hasDriver = b.driverName != null;
    final choice = await showCancelReasonSheet(
      context,
      title: 'Bạn muốn hủy chuyến?',
      subtitle: 'Cho DRIVO biết lý do để phục vụ bạn tốt hơn.',
      reasons: [
        const CancelReason('CHANGE_PLAN', 'Thay đổi kế hoạch'),
        if (hasDriver) const CancelReason('WAIT_TOO_LONG', 'Chờ tài xế quá lâu'),
        const CancelReason('WRONG_ADDRESS', 'Đặt nhầm địa chỉ'),
        if (hasDriver) const CancelReason('DRIVER_ASKED', 'Tài xế yêu cầu tôi hủy'),
        const CancelReason('OTHER', 'Lý do khác'),
      ],
    );
    if (choice == null || !mounted || _activeBooking?.id != b.id) return;
    setState(() => _submitting = true);
    try {
      final res = await ApiService.cancelBooking(b.id, choice.code, choice.note);
      if (res['success'] == true) {
        if (mounted) {
          setState(() {
            _activeBooking = null;
            _submitting = false;
          });
          _stopPolling();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã hủy chuyến đi thành công')),
          );
        }
      } else {
        if (mounted) {
          setState(() => _submitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Không hủy được chuyến'), backgroundColor: const Color(0xFFE53935)),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Bảng phí sau khi hoàn thành (nền tối trong sheet đánh giá).
  Widget _buildFinalFareBreakdown(BookingDetail b) {
    Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: bold ? 16 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
    final finalPrice = b.finalPrice ??
        (b.estimatedPrice + b.pickupFee + b.waitingFee + b.extraDistanceFee - b.discount);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          row('Cước chuyến', _formatCurrency(b.estimatedPrice)),
          if (b.pickupFee > 0)
            row('Phí đón${b.pickupDistanceKm != null ? ' (${b.pickupDistanceKm!.toStringAsFixed(1)} km)' : ''}',
                _formatCurrency(b.pickupFee)),
          if (b.waitingFee > 0) row('Phí chờ', _formatCurrency(b.waitingFee)),
          if (b.extraDistanceFee > 0)
            row('Phụ phí quãng đường${b.actualDistanceKm != null ? ' (thực tế ${b.actualDistanceKm!.toStringAsFixed(1)} km)' : ''}',
                _formatCurrency(b.extraDistanceFee)),
          if (b.discount > 0) row('Giảm giá', '-${_formatCurrency(b.discount)}', color: const Color(0xFF22C55E)),
          const Divider(color: Colors.white24, height: 16),
          row('Tổng thanh toán', _formatCurrency(finalPrice), bold: true, color: const Color(0xFF60A5FA)),
        ],
      ),
    );
  }

  String _formatCurrency(double amount) {
    return '${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"),
      (m) => "${m[1]}.",
    )}đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          // 1. Bản đồ OpenStreetMap: điểm đón/đến, lộ trình, vị trí tài xế
          Positioned.fill(
            child: DrivoMap(
              initialTarget: _pickupLatLng ?? _cameraTarget,
              initialZoom: 15,
              style: _mapStyle,
              markers: _buildMarkers(),
              polylines: _buildPolylines(),
              myLocation: _hasLocationPermission ? _myLocation : null,
              onMapCreated: (c) {
                _mapCtrl = c;
                if (_activeBooking != null) {
                  _fitBooking(_activeBooking!);
                } else if (_hasDestination) {
                  _fitRoute();
                } else if (_pickupLatLng != null) {
                  _moveCamera(_pickupLatLng!, zoom: 16);
                }
              },
              onCameraMove: (center) => _cameraTarget = center,
              onCameraIdle: _onCameraIdle,
            ),
          ),

          // 1b. Ghim giữa màn hình khi chọn điểm trên bản đồ
          if (_picking != null) _buildCenterPin(),

          // 2. Header Top Bar (Back button, Logo DRIVO, Map layer icon)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopHeader(),
          ),

          // 3. Floating Route Selector Card (Điểm đón, Điểm dừng, Điểm đến)
          if (_picking == null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: _buildRouteSelectorCard(),
            ),

          // 4+5. Chips + nút định vị, rồi Bottom Sheet (tự co giãn theo nội dung)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildMapActionChips(),
                ),
                const SizedBox(height: 12),
                if (_picking != null)
                  _buildPickOnMapPanel()
                else if (_activeBooking != null)
                  _buildActiveBookingTrackingSheet()
                else
                  _buildBookingBottomPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bản đồ: markers & polylines ─────────────────────────────
  List<MapMarker> _buildMarkers() {
    final markers = <MapMarker>[];
    final b = _activeBooking;
    if (b != null) {
      if (b.hasPickupCoords) {
        markers.add(MapMarker(
          id: 'pickup',
          position: LatLng(b.pickupLatitude!, b.pickupLongitude!),
          kind: MapMarkerKind.pickup,
          title: 'Điểm đón: ${b.pickupAddress}',
        ));
      }
      if (b.hasDestinationCoords) {
        markers.add(MapMarker(
          id: 'destination',
          position: LatLng(b.destinationLatitude!, b.destinationLongitude!),
          kind: MapMarkerKind.destination,
          title: 'Điểm đến: ${b.destinationAddress}',
        ));
      }
      if (_driverLatLng != null && b.driverName != null) {
        markers.add(MapMarker(
          id: 'driver',
          position: _driverLatLng!,
          kind: MapMarkerKind.scooter,
          title: '${b.driverName} · Tài xế DRIVO',
        ));
      }
      return markers;
    }
    if (_pickupLatLng != null && _picking != _PickTarget.pickup) {
      markers.add(MapMarker(
        id: 'pickup',
        position: _pickupLatLng!,
        kind: MapMarkerKind.pickup,
        title: 'Điểm đón: $_pickupAddress',
      ));
    }
    if (_destinationLatLng != null && _picking != _PickTarget.destination) {
      markers.add(MapMarker(
        id: 'destination',
        position: _destinationLatLng!,
        kind: MapMarkerKind.destination,
        title: 'Điểm đến: $_destinationAddress',
      ));
    }
    return markers;
  }

  List<MapLine> _buildPolylines() {
    final lines = <MapLine>[];
    final b = _activeBooking;
    List<LatLng> route;
    if (b != null) {
      route = GeoUtils.decodePolyline(b.routePolyline);
      if (route.isEmpty && b.hasPickupCoords && b.hasDestinationCoords) {
        route = [
          LatLng(b.pickupLatitude!, b.pickupLongitude!),
          LatLng(b.destinationLatitude!, b.destinationLongitude!),
        ];
      }
      // Đường tài xế (xe điện gấp) -> điểm đón khi đang đến đón
      final approaching = b.status == 'DriverAccepted' || b.status == 'DriverArriving' || b.status == 'DriverAssigned';
      if (approaching && _driverLatLng != null && b.hasPickupCoords) {
        lines.add(MapLine(
          id: 'driver-approach',
          points: [_driverLatLng!, LatLng(b.pickupLatitude!, b.pickupLongitude!)],
          color: const Color(0xFF10B981),
          width: 4,
          dashed: true,
        ));
      }
    } else if (_picking == null) {
      route = GeoUtils.decodePolyline(_estimate?.routePolyline);
    } else {
      route = const [];
    }
    if (route.length >= 2) {
      lines.add(MapLine(
        id: 'route',
        points: route,
        color: const Color(0xFF0070E0),
        width: 5,
      ));
    }
    return lines;
  }

  // ── Chọn điểm trên bản đồ ───────────────────────────────────
  void _startPickOnMap(_PickTarget target) {
    final start = target == _PickTarget.pickup
        ? (_pickupLatLng ?? _cameraTarget)
        : (_destinationLatLng ?? _pickupLatLng ?? _cameraTarget);
    setState(() {
      _picking = target;
      _pickingAddress = '';
    });
    _moveCamera(start, zoom: 17);
    // Đảm bảo có địa chỉ ngay cả khi camera không phát sự kiện (map chưa sẵn sàng).
    _cameraTarget = start;
    _onCameraIdle();
  }

  Future<void> _onCameraIdle() async {
    if (_picking == null) return;
    final target = _cameraTarget;
    final seq = ++_reverseSeq;
    setState(() => _pickingResolving = true);
    final place = await ApiService.reverseGeocode(target.latitude, target.longitude);
    if (!mounted || seq != _reverseSeq || _picking == null) return;
    setState(() {
      _pickingResolving = false;
      _pickingAddress = place?.address ??
          'Vị trí đã chọn (${target.latitude.toStringAsFixed(5)}, ${target.longitude.toStringAsFixed(5)})';
    });
  }

  void _confirmPickOnMap() {
    final target = _cameraTarget;
    final addr = _pickingAddress.isNotEmpty
        ? _pickingAddress
        : 'Vị trí đã chọn (${target.latitude.toStringAsFixed(5)}, ${target.longitude.toStringAsFixed(5)})';
    final which = _picking;
    setState(() => _picking = null);
    if (which == _PickTarget.pickup) {
      _setPickup(target, addr);
    } else if (which == _PickTarget.destination) {
      _setDestination(target, addr);
    }
  }

  void _setPickup(LatLng p, String address) {
    setState(() {
      _pickupLatLng = p;
      _pickupAddress = address;
    });
    if (_hasDestination) {
      _fetchEstimate();
    } else {
      _moveCamera(p, zoom: 16);
    }
  }

  void _setDestination(LatLng p, String address) {
    setState(() {
      _destinationLatLng = p;
      _destinationAddress = address;
    });
    if (_pickupLatLng != null) {
      _fetchEstimate();
    } else {
      _moveCamera(p, zoom: 16);
    }
  }

  Widget _buildCenterPin() {
    final isPickup = _picking == _PickTarget.pickup;
    final color = isPickup ? const Color(0xFF0070E0) : const Color(0xFFFF3B30);
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -22),
          child: Icon(Icons.location_on_rounded, size: 48, color: color,
              shadows: const [Shadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))]),
        ),
      ),
    );
  }

  Widget _buildPickOnMapPanel() {
    final isPickup = _picking == _PickTarget.pickup;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPickup ? 'Kéo bản đồ để chọn điểm đón' : 'Kéo bản đồ để chọn điểm đến',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(isPickup ? Icons.my_location_rounded : Icons.location_on_rounded,
                      color: isPickup ? const Color(0xFF0070E0) : const Color(0xFFFF3B30), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _pickingResolving && _pickingAddress.isEmpty
                        ? Text('Đang xác định địa chỉ...', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)))
                        : Text(
                            _pickingAddress.isEmpty ? 'Di chuyển bản đồ tới vị trí mong muốn' : _pickingAddress,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                          ),
                  ),
                  if (_pickingResolving)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: OutlinedButton(
                      onPressed: () => setState(() => _picking = null),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Hủy', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: ElevatedButton(
                      onPressed: _confirmPickOnMap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0066CC),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(isPickup ? 'Xác nhận điểm đón' : 'Xác nhận điểm đến',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top Bar Header ──────────────────────────────────────────
  Widget _buildTopHeader() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Nút Back tròn
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF1E293B)),
              ),
            ),

            // Logo Thương hiệu "DRIVO" 
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF0070E0), Color(0xFF00449E)],
                  ).createShader(bounds),
                  child: Text(
                    'DRIVO',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),

            // Nút Chuyển layer bản đồ (thường <-> vệ tinh)
            GestureDetector(
              onTap: () => setState(() {
                _mapStyle = _mapStyle == DrivoMapStyle.standard ? DrivoMapStyle.voyager : DrivoMapStyle.standard;
              }),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0066CC),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0066CC).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _mapStyle == DrivoMapStyle.standard ? Icons.layers_rounded : Icons.map_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Route Selector Floating Card ────────────────────────────
  Widget _buildRouteSelectorCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE5F1FC).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0055AA).withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Điểm đón (Blue GPS dot)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0070E0),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0070E0).withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _activeBooking != null ? null : () => _showPlaceSearchSheet(_PickTarget.pickup),
                      child: Text(
                        _activeBooking?.pickupAddress ?? _pickupAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 2. Điểm dừng (0/2) + nút Add
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 6, bottom: 6),
                child: Row(
                  children: [
                    Text(
                      'Điểm dừng (0/2)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tính năng thêm tối đa 2 điểm dừng')),
                        );
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0066CC),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Điểm đến (Red Pin)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3B30).withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _activeBooking != null ? null : () => _showPlaceSearchSheet(_PickTarget.destination),
                      child: Text(
                        _activeBooking?.destinationAddress ??
                            (_hasDestination ? _destinationAddress : 'Bạn muốn đi đâu? Chạm để chọn điểm đến'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: (_hasDestination || _activeBooking != null) ? FontWeight.w600 : FontWeight.w500,
                          color: (_hasDestination || _activeBooking != null) ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Quick Action Chips Over Map ─────────────────────────────
  Widget _buildMapActionChips() {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [// 2. Đặt trước
        _buildPillChip(
          icon: Icons.calendar_today_rounded,
          label: 'Đặt trước',
          iconColor: const Color(0xFF0088EE),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Chọn thời gian hẹn tài xế đến đón')),
            );
          },
        ),
        const SizedBox(width: 8),

        // 3. Đặt hộ
        _buildPillChip(
          icon: Icons.favorite_rounded,
          label: 'Đặt hộ',
          iconColor: const Color(0xFFE91E63),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đặt tài xế lái hộ cho người thân, bạn bè')),
            );
          },
        ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 4. Nút định vị GPS: đưa bản đồ về vị trí hiện tại
        GestureDetector(
          onTap: _goToMyLocation,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.my_location_rounded, color: Color(0xFF0070E0), size: 22),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPillChip({
    required IconData icon,
    required String label,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor ?? const Color(0xFF1E293B)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Booking Bottom Sheet Panel ──────────────────────────────
  Widget _buildBookingBottomPanel() {
    final est = _estimate;
    final double discount = est != null ? math.min(_voucherDiscount, est.totalEstimatedFare) : 0;
    final String fareText = _loadingEstimate
        ? '...'
        : (est != null ? _formatCurrency(est.totalEstimatedFare - discount) : '—');
    final String distanceText =
        _loadingEstimate ? '...' : (est != null ? '${est.estimatedDistanceKm.toStringAsFixed(1)}km' : '—');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Thông tin xe (Biển số xe & Mẫu xe)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0070E0).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(Icons.directions_car_filled_rounded, color: Color(0xFF0070E0), size: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Biển số xe: ${_selectedVehicle?.licensePlate ?? "00A-000.00"}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Mẫu xe: ${_selectedVehicle?.displayName ?? "Xe mặc định"}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _showVehicleSelectorSheet,
                      child: Text(
                        'Thay đổi',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0070E0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. Toggle Switch: Cho phép tài xế mang xe điện gấp để cốp xe
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Cho phép tài xế mang xe điện gấp để cốp xe',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _allowFoldingScooter,
                    activeColor: const Color(0xFF0070E0),
                    onChanged: (val) => setState(() => _allowFoldingScooter = val),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 3. Tổng cộng & Khoảng cách
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tổng cộng:',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: est != null ? () => _showFareDetailSheet(est) : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              fareText,
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0070E0),
                              ),
                            ),
                            if (est != null) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
                            ],
                          ],
                        ),
                      ),
                      if (est != null && !_loadingEstimate && discount > 0)
                        Text(
                          '${_formatCurrency(est.totalEstimatedFare)} · giảm ${_formatCurrency(discount)}',
                          style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF16A34A), fontWeight: FontWeight.w600),
                        ),
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('DRIVO hỗ trợ xuất hóa đơn VAT điện tử')),
                          );
                        },
                        child: Text(
                          'Yêu cầu xuất hoá đơn >',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0070E0),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Khoảng cách:',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        distanceText,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0070E0),
                        ),
                      ),
                      if (est != null && !_loadingEstimate)
                        Text(
                          '~${est.estimatedDurationMin} phút',
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ],
              ),
              if (est != null && !_loadingEstimate) ...[
                const SizedBox(height: 8),
                _buildPickupFeeInfo(est),
              ] else if (!_hasDestination) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Chọn điểm đến để xem giá cước dự kiến',
                    style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // 4. Các nút tuỳ chọn (Tiền mặt, Ghi chú, Chọn khuyến mãi)
              Row(
                children: [
                  // Tiền mặt
                  Expanded(
                    child: InkWell(
                      onTap: _showPaymentPicker,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.attach_money_rounded, color: Color(0xFF0070E0), size: 18),
                          const SizedBox(width: 4),
                          Text(_paymentMethod, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  Container(height: 18, width: 1, color: const Color(0xFFE2E8F0)),

                  // Ghi chú
                  Expanded(
                    child: InkWell(
                      onTap: _showNoteDialog,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.edit_note_rounded, color: Color(0xFF64748B), size: 18),
                          const SizedBox(width: 4),
                          Text('Ghi chú', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  Container(height: 18, width: 1, color: const Color(0xFFE2E8F0)),

                  // Chọn khuyến mãi
                  Expanded(
                    child: InkWell(
                      onTap: _showPromoDialog,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _voucherCode != null ? Icons.local_offer_rounded : Icons.local_offer_outlined,
                            color: _voucherCode != null ? const Color(0xFF16A34A) : const Color(0xFF0070E0),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _voucherCode ?? 'Khuyến mãi',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _voucherCode != null ? const Color(0xFF16A34A) : const Color(0xFF0070E0),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 5. Dual Action Buttons: DRIVONow vs Đặt chuyến ngay
              Row(
                children: [
                  // Nút DRIVONow (Màu xanh dương nhạt)
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFBFE0FF),
                          foregroundColor: const Color(0xFF005DB4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('DRIVONow: Chuyến đi ưu tiên điều phối tài xế gần nhất')),
                          );
                          _createBooking();
                        },
                        child: Text(
                          'DRIVONow',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Nút Đặt chuyến ngay (Màu xanh dương đậm chính)
                  Expanded(
                    flex: 6,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0066CC),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _submitting ? null : _createBooking,
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                'Đặt chuyến ngay',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Active Booking Tracking Sheet ───────────────────────────
  Widget _buildActiveBookingTrackingSheet() {
    final b = _activeBooking!;
    if (_isSearching(b)) _ensureSearchTicker();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thanh kéo nhỏ
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Trạng thái chuyến
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0070E0),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b.statusDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0070E0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '#${b.bookingCode}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFE2E8F0)),

              // Driver Card (Nếu đã nhận tài xế) hoặc Radar tìm kiếm
              if (b.driverName != null) ...[
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF0070E0).withValues(alpha: 0.15),
                      foregroundImage: b.driverAvatarUrl != null
                          ? NetworkImage(ApiService.fileUrl(b.driverAvatarUrl!))
                          : null,
                      child: const Icon(Icons.person_rounded, color: Color(0xFF0070E0), size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.driverName!,
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tài xế DRIVO (Đã chuẩn bị xe điện gấp)',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF10B981), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _callDriver(b.driverPhone),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE0F2FE),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.phone_rounded, color: Color(0xFF0070E0), size: 20),
                      ),
                    ),
                  ],
                ),
                if (_driverEtaText(b) != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.electric_scooter_rounded, size: 18, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _driverEtaText(b)!,
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF047857)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (b.status == 'DriverArrived' && b.arrivedAt != null) ...[
                  const SizedBox(height: 10),
                  WaitingTimerCard(
                    arrivedAt: b.arrivedAt!,
                    freeWaitingMin: b.freeWaitingMin,
                    waitingPricePerMin: b.waitingPricePerMin,
                    note: (over) => !over
                        ? 'Tài xế đã đến điểm đón. Sau ${b.freeWaitingMin} phút chờ miễn phí sẽ tính phí chờ${b.waitingPricePerMin > 0 ? ' ${_formatCurrency(b.waitingPricePerMin)}/phút' : ''}.'
                        : b.waitExtendedAt != null
                            ? 'Tài xế tiếp tục chờ bạn, phí chờ đang được tính. Bạn ra điểm đón sớm nhé.'
                            : 'Tài xế sẽ gọi xác nhận. Nếu bạn không có mặt, tài xế có thể hủy chuyến.',
                  ),
                ],
              ] else ...[
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: const Color(0xFF0070E0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Đang liên hệ tài xế gần bạn nhất...${_searchElapsedText(b)}',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
                      ),
                    ),
                  ],
                ),
                if (_showNoDriverNotice(b)) ...[
                  const SizedBox(height: 12),
                  _buildNoDriverNotice(b),
                ],
              ],
              const SizedBox(height: 14),

              // Cước phí & Hủy
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cước phí dự kiến', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      Text(
                        _formatCurrency(b.estimatedPrice + b.pickupFee + b.waitingFee + b.extraDistanceFee - b.discount),
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0070E0)),
                      ),
                      if (b.pickupFee > 0 || b.waitingFee > 0)
                        Text(
                          [
                            'Cước chuyến ${_formatCurrency(b.estimatedPrice)}',
                            if (b.pickupFee > 0) 'phí đón ${_formatCurrency(b.pickupFee)}',
                            if (b.waitingFee > 0) 'phí chờ ${_formatCurrency(b.waitingFee)}',
                          ].join(' + '),
                          style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF64748B)),
                        ),
                    ],
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      foregroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submitting ? null : _cancelBooking,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(_submitting ? 'Đang hủy...' : 'Hủy chuyến', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Khoảng cách/ETA của tài xế tới điểm đón (haversine phía client).
  String? _driverEtaText(BookingDetail b) {
    const approaching = ['DriverAssigned', 'DriverAccepted', 'DriverArriving'];
    if (!approaching.contains(b.status) || _driverLatLng == null || !b.hasPickupCoords) return null;
    final km = GeoUtils.roadKm(_driverLatLng!, LatLng(b.pickupLatitude!, b.pickupLongitude!));
    if (km < 0.1) return 'Tài xế sắp tới điểm đón';
    return 'Tài xế cách điểm đón ~${km.toStringAsFixed(1)} km · khoảng ${GeoUtils.scooterEtaMin(km)} phút';
  }

  /// Dòng giải thích phí đón (tài xế đi xe điện gấp tới chỗ khách).
  Widget _buildPickupFeeInfo(FareEstimate est) {
    final parts = <String>[];
    if (est.pickupFeePerKm > 0) {
      parts.add('Miễn phí đón trong ${_trimKm(est.freePickupKm)} km, sau đó ${_formatCurrency(est.pickupFeePerKm)}/km');
    }
    if (est.estimatedPickupKm != null) {
      final eta = est.nearestDriverEtaMin != null ? ', ~${est.nearestDriverEtaMin} phút' : '';
      final fee = (est.estimatedPickupFee ?? 0) > 0
          ? ' · phí đón dự kiến ${_formatCurrency(est.estimatedPickupFee!)}'
          : ' · miễn phí đón';
      parts.add('Tài xế gần nhất cách ~${est.estimatedPickupKm!.toStringAsFixed(1)} km$eta$fee');
    } else {
      parts.add('Chưa có tài xế trực tuyến gần bạn');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.electric_scooter_rounded, size: 16, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join('\n'),
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF475569), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  String _trimKm(double km) => km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1);

  void _showFareDetailSheet(FareEstimate est) {
    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13.5, color: const Color(0xFF475569), fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          Text(value, style: GoogleFonts.inter(fontSize: bold ? 16 : 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? const Color(0xFF0070E0) : const Color(0xFF0F172A))),
        ],
      ),
    );
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chi tiết giá cước dự kiến', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              row('Quãng đường', '${est.estimatedDistanceKm.toStringAsFixed(1)} km'),
              row('Thời gian dự kiến', '~${est.estimatedDurationMin} phút'),
              const Divider(),
              row('Giá mở cửa', _formatCurrency(est.baseFare)),
              row('Cước theo km', _formatCurrency(est.distanceFare)),
              row('Cước theo thời gian', _formatCurrency(est.timeFare)),
              if (est.nightSurcharge > 0) row('Phụ phí ban đêm', _formatCurrency(est.nightSurcharge)),
              const Divider(),
              if (_voucherDiscount > 0) ...[
                row('Cước chuyến', _formatCurrency(est.totalEstimatedFare)),
                row('Khuyến mãi ${_voucherCode ?? ''}', '-${_formatCurrency(math.min(_voucherDiscount, est.totalEstimatedFare))}'),
                row('Tạm tính', _formatCurrency(est.totalEstimatedFare - math.min(_voucherDiscount, est.totalEstimatedFare)), bold: true),
              ] else
                row('Cước chuyến', _formatCurrency(est.totalEstimatedFare), bold: true),
              const SizedBox(height: 10),
              _buildPickupFeeInfo(est),
              if (est.freeWaitingMin > 0 && est.waitingPricePerMin > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Miễn phí chờ ${est.freeWaitingMin} phút tại điểm đón, sau đó ${_formatCurrency(est.waitingPricePerMin)}/phút. '
                  'Phí đón, phí chờ và phụ phí quãng đường (nếu đi xa hơn dự kiến) được cộng khi hoàn thành chuyến.',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Dialogs: Địa chỉ, Xe, Thanh toán, Khuyến mãi ──────────
  static String _newSessionToken() {
    final r = math.Random();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Sheet tìm địa chỉ: gợi ý từ /maps/autocomplete (debounce 350 ms) -> /maps/place lấy toạ độ.
  void _showPlaceSearchSheet(_PickTarget target) {
    final isPickup = target == _PickTarget.pickup;
    final ctrl = TextEditingController();
    final sessionToken = _newSessionToken();
    Timer? debounce;
    List<PlaceSuggestion> results = [];
    bool searching = false;
    bool resolving = false;
    int querySeq = 0;
    final bias = _pickupLatLng ?? _cameraTarget;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void onChanged(String text) {
            debounce?.cancel();
            final q = text.trim();
            if (q.length < 2) {
              setSheet(() {
                results = [];
                searching = false;
              });
              return;
            }
            setSheet(() => searching = true);
            debounce = Timer(const Duration(milliseconds: 350), () async {
              final seq = ++querySeq;
              final list = await ApiService.mapsAutocomplete(q,
                  lat: bias.latitude, lng: bias.longitude, sessionToken: sessionToken);
              if (!ctx.mounted || seq != querySeq) return;
              setSheet(() {
                results = list;
                searching = false;
              });
            });
          }

          Future<void> choose(PlaceSuggestion s) async {
            final messenger = ScaffoldMessenger.of(context);
            final fallbackAddress = [s.mainText, s.secondaryText].where((x) => x.isNotEmpty).join(', ');
            // OSM: gợi ý đã có toạ độ -> dùng luôn, không cần gọi /maps/place.
            if (s.latitude != null && s.longitude != null) {
              Navigator.pop(ctx);
              final p = LatLng(s.latitude!, s.longitude!);
              if (isPickup) {
                _setPickup(p, fallbackAddress);
              } else {
                _setDestination(p, fallbackAddress);
              }
              return;
            }
            setSheet(() => resolving = true);
            final place = await ApiService.mapsPlace(s.placeId, sessionToken: sessionToken);
            if (!ctx.mounted) return;
            setSheet(() => resolving = false);
            if (place == null) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Không lấy được toạ độ địa điểm, vui lòng thử lại')),
              );
              return;
            }
            Navigator.pop(ctx);
            final address = place.address.isNotEmpty
                ? place.address
                : [s.mainText, s.secondaryText].where((x) => x.isNotEmpty).join(', ');
            final p = LatLng(place.latitude, place.longitude);
            if (isPickup) {
              _setPickup(p, address);
            } else {
              _setDestination(p, address);
            }
          }

          Future<void> useMyLocation() async {
            final messenger = ScaffoldMessenger.of(context);
            setSheet(() => resolving = true);
            final r = await LocationService.getCurrent();
            if (!ctx.mounted) return;
            if (!r.ok) {
              setSheet(() => resolving = false);
              messenger.showSnackBar(
                SnackBar(content: Text(r.error ?? 'Không lấy được vị trí')),
              );
              return;
            }
            final p = LatLng(r.position!.latitude, r.position!.longitude);
            final place = await ApiService.reverseGeocode(p.latitude, p.longitude);
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (mounted) {
              setState(() {
                _hasLocationPermission = true;
                _myLocation = p;
              });
            }
            final addr = place?.address ?? 'Vị trí hiện tại của bạn';
            if (isPickup) {
              _setPickup(p, addr);
            } else {
              _setDestination(p, addr);
            }
          }

          final color = isPickup ? const Color(0xFF0070E0) : const Color(0xFFFF3B30);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isPickup ? 'Chọn điểm đón' : 'Chọn điểm đến',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    onChanged: onChanged,
                    decoration: InputDecoration(
                      prefixIcon: Icon(isPickup ? Icons.my_location_rounded : Icons.location_on_rounded, color: color),
                      hintText: isPickup ? 'Tìm địa chỉ đón...' : 'Tìm địa chỉ đến...',
                      suffixIcon: (searching || resolving)
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isPickup)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.gps_fixed_rounded, color: Color(0xFF0070E0)),
                      title: Text('Dùng vị trí hiện tại', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      onTap: resolving ? null : useMyLocation,
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.pin_drop_outlined, color: Color(0xFF475569)),
                    title: Text('Chọn trên bản đồ', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _startPickOnMap(target);
                    },
                  ),
                  const Divider(height: 8),
                  Flexible(
                    child: results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              ctrl.text.trim().length < 2
                                  ? 'Nhập ít nhất 2 ký tự để tìm kiếm'
                                  : (searching ? 'Đang tìm...' : 'Không tìm thấy địa điểm phù hợp'),
                              style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: results.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final s = results[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.place_outlined, color: Color(0xFF64748B)),
                                title: Text(s.mainText,
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                subtitle: s.secondaryText.isEmpty
                                    ? null
                                    : Text(s.secondaryText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B))),
                                onTap: resolving ? null : () => choose(s),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      debounce?.cancel();
    });
  }

  void _showVehicleSelectorSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Chọn xe của bạn', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddVehicleDialog();
                    },
                    icon: const Icon(Icons.add_rounded, size: 18, color: Color(0xFF0070E0)),
                    label: const Text('Thêm xe', style: TextStyle(color: Color(0xFF0070E0), fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_vehicles.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const Icon(Icons.directions_car_outlined, size: 48, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 8),
                        Text('Chưa có xe nào được lưu', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070E0)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showAddVehicleDialog();
                          },
                          child: const Text('Thêm xe ngay', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _vehicles.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final v = _vehicles[idx];
                      final isSelected = _selectedVehicle?.id == v.id;
                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF0070E0).withValues(alpha: 0.15) : const Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.directions_car_filled_rounded,
                            color: isSelected ? const Color(0xFF0070E0) : const Color(0xFF64748B),
                            size: 20,
                          ),
                        ),
                        title: Text(v.displayName, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        subtitle: Text('${v.transmission == "Automatic" ? "Số tự động" : "Số sàn"} • ${v.vehicleType}',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                        trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF0070E0)) : null,
                        onTap: () {
                          setState(() => _selectedVehicle = v);
                          Navigator.pop(ctx);
                          _fetchEstimate(); // loại xe / hộp số có thể đổi bảng giá
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddVehicleDialog() {
    final plateCtrl = TextEditingController(text: '30A-888.88');
    final brandCtrl = TextEditingController(text: 'Mercedes-Benz');
    final modelCtrl = TextEditingController(text: 'C300 AMG');
    String transmission = 'Automatic';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Thêm xe mới của bạn', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: plateCtrl,
                decoration: const InputDecoration(labelText: 'Biển số xe (VD: 30A-888.88)'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: brandCtrl,
                      decoration: const InputDecoration(labelText: 'Hãng xe (VD: Toyota, Mazda)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(labelText: 'Dòng xe (VD: Camry, CX-5)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Hộp số', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Số tự động (AT)'),
                    selected: transmission == 'Automatic',
                    onSelected: (val) => setDialogState(() => transmission = 'Automatic'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Số sàn (MT)'),
                    selected: transmission == 'Manual',
                    onSelected: (val) => setDialogState(() => transmission = 'Manual'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070E0)),
                onPressed: () async {
                  if (plateCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  final res = await ApiService.addCustomerVehicle({
                    'licensePlate': plateCtrl.text.trim(),
                    'brand': brandCtrl.text.trim(),
                    'model': modelCtrl.text.trim(),
                    'transmission': transmission,
                    'isDefault': true,
                  });
                  if (res['success'] == true) {
                    await _loadVehicles();
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã lưu thông tin xe!')),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(res['message'] ?? 'Lỗi khi lưu xe')),
                      );
                    }
                  }
                },
                child: const Text('Lưu xe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phương thức thanh toán', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.attach_money_rounded, color: Color(0xFF0070E0)),
              title: const Text('Tiền mặt'),
              trailing: _paymentMethod == 'Tiền mặt' ? const Icon(Icons.check, color: Color(0xFF0070E0)) : null,
              onTap: () {
                setState(() => _paymentMethod = 'Tiền mặt');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF0070E0)),
              title: const Text('Ví điện tử DRIVO Pay'),
              trailing: _paymentMethod == 'Ví điện tử' ? const Icon(Icons.check, color: Color(0xFF0070E0)) : null,
              onTap: () {
                setState(() => _paymentMethod = 'Ví điện tử');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF0070E0)),
              title: const Text('Chuyển khoản QR'),
              trailing: _paymentMethod == 'Chuyển khoản QR' ? const Icon(Icons.check, color: Color(0xFF0070E0)) : null,
              onTap: () {
                setState(() => _paymentMethod = 'Chuyển khoản QR');
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteDialog() {
    final ctrl = TextEditingController(text: _customerNote);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ghi chú cho tài xế', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'VD: Xe đỗ ở hầm B2, số tự động, tôi mặc áo trắng...',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070E0)),
              onPressed: () {
                setState(() => _customerNote = ctrl.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('Lưu ghi chú', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _applyPendingVoucher() async {
    final code = _pendingVoucherCode;
    if (code == null) return;
    _pendingVoucherCode = null;
    final err = await _applyVoucher(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err == null
          ? 'Đã áp mã $_voucherCode, giảm ${_formatCurrency(_voucherDiscount)}'
          : 'Chưa áp được mã $code: $err'),
      backgroundColor: err == null ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
    ));
  }

  void _clearVoucher() => setState(() {
        _voucherCode = null;
        _voucherDiscount = 0;
      });

  /// Kiểm tra mã với giá ước tính hiện tại. Trả về thông báo lỗi (null nếu áp thành công).
  Future<String?> _applyVoucher(String code, {bool silent = false}) async {
    final est = _estimate;
    if (est == null) return 'Chọn điểm đến để xem giá trước khi áp mã';
    try {
      final res = await ApiService.checkVoucher(code.trim(), est.totalEstimatedFare);
      if (!mounted) return null;
      if (res['success'] == true && res['data'] != null) {
        final d = res['data'];
        setState(() {
          _voucherCode = d['code'];
          _voucherDiscount = (d['discount'] as num?)?.toDouble() ?? 0;
        });
        return null;
      }
      final msg = res['message']?.toString() ?? 'Mã không hợp lệ';
      if (silent && _voucherCode != null) {
        _clearVoucher();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã bỏ mã khuyến mãi: $msg'), backgroundColor: const Color(0xFFF59E0B)),
        );
      }
      return msg;
    } catch (_) {
      return 'Không kiểm tra được mã, vui lòng thử lại';
    }
  }

  static String _voucherDesc(Map<String, dynamic> v, String Function(double) fmt) {
    final value = (v['discountValue'] as num?)?.toDouble() ?? 0;
    final max = (v['maxDiscountAmount'] as num?)?.toDouble();
    final min = (v['minOrderAmount'] as num?)?.toDouble() ?? 0;
    final parts = <String>[
      v['discountType'] == 'PERCENT'
          ? 'Giảm ${value.toStringAsFixed(0)}%${max != null && max > 0 ? ', tối đa ${fmt(max)}' : ''}'
          : 'Giảm ${fmt(value)}',
      if (min > 0) 'đơn từ ${fmt(min)}',
    ];
    return parts.join(' · ');
  }

  void _showPromoDialog() {
    final ctrl = TextEditingController(text: _voucherCode ?? '');
    final vouchersFuture = ApiService.getAvailableVouchers();
    String? error;
    bool applying = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> apply(String code) async {
            if (code.trim().isEmpty || applying) return;
            setSheet(() {
              applying = true;
              error = null;
            });
            final err = await _applyVoucher(code);
            if (!ctx.mounted || !mounted) return;
            if (err == null) {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Đã áp mã $_voucherCode, giảm ${_formatCurrency(_voucherDiscount)}'),
                backgroundColor: const Color(0xFF16A34A),
              ));
            } else {
              setSheet(() {
                applying = false;
                error = err;
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mã khuyến mãi', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(hintText: 'Nhập mã, VD: DRIVOVIP', errorText: error),
                          onSubmitted: apply,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0070E0),
                          minimumSize: const Size(88, 48),
                        ),
                        onPressed: applying ? null : () => apply(ctrl.text),
                        child: applying
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Áp dụng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  if (_voucherCode != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(minimumSize: Size.zero, padding: EdgeInsets.zero),
                      onPressed: () {
                        _clearVoucher();
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFE53935)),
                      label: Text('Bỏ mã $_voucherCode', style: const TextStyle(color: Color(0xFFE53935))),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text('Mã dành cho bạn', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  Flexible(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: vouchersFuture,
                      builder: (ctx, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        final list = (snap.data?['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                        if (list.isEmpty) {
                          return const ListTile(
                            leading: Icon(Icons.confirmation_num_outlined, color: Color(0xFF94A3B8)),
                            title: Text('Hiện chưa có mã khuyến mãi khả dụng'),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final v = list[i];
                            final selected = v['code'] == _voucherCode;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.local_offer_rounded,
                                  color: selected ? const Color(0xFF16A34A) : const Color(0xFF0070E0)),
                              title: Text('${v['code']} · ${v['title']}',
                                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700)),
                              subtitle: Text(_voucherDesc(v, _formatCurrency), style: GoogleFonts.inter(fontSize: 12)),
                              trailing: selected ? const Icon(Icons.check, color: Color(0xFF16A34A)) : null,
                              onTap: applying ? null : () => apply(v['code']),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
