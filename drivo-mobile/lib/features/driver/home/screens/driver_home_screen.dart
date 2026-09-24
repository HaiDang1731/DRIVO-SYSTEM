import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/api_service.dart';
import '../../../../../core/drivo_map.dart';
import '../../../../../core/geo_utils.dart';
import '../../../../../core/location_service.dart';
import '../../../../../core/theme.dart';

class DriverHomeScreen extends StatefulWidget {
  final AuthUser user;
  final VoidCallback onLogout;
  const DriverHomeScreen({super.key, required this.user, required this.onLogout});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  int _tab = 0;
  DriverProfile? _profile;
  bool _loadingProfile = true;
  bool _isOnline = false;
  bool _togglingStatus = false;

  // Active booking for driver
  DriverBooking? _activeBooking;

  // Pending booking popup
  DriverBooking? _pendingOffer;
  bool _acceptingBooking = false;

  // Polling timer
  Timer? _pollingTimer;

  // Radar animation
  late AnimationController _radarCtrl;
  late Animation<double> _radarAnim;

  // Step update loading
  bool _updatingStatus = false;

  // GPS: gửi vị trí lên server khi online / đang chạy chuyến (chỉ khi app ở foreground)
  StreamSubscription<Position>? _posSub;
  Timer? _locationSendTimer;
  Position? _lastPos;
  Position? _lastSentPos;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _sendingLocation = false;
  bool _appInForeground = true;
  bool _locationWarned = false;

  // Bản đồ chuyến đi
  DrivoMapController? _tripMapCtrl;
  String? _fittedKey; // bookingId:status đã căn camera
  String? _approachPolyline; // lộ trình xe điện gấp -> điểm đón (Routes TWO_WHEELER)
  int? _approachForBookingId;

  LatLng? get _myLatLng => _lastPos == null ? null : LatLng(_lastPos!.latitude, _lastPos!.longitude);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _radarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _radarAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _radarCtrl, curve: Curves.easeOut),
    );
    _loadProfile();
    _loadActiveBooking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _radarCtrl.dispose();
    _pollingTimer?.cancel();
    _stopLocationUpdates();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Chỉ gửi GPS khi app đang mở (không có background location).
    _appInForeground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    _syncLocationUpdates();
  }

  // ── GPS tài xế ──────────────────────────────────────────────
  bool get _shouldTrackLocation => _appInForeground && (_isOnline || _activeBooking != null);

  void _syncLocationUpdates() {
    if (_shouldTrackLocation) {
      _startLocationUpdates();
    } else {
      _stopLocationUpdates();
    }
  }

  Future<void> _startLocationUpdates() async {
    if (_posSub != null) return;
    final err = await LocationService.ensurePermission();
    if (!mounted) return;
    if (err != null) {
      if (!_locationWarned) {
        _locationWarned = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: DrivoColors.warning,
          action: SnackBarAction(label: 'Cài đặt', onPressed: LocationService.openSettings),
        ));
      }
      return;
    }
    if (_posSub != null || !_shouldTrackLocation) return;
    _posSub = LocationService.positionStream(distanceFilterMeters: 10).listen(
      (pos) {
        final first = _lastPos == null;
        _lastPos = pos;
        if (mounted && _activeBooking != null) setState(() {});
        if (first) _maybeSendLocation(force: true);
      },
      onError: (_) {},
    );
    // Gửi tối đa 5 s/lần; nếu đứng yên vẫn gửi "heartbeat" mỗi 60 s để server biết vị trí còn mới.
    _locationSendTimer?.cancel();
    _locationSendTimer = Timer.periodic(const Duration(seconds: 5), (_) => _maybeSendLocation());
  }

  void _stopLocationUpdates() {
    _posSub?.cancel();
    _posSub = null;
    _locationSendTimer?.cancel();
    _locationSendTimer = null;
  }

  Future<void> _maybeSendLocation({bool force = false}) async {
    final pos = _lastPos;
    if (pos == null || _sendingLocation) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastSentAt);
    if (elapsed < const Duration(seconds: 5)) return;
    final moved = !identical(pos, _lastSentPos);
    if (!force && !moved && elapsed < const Duration(seconds: 60)) return;
    _sendingLocation = true;
    try {
      await ApiService.updateDriverLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy > 0 ? pos.accuracy : null,
        speedKmh: pos.speed >= 0 ? pos.speed * 3.6 : null,
        heading: pos.heading >= 0 ? pos.heading : null,
      );
      _lastSentPos = pos;
      _lastSentAt = now;
    } catch (_) {
      // mạng chập chờn -> lần sau gửi lại
    } finally {
      _sendingLocation = false;
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    final res = await ApiService.getDriverProfile();
    if (res['success'] == true && mounted) {
      final p = DriverProfile.fromJson(res['data']);
      setState(() {
        _profile = p;
        _isOnline = p.driverStatus == 'Online';
        _loadingProfile = false;
      });
      if (p.isFirstLogin) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showChangePasswordDialog(forced: true));
      }
      // Start polling if online and no active booking
      if (_isOnline && _activeBooking == null) {
        _startPolling();
      }
      _syncLocationUpdates();
    } else {
      setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadActiveBooking() async {
    final res = await ApiService.getDriverActiveBooking();
    if (mounted) {
      if (res['success'] == true && res['data'] != null) {
        setState(() {
          _activeBooking = DriverBooking.fromJson(res['data']);
          });
        _loadApproachRoute();
      } else {
        setState(() {
          _activeBooking = null;
          });
      }
      _syncLocationUpdates();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollBooking());
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _pollBooking() async {
    if (!mounted || _acceptingBooking || _updatingStatus) return;
    
    if (_activeBooking != null) {
      final res = await ApiService.getDriverActiveBooking();
      if (mounted) {
        if (res['success'] == true && res['data'] != null) {
          final updated = DriverBooking.fromJson(res['data']);
          if (updated.status == 'Cancelled') {
             setState(() => _activeBooking = null);
             _syncLocationUpdates();
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
               content: Text('Khách hàng đã hủy chuyến đi.'), backgroundColor: DrivoColors.danger
             ));
          } else {
             setState(() => _activeBooking = updated);
          }
        } else {
          // Booking might have been cancelled
          setState(() => _activeBooking = null);
          _syncLocationUpdates();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cuốc xe đã bị hủy hoặc không còn khả dụng.'), backgroundColor: DrivoColors.danger
          ));
        }
      }
    } else {
      final res = await ApiService.getDriverPendingBookings();
      if (res['success'] == true && mounted) {
        final list = (res['data'] as List?) ?? [];
        
        if (_pendingOffer != null) {
          // Check if current offer is still in the pending list
          bool stillPending = list.any((b) => b['id'] == _pendingOffer!.id);
          if (!stillPending) {
            Navigator.pop(context); // Close the sheet
            setState(() => _pendingOffer = null);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Cuốc xe đã bị hủy hoặc được tài xế khác nhận.'), 
              backgroundColor: DrivoColors.warning,
            ));
          }
        } else if (list.isNotEmpty && _activeBooking == null) {
          setState(() => _pendingOffer = DriverBooking.fromJson(list.first));
          _showBookingOfferSheet();
        }
      }
    }
  }


  void _showBookingOfferSheet() {
    if (_pendingOffer == null) return;
    final offer = _pendingOffer!;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: const BoxDecoration(
            color: DrivoColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: DrivoColors.border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),

              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DrivoColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_taxi_rounded, color: DrivoColors.primary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cuốc xe mới!', style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(offer.bookingCode, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
                ])),
                // Hiện đúng số khách trả (khớp màn khách); mã giảm do DRIVO bù nên thu nhập tài xế không đổi.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: DrivoColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${((offer.estimatedPrice - offer.discount) / 1000).toStringAsFixed(0)}K ₫',
                    style: GoogleFonts.inter(color: DrivoColors.success, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ]),
              if (offer.offerSecondsLeft != null) ...[
                const SizedBox(height: 10),
                _OfferCountdown(
                  seconds: offer.offerSecondsLeft!,
                  onExpired: () {
                    if (!mounted || _acceptingBooking || !ctx.mounted) return;
                    Navigator.pop(ctx);
                    setState(() => _pendingOffer = null);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Hết thời gian ưu tiên, cuốc đã chuyển cho tài xế khác.'),
                      backgroundColor: DrivoColors.warning,
                    ));
                  },
                ),
              ],
              if (offer.discount > 0) ...[
                const SizedBox(height: 8),
                _VoucherNote(booking: offer),
              ],
              const SizedBox(height: 14),

              // Khoảng cách từ tài xế tới điểm đón (server tính theo vị trí GPS gần nhất)
              if (offer.distanceToPickupKm != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: DrivoColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.electric_scooter_rounded, color: DrivoColors.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Cách điểm đón ~${offer.distanceToPickupKm!.toStringAsFixed(1)} km '
                      '(~${GeoUtils.scooterEtaMin(offer.distanceToPickupKm!)} phút bằng xe điện gấp)',
                      style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                    )),
                  ]),
                ),
                const SizedBox(height: 14),
              ],

              // Route info
              _OfferRouteRow(icon: Icons.circle, iconColor: DrivoColors.primary, label: 'Điểm đón', address: offer.pickupAddress),
              const Padding(
                padding: EdgeInsets.only(left: 10),
                child: SizedBox(height: 2, width: 2, child: VerticalDivider(color: DrivoColors.border, thickness: 1)),
              ),
              _OfferRouteRow(icon: Icons.location_on, iconColor: DrivoColors.danger, label: 'Điểm đến', address: offer.destinationAddress),
              const SizedBox(height: 16),

              // Stats row
              Row(children: [
                _OfferStat(Icons.straighten_rounded, '${offer.estimatedDistanceKm.toStringAsFixed(1)} km'),
                const SizedBox(width: 12),
                _OfferStat(Icons.timer_outlined, '~${offer.estimatedDurationMin} phút'),
                const SizedBox(width: 12),
                _OfferStat(Icons.directions_car_rounded, '${offer.vehicleBrand} ${offer.vehicleModel}'),
              ]),

              if (offer.customerNote != null && offer.customerNote!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DrivoColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DrivoColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.notes_rounded, color: DrivoColors.warning, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(offer.customerNote!, style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 12))),
                  ]),
                ),
              ],
              const SizedBox(height: 20),

              // Buttons
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: _acceptingBooking ? null : () {
                    Navigator.pop(ctx);
                    setState(() => _pendingOffer = null);
                    // Báo server để chuyển ngay cho tài xế tiếp theo và không hiện lại cuốc này
                    ApiService.rejectBooking(offer.id);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: DrivoColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Bỏ qua', style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontWeight: FontWeight.w600)),
                )),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: ElevatedButton(
                  onPressed: _acceptingBooking ? null : () async {
                    setS(() => _acceptingBooking = true);
                    final res = await ApiService.acceptBooking(offer.id);
                    if (res['success'] == true && mounted) {
                      Navigator.pop(ctx);
                      await _loadActiveBooking();
                      setState(() {
                        _pendingOffer = null;
                        _acceptingBooking = false;
                      });
                    } else {
                      setS(() => _acceptingBooking = false);
                      if (mounted) {
                        Navigator.pop(ctx);
                        setState(() => _pendingOffer = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(res['message'] ?? 'Cuốc xe không còn khả dụng'), backgroundColor: DrivoColors.danger),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DrivoColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _acceptingBooking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Nhận cuốc', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                )),
              ]),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _pendingOffer = null);
    });
  }

  Future<void> _toggleOnline() async {
    if (_togglingStatus) return;
    final newStatus = !_isOnline;
    setState(() => _togglingStatus = true);
    // Bật trực tuyến -> gửi kèm vị trí hiện tại để hệ thống ghép cuốc gần nhất.
    double? lat, lng;
    if (newStatus) {
      final r = await LocationService.getCurrent(timeout: const Duration(seconds: 8));
      if (r.ok) {
        _lastPos = r.position;
        lat = r.position!.latitude;
        lng = r.position!.longitude;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${r.error} Bạn vẫn trực tuyến nhưng có thể không nhận được cuốc gần.'),
          backgroundColor: DrivoColors.warning,
        ));
      }
    }
    Map<String, dynamic> res;
    try {
      res = await ApiService.toggleDriverStatus(newStatus, latitude: lat, longitude: lng);
    } catch (e) {
      res = {'success': false, 'message': 'Lỗi kết nối: $e'};
    }
    if (mounted) {
      setState(() {
        _togglingStatus = false;
        if (res['success'] == true) {
          _isOnline = newStatus;
          if (_isOnline && _activeBooking == null) {
            _startPolling();
          } else {
            _stopPolling();
          }
        }
      });
      if (res['success'] == true && lat != null) {
        _lastSentPos = _lastPos;
        _lastSentAt = DateTime.now();
      }
      _syncLocationUpdates();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message'] ?? (newStatus ? 'Đang trực tuyến' : 'Đã ngoại tuyến')),
        backgroundColor: newStatus ? DrivoColors.success : DrivoColors.textMuted,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_activeBooking == null || _updatingStatus) return;
    setState(() => _updatingStatus = true);
    final res = await ApiService.updateBookingStatus(_activeBooking!.id, newStatus);
    if (mounted) {
      setState(() => _updatingStatus = false);
      if (res['success'] == true) {
        final updated = DriverBooking.fromJson(res['data']);
        setState(() => _activeBooking = updated);
        if (updated.status == 'Completed') {
          setState(() => _activeBooking = null);
          _startPolling();
          _syncLocationUpdates();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🎉 Hoàn thành chuyến! Đang tìm cuốc tiếp theo...'),
            backgroundColor: DrivoColors.success,
          ));
          _loadProfile(); // refresh earnings
          _showCompletedSummary(updated);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message'] ?? 'Lỗi cập nhật trạng thái'),
          backgroundColor: DrivoColors.danger,
        ));
      }
    }
  }

  Future<void> _cancelBooking() async {
    if (_activeBooking == null || _updatingStatus) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DrivoColors.bgCard,
        title: const Text('Xác nhận hủy', style: TextStyle(color: DrivoColors.danger)),
        content: const Text('Bạn có chắc chắn muốn hủy cuốc xe này không? Việc này có thể ảnh hưởng đến tỷ lệ nhận chuyến của bạn.', style: TextStyle(color: DrivoColors.textPrimary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không', style: TextStyle(color: DrivoColors.textMuted))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: DrivoColors.danger), child: const Text('Hủy cuốc')),
        ],
      )
    );
    
    if (confirm != true) return;
    
    setState(() => _updatingStatus = true);
    final res = await ApiService.cancelBookingByDriver(_activeBooking!.id, "Tài xế có việc bận đột xuất");
    if (mounted) {
      setState(() => _updatingStatus = false);
      if (res['success'] == true) {
        setState(() => _activeBooking = null);
        _startPolling();
        _syncLocationUpdates();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã hủy chuyến thành công'), backgroundColor: DrivoColors.success
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message'] ?? 'Lỗi hủy chuyến'), backgroundColor: DrivoColors.danger
        ));
      }
    }
  }

  void _showChangePasswordDialog({bool forced = false}) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;
    showDialog(
      context: context,
      barrierDismissible: !forced,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        backgroundColor: DrivoColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (forced) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: DrivoColors.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.warning_rounded, color: DrivoColors.warning, size: 14),
                const SizedBox(width: 6),
                Text('Bắt buộc đổi mật khẩu', style: GoogleFonts.inter(color: DrivoColors.warning, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          Text('Đổi mật khẩu', style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (forced) Text(
            'Mật khẩu hiện tại của bạn là số điện thoại. Vui lòng đổi mật khẩu mới để bảo vệ tài khoản.',
            style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 13),
          ),
          if (forced) const SizedBox(height: 16),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: DrivoColors.danger, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          _pwField('Mật khẩu hiện tại', currentCtrl),
          const SizedBox(height: 10),
          _pwField('Mật khẩu mới (≥ 6 ký tự)', newCtrl),
          const SizedBox(height: 10),
          _pwField('Xác nhận mật khẩu mới', confirmCtrl),
        ]),
        actions: [
          if (!forced) TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: TextStyle(color: DrivoColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () async {
              if (newCtrl.text != confirmCtrl.text) {
                setS(() => error = 'Mật khẩu xác nhận không khớp');
                return;
              }
              final res = await ApiService.changePassword(currentCtrl.text, newCtrl.text);
              if (res['success'] == true && mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('✓ Đổi mật khẩu thành công!'), backgroundColor: DrivoColors.success,
                ));
                _loadProfile();
              } else {
                setS(() => error = res['message'] ?? 'Lỗi đổi mật khẩu');
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      )),
    );
  }

  Widget _pwField(String label, TextEditingController ctrl) => TextField(
    controller: ctrl,
    obscureText: true,
    style: const TextStyle(color: DrivoColors.textPrimary),
    decoration: InputDecoration(labelText: label),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          _buildHomeTab(),
          // Đổi key khi số chuyến đổi -> tab tải lại số liệu sau mỗi chuyến hoàn thành.
          _EarningsTab(key: ValueKey(_profile?.totalTrips), profile: _profile),
          _ProfileTab(
            profile: _profile,
            user: widget.user,
            onChangePassword: _showChangePasswordDialog,
            onLogout: widget.onLogout,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: DrivoColors.bgCard,
        indicatorColor: DrivoColors.primary.withValues(alpha: 0.2),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Trang chủ'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart_rounded), label: 'Thu nhập'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded), label: 'Hồ sơ'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    if (_loadingProfile) {
      return const Center(child: CircularProgressIndicator(color: DrivoColors.primary));
    }

    // If driver has an active booking, show trip management screen
    if (_activeBooking != null) {
      return _buildActiveTripView();
    }

    // Otherwise show normal home
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [DrivoColors.primary, DrivoColors.accent]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: Text(
                _profile?.fullName.split(' ').last[0] ?? '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Xin chào!', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
              Text(_profile?.fullName ?? '...', style: GoogleFonts.inter(
                color: DrivoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16,
              )),
            ])),
            DrivoBadge(_profile?.verificationStatus ?? 'Pending'),
          ]),
          const SizedBox(height: 24),

          // Online Toggle Card
          DrivoCard(
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: _isOnline ? DrivoColors.success : DrivoColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _isOnline ? 'Đang trực tuyến' : 'Ngoại tuyến',
                  style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                Text(
                  _isOnline ? 'Đang tìm cuốc trong khu vực...' : 'Bật để bắt đầu nhận chuyến',
                  style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 12),
                ),
              ])),
              if (_togglingStatus)
                const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2, color: DrivoColors.primary))
              else
                Switch(
                  value: _isOnline,
                  onChanged: _profile?.verificationStatus == 'Approved' ? (_) => _toggleOnline() : null,
                  activeColor: DrivoColors.accent,
                  thumbColor: WidgetStateProperty.all(Colors.white),
                ),
            ]),
          ),

          // Verification warning
          if (_profile?.verificationStatus != 'Approved') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DrivoColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DrivoColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.hourglass_empty_rounded, color: DrivoColors.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Hồ sơ đang chờ Admin duyệt. Sau khi được duyệt bạn có thể nhận chuyến.',
                  style: GoogleFonts.inter(color: DrivoColors.warning, fontSize: 12),
                )),
              ]),
            ),
          ],

          // Radar animation when online
          if (_isOnline && _profile?.verificationStatus == 'Approved') ...[
            const SizedBox(height: 24),
            Center(
              child: AnimatedBuilder(
                animation: _radarCtrl,
                builder: (context, child) {
                  return Stack(alignment: Alignment.center, children: [
                    for (int i = 0; i < 3; i++)
                      Transform.scale(
                        scale: (_radarAnim.value + i * 0.3).clamp(0.0, 1.6),
                        child: Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: DrivoColors.primary.withOpacity((1.0 - _radarAnim.value * 0.6).clamp(0, 1) / (i + 1)),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [DrivoColors.primary, DrivoColors.accent]),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: DrivoColors.primary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))],
                      ),
                      child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 32),
                    ),
                  ]);
                },
              ),
            ),
            const SizedBox(height: 12),
            Center(child: Text(
              'Đang tìm cuốc xe gần bạn...',
              style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 13),
            )),
          ],

          const SizedBox(height: 24),

          // Stats
          const SectionHeader('THỐNG KÊ'),
          Row(children: [
            Expanded(child: _StatCard('Chuyến đã chạy', '${_profile?.totalTrips ?? 0}', Icons.route_rounded, DrivoColors.primary)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard('Đánh giá TB', '${(_profile?.ratingAverage ?? 0).toStringAsFixed(1)}⭐', Icons.star_rounded, DrivoColors.warning)),
          ]),
          const SizedBox(height: 12),
          DrivoCard(
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tổng thu nhập', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
                Text(
                  '${((_profile?.totalEarnings ?? 0) / 1000).toStringAsFixed(0)}K ₫',
                  style: GoogleFonts.inter(color: DrivoColors.success, fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ]),
              const Icon(Icons.account_balance_wallet_rounded, color: DrivoColors.success, size: 32),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildActiveTripView() {
    final b = _activeBooking!;
    final statusColor = {
      'DriverAccepted': DrivoColors.primary,
      'DriverArriving': DrivoColors.warning,
      'DriverArrived': DrivoColors.success,
      'InProgress': DrivoColors.accent,
    }[b.status] ?? DrivoColors.textMuted;

    final statusIcon = {
      'DriverAccepted': Icons.directions_car_rounded,
      'DriverArriving': Icons.navigation_rounded,
      'DriverArrived': Icons.location_on_rounded,
      'InProgress': Icons.play_arrow_rounded,
    }[b.status] ?? Icons.info_outline;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(statusIcon, color: statusColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Chuyến đang thực hiện', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
              Text(b.statusDisplay, style: GoogleFonts.inter(color: statusColor, fontSize: 16, fontWeight: FontWeight.w700)),
            ])),
            Text(b.bookingCode, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 16),

          // Bản đồ chuyến đi + nút chỉ đường
          _buildTripMap(b),
          const SizedBox(height: 16),

          // Route Card
          DrivoCard(
            child: Column(children: [
              _TripRouteRow(
                icon: Icons.circle,
                iconColor: DrivoColors.primary,
                label: 'Đón khách',
                address: b.pickupAddress,
              ),
              const Divider(color: DrivoColors.border),
              _TripRouteRow(
                icon: Icons.location_on,
                iconColor: DrivoColors.danger,
                label: 'Điểm đến',
                address: b.destinationAddress,
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Trip info
          DrivoCard(
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _TripInfoItem('Biển số', b.vehiclePlate),
                _TripInfoItem('Loại xe', '${b.vehicleBrand} ${b.vehicleModel}'),
                _TripInfoItem('Khoảng cách', '${b.estimatedDistanceKm.toStringAsFixed(1)} km'),
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _TripInfoItem('Thời gian', '~${b.estimatedDurationMin} phút'),
                _TripInfoItem('Hộp số', b.vehicleTransmission == 'Automatic' ? 'Tự động' : 'Số sàn'),
                _TripInfoItem('Khách trả', '${((b.estimatedPrice - b.discount) / 1000).toStringAsFixed(0)}K ₫',
                    valueColor: DrivoColors.success),
              ]),
              if (b.discount > 0) ...[
                const SizedBox(height: 12),
                _VoucherNote(booking: b),
              ],
            ]),
          ),

          if (b.customerNote != null && b.customerNote!.isNotEmpty) ...[
            const SizedBox(height: 12),
            DrivoCard(
              child: Row(children: [
                const Icon(Icons.notes_rounded, color: DrivoColors.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(b.customerNote!, style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 13))),
              ]),
            ),
          ],

          // Progress Steps
          const SizedBox(height: 20),
          const SectionHeader('TIẾN TRÌNH CHUYẾN ĐI'),
          _buildProgressSteps(b.status),
          const SizedBox(height: 20),

          // Action button
          if (b.nextStatusAction.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updatingStatus ? null : () => _updateStatus(b.nextStatusAction),
                style: ElevatedButton.styleFrom(
                  backgroundColor: statusColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _updatingStatus
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(b.nextStatusLabel, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          
          if (b.status == 'DriverAccepted' || b.status == 'DriverArriving') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _updatingStatus ? null : () => _cancelBooking(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: DrivoColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Hủy cuốc xe', style: GoogleFonts.inter(color: DrivoColors.danger, fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ]
        ]),
      ),
    );
  }

  // ── Bản đồ chuyến đi (tài xế) ───────────────────────────────
  bool _isApproaching(String status) =>
      status == 'DriverAccepted' || status == 'DriverArriving' || status == 'DriverAssigned';

  /// Lấy lộ trình xe điện gấp từ vị trí tài xế tới điểm đón (1 lần mỗi chuyến).
  Future<void> _loadApproachRoute() async {
    final b = _activeBooking;
    if (b == null || !_isApproaching(b.status) || !b.hasPickupCoords) return;
    if (_approachForBookingId == b.id) return;
    var me = _myLatLng;
    if (me == null) {
      final r = await LocationService.getCurrent(timeout: const Duration(seconds: 8));
      if (!r.ok) return;
      _lastPos ??= r.position;
      me = LatLng(r.position!.latitude, r.position!.longitude);
    }
    _approachForBookingId = b.id;
    final route = await ApiService.mapsRoute(
      originLat: me.latitude,
      originLng: me.longitude,
      destLat: b.pickupLatitude!,
      destLng: b.pickupLongitude!,
      mode: 'TWO_WHEELER',
    );
    if (!mounted) return;
    setState(() => _approachPolyline = route?.polyline);
  }

  void _fitTripMap(DriverBooking b, {bool force = false}) {
    final key = '${b.id}:${b.status}:${_myLatLng != null}';
    if (!force && _fittedKey == key) return;
    final pts = <LatLng>[
      ?_myLatLng,
      if (b.hasPickupCoords && b.status != 'InProgress') LatLng(b.pickupLatitude!, b.pickupLongitude!),
      if (b.hasDestinationCoords && (b.status == 'InProgress' || b.status == 'DriverArrived'))
        LatLng(b.destinationLatitude!, b.destinationLongitude!),
    ];
    if (pts.isEmpty || _tripMapCtrl == null) return;
    // Chỉ ghi nhớ khi fit thành công; map chưa layout xong thì lần build sau thử lại.
    if (DrivoMap.fitPoints(_tripMapCtrl, pts, padding: 48)) _fittedKey = key;
  }

  Future<void> _openNavigation(DriverBooking b) async {
    // Đang đến đón -> chỉ đường xe 2 bánh tới điểm đón; sau khi đón -> lái ô tô tới điểm đến.
    final toPickup = _isApproaching(b.status);
    double? lat, lng;
    if (toPickup && b.hasPickupCoords) {
      lat = b.pickupLatitude;
      lng = b.pickupLongitude;
    } else if (!toPickup && b.hasDestinationCoords) {
      lat = b.destinationLatitude;
      lng = b.destinationLongitude;
    }
    final dest = lat != null ? '$lat,$lng' : (toPickup ? b.pickupAddress : b.destinationAddress);
    // Ưu tiên ứng dụng bản đồ trên máy (geo: URI), dự phòng: chỉ đường trên openstreetmap.org.
    final geoUri = Uri.parse('geo:${lat != null ? dest : '0,0'}?q=${Uri.encodeComponent(dest)}');
    final webUri = lat != null
        ? Uri.https('www.openstreetmap.org', '/directions', {
            'engine': toPickup ? 'fossgis_osrm_bike' : 'fossgis_osrm_car',
            'route': ';$dest',
          })
        : Uri.https('www.openstreetmap.org', '/search', {'query': dest});
    var ok = false;
    try {
      if (!kIsWeb) ok = await launchUrl(geoUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    try {
      if (!ok) ok = await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không mở được ứng dụng bản đồ')));
    }
  }

  Widget _buildTripMap(DriverBooking b) {
    final approaching = _isApproaching(b.status);
    final markers = <MapMarker>[
      if (_myLatLng != null)
        MapMarker(
          id: 'me',
          position: _myLatLng!,
          kind: MapMarkerKind.scooter,
          title: 'Vị trí của bạn',
        ),
      if (b.hasPickupCoords)
        MapMarker(
          id: 'pickup',
          position: LatLng(b.pickupLatitude!, b.pickupLongitude!),
          kind: MapMarkerKind.pickup,
          title: 'Điểm đón: ${b.pickupAddress}',
        ),
      if (b.hasDestinationCoords && !_isApproaching(b.status))
        MapMarker(
          id: 'destination',
          position: LatLng(b.destinationLatitude!, b.destinationLongitude!),
          kind: MapMarkerKind.destination,
          title: 'Điểm đến: ${b.destinationAddress}',
        ),
    ];

    final polylines = <MapLine>[];
    if (_isApproaching(b.status)) {
      var pts = _approachForBookingId == b.id ? GeoUtils.decodePolyline(_approachPolyline) : <LatLng>[];
      if (pts.isEmpty && _myLatLng != null && b.hasPickupCoords) {
        pts = [_myLatLng!, LatLng(b.pickupLatitude!, b.pickupLongitude!)];
      }
      // Tài xế đã ở ngay điểm đón -> không vẽ đường tới điểm đón.
      if (pts.length >= 2 && GeoUtils.polylineKm(pts) >= 0.03) {
        polylines.add(MapLine(
          id: 'approach',
          points: pts,
          color: DrivoColors.accent,
          width: 5,
          dashed: true,
        ));
      }
    } else {
      var pts = GeoUtils.decodePolyline(b.routePolyline);
      if (pts.isEmpty && b.hasPickupCoords && b.hasDestinationCoords) {
        pts = [
          LatLng(b.pickupLatitude!, b.pickupLongitude!),
          LatLng(b.destinationLatitude!, b.destinationLongitude!),
        ];
      }
      if (pts.length >= 2) {
        polylines.add(MapLine(
          id: 'route',
          points: pts,
          color: DrivoColors.primary,
          width: 5,
        ));
      }
    }

    // Căn lại camera khi đổi trạng thái / lần đầu có GPS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeBooking?.id == b.id) _fitTripMap(b);
    });

    final initial = _myLatLng ??
        (b.hasPickupCoords ? LatLng(b.pickupLatitude!, b.pickupLongitude!) : const LatLng(21.0285, 105.8542));

    double? kmToTarget;
    if (_myLatLng != null) {
      if (approaching && b.hasPickupCoords) {
        kmToTarget = GeoUtils.roadKm(_myLatLng!, LatLng(b.pickupLatitude!, b.pickupLongitude!));
      } else if (!approaching && b.hasDestinationCoords) {
        kmToTarget = GeoUtils.roadKm(_myLatLng!, LatLng(b.destinationLatitude!, b.destinationLongitude!));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 240,
          child: Stack(children: [
            Positioned.fill(
              child: DrivoMap(
                initialTarget: initial,
                initialZoom: 14,
                markers: markers,
                polylines: polylines,
                onMapCreated: (c) {
                  _tripMapCtrl = c;
                  _fittedKey = null;
                  _fitTripMap(b, force: true);
                },
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(
                  icon: const Icon(Icons.center_focus_strong_rounded, color: Color(0xFF0070E0)),
                  tooltip: 'Căn giữa',
                  onPressed: () => _fitTripMap(b, force: true),
                ),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Text(
          kmToTarget == null
              ? (approaching ? 'Di chuyển tới điểm đón bằng xe điện gấp' : 'Lái xe của khách tới điểm đến')
              : approaching
                  ? 'Cách điểm đón ~${kmToTarget.toStringAsFixed(1)} km · ~${GeoUtils.scooterEtaMin(kmToTarget)} phút'
                  : 'Còn ~${kmToTarget.toStringAsFixed(1)} km tới điểm đến',
          style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
        )),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _openNavigation(b),
          style: ElevatedButton.styleFrom(
            backgroundColor: DrivoColors.accent,
            // Theme mặc định minimumSize width = infinity -> nằm trong Row sẽ lỗi layout (vỡ cả màn hình).
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
          label: Text('Chỉ đường', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ]),
    ]);
  }

  /// Bảng phí sau khi hoàn thành chuyến.
  void _showCompletedSummary(DriverBooking b) {
    String money(double v) => '${v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}đ';
    Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(label, style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
        Text(value, style: GoogleFonts.inter(color: color ?? DrivoColors.textPrimary, fontSize: bold ? 17 : 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );
    final total = b.finalPrice ?? (b.estimatedPrice + b.pickupFee + b.waitingFee + b.extraDistanceFee - b.discount);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DrivoColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: DrivoColors.success),
          const SizedBox(width: 8),
          Expanded(child: Text('Chuyến ${b.bookingCode}', style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          row('Cước chuyến', money(b.estimatedPrice)),
          if (b.pickupFee > 0)
            row('Phí đón${b.pickupDistanceKm != null ? ' (${b.pickupDistanceKm!.toStringAsFixed(1)} km)' : ''}', money(b.pickupFee)),
          if (b.waitingFee > 0) row('Phí chờ', money(b.waitingFee)),
          if (b.extraDistanceFee > 0)
            row('Phụ phí quãng đường${b.actualDistanceKm != null ? ' (${b.actualDistanceKm!.toStringAsFixed(1)} km)' : ''}',
                money(b.extraDistanceFee)),
          if (b.discount > 0)
            row('Giảm giá${b.voucherCode != null ? ' (${b.voucherCode})' : ''}', '-${money(b.discount)}',
                color: DrivoColors.success),
          const Divider(color: DrivoColors.border),
          row(b.paymentMethod == 'Cash' ? 'Thu tiền mặt của khách' : 'Khách đã trả qua app', money(total), bold: true),
          // Voucher do DRIVO chịu: hoa hồng tính trên giá trước giảm, DRIVO bù lại phần giảm cho tài xế.
          if (b.driverPayout > 0 && total + b.discount - b.driverPayout > 0)
            row('Hoa hồng nền tảng DRIVO', '-${money(total + b.discount - b.driverPayout)}', color: DrivoColors.danger),
          if (b.driverPayout > 0 && b.discount > 0)
            row('DRIVO bù khuyến mãi', '+${money(b.discount)}', color: DrivoColors.success),
          row('Bạn thực nhận', money(b.driverPayout > 0 ? b.driverPayout : total),
              bold: true, color: DrivoColors.success),
        ]),
        actions: [
          // actions là một hàng ngang -> phải bỏ minimumSize width = infinity của theme.
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSteps(String currentStatus) {
    final steps = [
      ('DriverAccepted', 'Đã nhận cuốc', Icons.check_circle),
      ('DriverArriving', 'Đang đến điểm đón', Icons.navigation_rounded),
      ('DriverArrived', 'Đã đến điểm đón', Icons.location_on_rounded),
      ('InProgress', 'Đang chạy', Icons.play_circle_rounded),
      ('Completed', 'Hoàn thành', Icons.flag_rounded),
    ];

    final statusOrder = ['DriverAccepted', 'DriverArriving', 'DriverArrived', 'InProgress', 'Completed'];
    final currentIdx = statusOrder.indexOf(currentStatus);

    return Column(
      children: steps.asMap().entries.map((entry) {
        final i = entry.key;
        final step = entry.value;
        final isDone = i < currentIdx;
        final isCurrent = i == currentIdx;
        final color = isDone ? DrivoColors.success : (isCurrent ? DrivoColors.primary : DrivoColors.textMuted);
        return Row(children: [
          Icon(isDone ? Icons.check_circle : step.$3, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(step.$2, style: GoogleFonts.inter(
            color: isCurrent ? DrivoColors.textPrimary : color,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
            fontSize: 13,
          ))),
          if (isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: DrivoColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Text('Hiện tại', style: GoogleFonts.inter(color: DrivoColors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
        ]);
      }).expand((w) => [w, const SizedBox(height: 12)]).toList()..removeLast(),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────

class _OfferRouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label, address;
  const _OfferRouteRow({required this.icon, required this.iconColor, required this.label, required this.address});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Icon(icon, color: iconColor, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 10)),
        Text(address, style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );
}

class _OfferStat extends StatelessWidget {
  final IconData icon;
  final String value;
  const _OfferStat(this.icon, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: DrivoColors.bgDark, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, color: DrivoColors.textMuted, size: 14),
        const SizedBox(width: 4),
        Expanded(child: Text(value, style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    ),
  );
}

class _TripRouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label, address;
  const _TripRouteRow({required this.icon, required this.iconColor, required this.label, required this.address});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Icon(icon, color: iconColor, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11)),
        Text(address, style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );
}

/// Thanh đếm ngược lượt ưu tiên riêng cho tài xế; hết giờ gọi onExpired.
class _OfferCountdown extends StatefulWidget {
  final int seconds;
  final VoidCallback onExpired;
  const _OfferCountdown({required this.seconds, required this.onExpired});

  @override
  State<_OfferCountdown> createState() => _OfferCountdownState();
}

class _OfferCountdownState extends State<_OfferCountdown> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        widget.onExpired();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _left <= 30;
    final color = urgent ? DrivoColors.danger : DrivoColors.primary;
    final left = _left.clamp(0, 3600);
    final mmss = '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.timer_outlined, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Cuốc ưu tiên cho bạn · còn $mmss',
              style: GoogleFonts.inter(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: widget.seconds <= 0 ? 0 : (_left.clamp(0, widget.seconds) / widget.seconds),
          minHeight: 5,
          backgroundColor: DrivoColors.border,
          color: color,
        ),
      ),
    ]);
  }
}

class _VoucherNote extends StatelessWidget {
  final DriverBooking booking;
  const _VoucherNote({required this.booking});

  @override
  Widget build(BuildContext context) {
    String k(double v) => '${(v / 1000).toStringAsFixed(0)}K';
    final b = booking;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DrivoColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.local_offer_rounded, color: DrivoColors.warning, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Khách dùng mã${b.voucherCode != null ? ' ${b.voucherCode}' : ''} giảm ${k(b.discount)}, DRIVO bù lại. '
            'Thu nhập của bạn vẫn tính trên cước ${k(b.estimatedPrice)}.',
            style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

class _TripInfoItem extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _TripInfoItem(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11)),
      Text(value, style: GoogleFonts.inter(color: valueColor ?? DrivoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => DrivoCard(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 8),
      Text(value, style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
      Text(label, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11)),
    ]),
  );
}

// ── Earnings Tab ─────────────────────────────────────────────
String _vnd(double v) {
  final neg = v < 0;
  final s = v.abs().toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${neg ? '-' : ''}$s ₫';
}

String _dd(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

class _EarningsTab extends StatefulWidget {
  final DriverProfile? profile;
  const _EarningsTab({super.key, required this.profile});

  @override
  State<_EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends State<_EarningsTab> {
  static const _periods = {'day': 'Ngày', 'week': 'Tuần', 'month': 'Tháng'};

  String _period = 'day';
  DateTime _anchor = DateTime.now();
  DriverEarnings? _data;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await ApiService.getDriverEarnings(_period, _anchor);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] != null) {
        _data = DriverEarnings.fromJson(res['data']);
      } else {
        _error = res['message']?.toString() ?? 'Không tải được thu nhập';
      }
    });
  }

  void _setPeriod(String p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _anchor = DateTime.now();
    });
    _load();
  }

  void _shift(int dir) {
    setState(() {
      _anchor = switch (_period) {
        'week' => _anchor.add(Duration(days: 7 * dir)),
        'month' => DateTime(_anchor.year, _anchor.month + dir, 1),
        _ => _anchor.add(Duration(days: dir)),
      };
    });
    _load();
  }

  bool get _isCurrent {
    final d = _data;
    if (d == null) return true;
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    return !t.isAfter(d.to);
  }

  String get _rangeLabel {
    final d = _data;
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (d.period) {
      case 'week':
        return '${_dd(d.from)} – ${_dd(d.to)}/${d.to.year}';
      case 'month':
        return 'Tháng ${d.from.month}/${d.from.year}';
      default:
        if (d.from == today) return 'Hôm nay, ${_dd(d.from)}';
        if (d.from == today.subtract(const Duration(days: 1))) return 'Hôm qua, ${_dd(d.from)}';
        return '${_dd(d.from)}/${d.from.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            _periodSelector(),
            const SizedBox(height: 12),
            Row(children: [
              IconButton(
                onPressed: _loading ? null : () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded, color: DrivoColors.textPrimary),
              ),
              Expanded(
                child: Text(_rangeLabel,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              IconButton(
                onPressed: _loading || _isCurrent ? null : () => _shift(1),
                icon: Icon(Icons.chevron_right_rounded,
                    color: _isCurrent ? DrivoColors.textMuted : DrivoColors.textPrimary),
              ),
            ]),
            const SizedBox(height: 8),
            if (_loading && d == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: DrivoColors.primary)),
              )
            else if (_error != null && d == null)
              DrivoCard(child: Text(_error!, style: GoogleFonts.inter(color: DrivoColors.danger)))
            else if (d != null) ...[
              Opacity(opacity: _loading ? 0.5 : 1, child: _summaryCard(d)),
              const SizedBox(height: 12),
              _breakdownCard(d),
              if (d.buckets.isNotEmpty) ...[
                const SizedBox(height: 12),
                _chartCard(d),
              ],
              const SizedBox(height: 20),
              SectionHeader('CHUYẾN ĐI TRONG KỲ (${d.tripCount})'),
              if (d.trips.isEmpty)
                DrivoCard(
                  child: Column(children: [
                    const Icon(Icons.history_rounded, color: DrivoColors.textMuted, size: 36),
                    const SizedBox(height: 10),
                    Text('Chưa có chuyến hoàn thành trong kỳ này',
                        style: GoogleFonts.inter(color: DrivoColors.textSecondary)),
                  ]),
                )
              else
                for (final t in d.trips) ...[
                  _EarningsTripTile(trip: t, showDate: d.period != 'day'),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Tổng thu nhập từ trước tới nay: ${_vnd(widget.profile?.totalEarnings ?? 0)}',
                  style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _periodSelector() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: DrivoColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DrivoColors.border),
        ),
        child: Row(
          children: _periods.entries.map((e) {
            final selected = e.key == _period;
            return Expanded(
              child: GestureDetector(
                onTap: () => _setPeriod(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? DrivoColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(e.value,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: selected ? Colors.white : DrivoColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      )),
                ),
              ),
            );
          }).toList(),
        ),
      );

  Widget _summaryCard(DriverEarnings d) => DrivoCard(
        child: Column(children: [
          Text('Thực nhận', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 13)),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(_vnd(d.payout),
                style: GoogleFonts.inter(color: DrivoColors.success, fontSize: 32, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 4),
          Text('${d.tripCount} chuyến hoàn thành',
              style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 13)),
        ]),
      );

  Widget _breakdownCard(DriverEarnings d) {
    Widget row(String label, String value, {Color? color, bool bold = false, String? note}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: GoogleFonts.inter(
                        color: bold ? DrivoColors.textPrimary : DrivoColors.textSecondary,
                        fontSize: 13,
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
                if (note != null)
                  Text(note, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11)),
              ]),
            ),
            Text(value,
                style: GoogleFonts.inter(
                    color: color ?? DrivoColors.textPrimary,
                    fontSize: bold ? 15 : 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ]),
        );

    final owesDriver = d.balanceWithPlatform >= 0;
    return DrivoCard(
      child: Column(children: [
        row('Tổng cước', _vnd(d.grossFare),
            note: d.voucherSupport > 0 ? 'Gồm ${_vnd(d.voucherSupport)} khuyến mãi do DRIVO chịu' : null),
        row('Hoa hồng DRIVO', '-${_vnd(d.commission)}', color: DrivoColors.danger),
        const Divider(color: DrivoColors.border),
        row('Thực nhận', _vnd(d.payout), color: DrivoColors.success, bold: true),
        const SizedBox(height: 6),
        row('Tiền mặt đã thu của khách', _vnd(d.cashCollected)),
        row(
          owesDriver ? 'DRIVO cần trả bạn' : 'Bạn cần nộp lại DRIVO',
          _vnd(d.balanceWithPlatform.abs()),
          color: owesDriver ? DrivoColors.success : DrivoColors.warning,
          note: 'Thực nhận − tiền mặt đã thu',
        ),
      ]),
    );
  }

  Widget _chartCard(DriverEarnings d) {
    final maxPayout = d.buckets.fold<double>(0, (m, b) => b.payout > m ? b.payout : m);
    final showEvery = d.buckets.length > 10 ? 5 : 1;
    return DrivoCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Thực nhận theo ngày', style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < d.buckets.length; i++)
                Expanded(
                  child: Tooltip(
                    message: '${d.buckets[i].date}: ${_vnd(d.buckets[i].payout)} · ${d.buckets[i].trips} chuyến',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: d.buckets.length > 10 ? 1 : 4),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          height: maxPayout <= 0 ? 2 : 2 + 94 * d.buckets[i].payout / maxPayout,
                          decoration: BoxDecoration(
                            color: d.buckets[i].payout > 0 ? DrivoColors.primary : DrivoColors.border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 14,
                          child: (i % showEvery == 0)
                              ? FittedBox(
                                  child: Text(d.buckets[i].label,
                                      style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 10)),
                                )
                              : null,
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _EarningsTripTile extends StatelessWidget {
  final EarningsTrip trip;
  final bool showDate;
  const _EarningsTripTile({required this.trip, required this.showDate});

  @override
  Widget build(BuildContext context) {
    final t = trip.completedAt;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final isCash = trip.paymentMethod == 'Cash';
    return DrivoCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('#${trip.bookingCode}',
                  style: GoogleFonts.inter(color: DrivoColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
              Text(showDate ? '${_dd(t)} · $time' : time,
                  style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11)),
            ]),
          ),
          Text('+${_vnd(trip.payout)}',
              style: GoogleFonts.inter(color: DrivoColors.success, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        Text(
          '${trip.pickupAddress} → ${trip.destinationAddress}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          [
            'Cước ${_vnd(trip.grossFare)}',
            'hoa hồng -${_vnd(trip.commission)}',
            if (trip.discount > 0) 'KM ${_vnd(trip.discount)}',
            isCash ? 'tiền mặt' : 'trả qua app',
          ].join(' · '),
          style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11),
        ),
      ]),
    );
  }
}

// ── Profile Tab ──────────────────────────────────────────────
class _ProfileTab extends StatefulWidget {
  final DriverProfile? profile;
  final AuthUser user;
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;
  const _ProfileTab({required this.profile, required this.user, required this.onChangePassword, required this.onLogout});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  bool _editing = false;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile != null && !_editing) {
      _nameCtrl.text = widget.profile!.fullName;
      _emailCtrl.text = widget.profile!.email ?? '';
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await ApiService.updateDriverProfile({'fullName': _nameCtrl.text, 'email': _emailCtrl.text});
    setState(() { _saving = false; _editing = false; });
    if (res['success'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Cập nhật thành công!'), backgroundColor: DrivoColors.success,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    if (p == null) return const Center(child: CircularProgressIndicator(color: DrivoColors.primary));

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [DrivoColors.primary, DrivoColors.accent]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: DrivoColors.primary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Center(child: Text(p.fullName.split(' ').last[0],
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32))),
          ),
          const SizedBox(height: 12),
          Text(p.fullName, style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            DrivoBadge(p.verificationStatus), const SizedBox(width: 8), DrivoBadge(p.driverStatus),
          ]),
          if (p.isFirstLogin) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: DrivoColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DrivoColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, color: DrivoColors.warning, size: 14),
                const SizedBox(width: 8),
                Text('Vui lòng đổi mật khẩu mặc định', style: GoogleFonts.inter(color: DrivoColors.warning, fontSize: 12)),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          const SectionHeader('THÔNG TIN CÁ NHÂN'),
          DrivoCard(child: Column(children: [
            if (_editing) ...[
              TextField(controller: _nameCtrl, style: const TextStyle(color: DrivoColors.textPrimary), decoration: const InputDecoration(labelText: 'Họ và tên')),
              const SizedBox(height: 12),
              TextField(controller: _emailCtrl, style: const TextStyle(color: DrivoColors.textPrimary), decoration: const InputDecoration(labelText: 'Email')),
            ] else ...[
              _InfoRow(Icons.phone_outlined, 'Số điện thoại', p.phone),
              _InfoRow(Icons.email_outlined, 'Email', p.email ?? '—'),
              _InfoRow(Icons.badge_outlined, 'Số GPLX', p.licenseNumber),
              _InfoRow(Icons.drive_eta_outlined, 'Hạng bằng lái', p.licenseClass ?? '—'),
              _InfoRow(Icons.star_outline, 'Đánh giá', '${p.ratingAverage.toStringAsFixed(1)} ⭐ (${p.totalTrips} chuyến)'),
            ],
            const SizedBox(height: 16),
            Row(children: [
              if (_editing) ...[
                Expanded(child: OutlinedButton(
                  onPressed: () => setState(() => _editing = false),
                  style: OutlinedButton.styleFrom(foregroundColor: DrivoColors.textSecondary, side: const BorderSide(color: DrivoColors.border)),
                  child: const Text('Hủy'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Lưu'),
                )),
              ] else
                Expanded(child: ElevatedButton.icon(
                  onPressed: () { _nameCtrl.text = p.fullName; _emailCtrl.text = p.email ?? ''; setState(() => _editing = true); },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Chỉnh sửa thông tin'),
                  style: ElevatedButton.styleFrom(backgroundColor: DrivoColors.primary.withValues(alpha: 0.15)),
                )),
            ]),
          ])),
          const SizedBox(height: 16),
          const SectionHeader('TÀI KHOẢN'),
          DrivoCard(child: Column(children: [
            _ActionRow(Icons.lock_outline, 'Đổi mật khẩu', DrivoColors.primary, widget.onChangePassword),
            const Divider(color: DrivoColors.border, height: 1),
            _ActionRow(Icons.help_outline, 'Hỗ trợ', DrivoColors.textSecondary, () {}),
            const Divider(color: DrivoColors.border, height: 1),
            _ActionRow(Icons.logout_rounded, 'Đăng xuất', DrivoColors.danger, widget.onLogout),
          ])),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Icon(icon, color: DrivoColors.textMuted, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11)),
        Text(value, style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontWeight: FontWeight.w500)),
      ])),
    ]),
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionRow(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: GoogleFonts.inter(color: color, fontWeight: FontWeight.w500))),
        const Icon(Icons.chevron_right, color: DrivoColors.textMuted, size: 18),
      ]),
    ),
  );
}
