import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/api_service.dart';
import '../../../../core/theme.dart';

/// Màn hình Đặt chuyến DRIVO mô phỏng chuẩn xác 100% giao diện "Let Me Drive"
class CustomerBookingScreen extends StatefulWidget {
  final AuthUser user;
  final BookingDetail? initialActiveBooking;

  const CustomerBookingScreen({
    super.key,
    required this.user,
    this.initialActiveBooking,
  });

  @override
  State<CustomerBookingScreen> createState() => _CustomerBookingScreenState();
}

class _CustomerBookingScreenState extends State<CustomerBookingScreen>
    with SingleTickerProviderStateMixin {
  // Địa chỉ mặc định khớp 100% với screenshot
  String _pickupAddress = '152/28 Nguyễn Đình Hoàn, Tổ Dân Phố Số 24, Nghĩa Đô, Cầu Giấy, Hà Nội';
  String _destinationAddress = '62 Ngọc Hà, Ba Đình, Hà Nội';
  bool _hasDestination = true;

  // Tính năng độc quyền DRIVO: Cho phép mang xe điện gấp
  bool _allowFoldingScooter = true;

  // Dịch vụ và phương thức
  String _paymentMethod = 'Tiền mặt';
  String _customerNote = '';
  String _promoCode = 'GIAM10K';
  double _promoDiscount = 10000;

  // Quản lý xe
  List<CustomerVehicle> _vehicles = [];
  CustomerVehicle? _selectedVehicle;
  bool _loadingVehicles = true;

  // Giá & tính toán cước
  FareEstimate? _estimate;
  bool _loadingEstimate = false;

  // Trạng thái chuyến đi
  BookingDetail? _activeBooking;
  bool _submitting = false;

  // Animation radar tìm tài xế
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _activeBooking = widget.initialActiveBooking;
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _loadVehicles();
    _fetchEstimate();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    setState(() => _loadingVehicles = true);
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
            _loadingVehicles = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingVehicles = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVehicles = false);
    }
  }

  Future<void> _fetchEstimate() async {
    if (!_hasDestination || _destinationAddress.isEmpty) return;
    setState(() => _loadingEstimate = true);
    try {
      final res = await ApiService.estimateFare({
        'pickupAddress': _pickupAddress,
        'destinationAddress': _destinationAddress,
      });
      if (res['success'] == true && res['data'] != null) {
        if (mounted) {
          setState(() {
            _estimate = FareEstimate.fromJson(res['data']);
            _loadingEstimate = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingEstimate = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEstimate = false);
    }
  }

  Future<void> _createBooking() async {
    if (_submitting) return;
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
        'destinationAddress': _destinationAddress,
        'vehicleId': _selectedVehicle!.id,
        'customerNote': '$_customerNote | Xe điện gấp: ${_allowFoldingScooter ? "Có" : "Không"} | PT: $_paymentMethod',
      });

      if (res['success'] == true && res['data'] != null) {
        final booking = BookingDetail.fromJson(res['data']);
        if (mounted) {
          setState(() {
            _activeBooking = booking;
            _submitting = false;
          });
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

  Future<void> _cancelBooking() async {
    if (_activeBooking == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final res = await ApiService.cancelBooking(
        _activeBooking!.id,
        'Khách hàng thay đổi kế hoạch',
      );
      if (res['success'] == true) {
        if (mounted) {
          setState(() {
            _activeBooking = null;
            _submitting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã hủy chuyến đi thành công')),
          );
        }
      } else {
        if (mounted) setState(() => _submitting = false);
      }
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
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
          // 1. Bản đồ tương tác phong cách Hà Nội với driver pins & route polyline
          Positioned.fill(
            child: _HanoiMapCanvas(
              showRoute: _hasDestination,
              allowFoldingScooter: _allowFoldingScooter,
            ),
          ),

          // 2. Header Top Bar (Back button, Logo Let Me Drive / DRIVO, Map layer icon)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopHeader(),
          ),

          // 3. Floating Route Selector Card (Điểm đón, Điểm dừng, Điểm đến)
          Positioned(
            top: 100,
            left: 16,
            right: 16,
            child: _buildRouteSelectorCard(),
          ),

          // 4. Quick Floating Action Chips (Tư vấn, Đặt trước, Đặt hộ) + Compass button
          Positioned(
            bottom: _activeBooking != null ? 310 : 340,
            left: 16,
            right: 16,
            child: _buildMapActionChips(),
          ),

          // 5. Bottom Sheet / Booking Panel (Thông tin xe, toggle xe điện gấp, giá, đặt chuyến)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _activeBooking != null
                ? _buildActiveBookingTrackingSheet()
                : _buildBookingBottomPanel(),
          ),
        ],
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
                  color: Colors.white.withOpacity(0.92),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF1E293B)),
              ),
            ),

            // Logo Thương hiệu "DRIVO" phong cách Let Me Drive
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF0070E0), Color(0xFF00449E)],
                  ).createShader(bounds),
                  child: Text(
                    'Let Me Drive',
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

            // Nút Chuyển layer bản đồ
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0066CC),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0066CC).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.map_rounded, color: Colors.white, size: 22),
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
        color: const Color(0xFFE5F1FC).withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0055AA).withOpacity(0.12),
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
                          color: const Color(0xFF0070E0).withOpacity(0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _showPickupAddressDialog,
                      child: Text(
                        _pickupAddress,
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
                          color: const Color(0xFFFF3B30).withOpacity(0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _showDestinationAddressDialog,
                      child: Text(
                        _hasDestination ? _destinationAddress : 'Vui lòng chọn điểm đến',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: _hasDestination ? FontWeight.w600 : FontWeight.w500,
                          color: _hasDestination ? const Color(0xFF0F172A) : const Color(0xFF64748B),
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
        // 1. Tư vấn
        _buildPillChip(
          icon: Icons.support_agent_rounded,
          label: 'Tư vấn',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tổng đài hỗ trợ DRIVO 24/7: 1900 6868')),
            );
          },
        ),
        const SizedBox(width: 8),

        // 2. Đặt trước
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
        const Spacer(),

        // 4. Nút định vị GPS / Compass
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.explore_outlined, color: Color(0xFF475569), size: 24),
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
              color: Colors.black.withOpacity(0.08),
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
    final distance = _estimate?.estimatedDistanceKm ?? 4.6;
    final totalFare = (_estimate?.totalEstimatedFare ?? 250000) - _promoDiscount;
    final originalFare = _estimate?.totalEstimatedFare ?? 250000;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
                        color: const Color(0xFF0070E0).withOpacity(0.12),
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _formatCurrency(totalFare),
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0070E0),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_promoDiscount > 0)
                            Text(
                              _formatCurrency(originalFare),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8),
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ],
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
                        '${distance.toStringAsFixed(1)}km',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0070E0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF0070E0), size: 16),
                          const SizedBox(width: 4),
                          Text(
                            _promoDiscount > 0 ? 'Giảm 10.000...' : 'Khuyến mãi',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0070E0),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                      Text(
                        b.statusDisplay,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0070E0),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Mã: #${b.bookingCode}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
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
                      backgroundColor: const Color(0xFF0070E0).withOpacity(0.15),
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
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0F2FE),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.phone_rounded, color: Color(0xFF0070E0), size: 20),
                    ),
                  ],
                ),
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
                        'Đang liên hệ tài xế gần bạn nhất...',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
                      ),
                    ),
                  ],
                ),
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
                        _formatCurrency(b.estimatedPrice),
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0070E0)),
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

  // ── Dialogs: Địa chỉ, Xe, Thanh toán, Khuyến mãi ──────────
  void _showPickupAddressDialog() {
    final ctrl = TextEditingController(text: _pickupAddress);
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
            Text('Thay đổi điểm đón', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.my_location_rounded, color: Color(0xFF0070E0)),
                hintText: 'Nhập địa chỉ đón...',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070E0)),
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  setState(() => _pickupAddress = ctrl.text.trim());
                  _fetchEstimate();
                }
                Navigator.pop(ctx);
              },
              child: const Text('Xác nhận điểm đón', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showDestinationAddressDialog() {
    final ctrl = TextEditingController(text: _destinationAddress);
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
            Text('Chọn điểm đến', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_rounded, color: Color(0xFFFF3B30)),
                hintText: 'Nhập địa chỉ đến...',
              ),
            ),
            const SizedBox(height: 10),
            // Gợi ý địa chỉ nhanh
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('62 Ngọc Hà, Ba Đình'),
                  onPressed: () {
                    ctrl.text = '62 Ngọc Hà, Ba Đình, Hà Nội';
                  },
                ),
                ActionChip(
                  label: const Text('Keangnam Landmark 72'),
                  onPressed: () {
                    ctrl.text = 'Tòa nhà Keangnam, Phạm Hùng, Nam Từ Liêm';
                  },
                ),
                ActionChip(
                  label: const Text('Vincom Bà Triệu'),
                  onPressed: () {
                    ctrl.text = 'Vincom Center, 191 Bà Triệu, Hai Bà Trưng';
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070E0)),
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  setState(() {
                    _destinationAddress = ctrl.text.trim();
                    _hasDestination = true;
                  });
                  _fetchEstimate();
                }
                Navigator.pop(ctx);
              },
              child: const Text('Xác nhận điểm đến', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final v = _vehicles[idx];
                      final isSelected = _selectedVehicle?.id == v.id;
                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF0070E0).withOpacity(0.15) : const Color(0xFFF1F5F9),
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
                    _loadVehicles();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã lưu thông tin xe!')),
                    );
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

  void _showPromoDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mã khuyến mãi', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.confirmation_num_rounded, color: Color(0xFF0070E0)),
              title: const Text('GIAM10K - Giảm ngay 10.000đ'),
              subtitle: const Text('Áp dụng cho chuyến lái hộ đầu tiên'),
              trailing: const Icon(Icons.check_circle_rounded, color: Color(0xFF0070E0)),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget Vẽ Bản Đồ Tương Tác Giống 100% Screenshot "Let Me Drive"
class _HanoiMapCanvas extends StatelessWidget {
  final bool showRoute;
  final bool allowFoldingScooter;

  const _HanoiMapCanvas({
    required this.showRoute,
    required this.allowFoldingScooter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFF3F8),
      child: CustomPaint(
        painter: _MapPainter(showRoute: showRoute),
        child: Stack(
          children: [
            // Các địa danh Hà Nội khớp trên bản đồ
            _buildLandmark(top: 190, left: 160, label: 'TÂY HỒ', isLarge: true),
            _buildLandmark(top: 280, left: 24, label: 'Hoàng Quốc Việt'),
            _buildLandmark(top: 480, left: 160, label: 'Cầu Giấy'),
            _buildLandmark(top: 490, left: 260, label: 'Kim Mã'),

            // Bệnh viện Phổi Trung ương (H)
            _buildHospitalBadge(top: 340, left: 180, label: 'Bệnh viện Phổi\nTrung ương'),

            // Khách sạn Lotte Hà Nội
            _buildHotelBadge(top: 470, left: 250, label: 'Khách sạn Lotte Hà Nội'),

            // Lăng Bác
            _buildMonumentBadge(top: 420, left: 340, label: 'Lăng Chủ tịch\nHồ Chí Minh'),

            // Driver Avatars xung quanh khu vực (như trong ảnh mẫu)
            _buildDriverAvatar(top: 250, left: 320, name: 'Nguyễn Văn A'),
            _buildDriverAvatar(top: 290, left: 280, name: 'Trần Văn B'),
            _buildDriverAvatar(top: 380, left: 180, name: 'Lê Văn C'),
            _buildDriverAvatar(top: 420, left: 195, name: 'Phạm Văn D'),
            _buildDriverAvatar(top: 450, left: 110, name: 'Hoàng Văn E'),
            _buildDriverAvatar(top: 560, left: 300, name: 'Vũ Văn F'),

            // Điểm Đón (Nguyễn Đình Hoàn)
            Positioned(
              top: 330,
              left: 95,
              child: _buildPickupMarker(),
            ),

            // Điểm Đến (62 Ngọc Hà)
            if (showRoute)
              Positioned(
                top: 410,
                left: 330,
                child: _buildDropoffMarker(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandmark({required double top, required double left, required String label, bool isLarge = false}) {
    return Positioned(
      top: top,
      left: left,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: isLarge ? 14 : 10.5,
          fontWeight: isLarge ? FontWeight.w800 : FontWeight.w600,
          color: const Color(0xFF94A3B8),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildHospitalBadge({required double top, required double left, required String label}) {
    return Positioned(
      top: top,
      left: left,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_hospital, color: Colors.white, size: 12),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildHotelBadge({required double top, required double left, required String label}) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hotel_rounded, size: 12, color: Color(0xFFE91E63)),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
          ],
        ),
      ),
    );
  }

  Widget _buildMonumentBadge({required double top, required double left, required String label}) {
    return Positioned(
      top: top,
      left: left,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_rounded, size: 13, color: Color(0xFF8B5CF6)),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
        ],
      ),
    );
  }

  Widget _buildDriverAvatar({required double top, required double left, required String name}) {
    return Positioned(
      top: top,
      left: left,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF0070E0),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0070E0).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0070E0),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.my_location_rounded, color: Colors.white, size: 12),
              const SizedBox(width: 4),
              Text(
                'Điểm đón bạn',
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        ),
        Container(
          width: 2,
          height: 8,
          color: const Color(0xFF0070E0),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF0070E0),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }

  Widget _buildDropoffMarker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.white, size: 12),
              const SizedBox(width: 4),
              Text(
                'Điểm trả xe',
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        ),
        Container(
          width: 2,
          height: 8,
          color: const Color(0xFFFF3B30),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFFFF3B30),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

/// CustomPainter vẽ đường phố, mặt hồ nước và lộ trình xe chạy
class _MapPainter extends CustomPainter {
  final bool showRoute;

  _MapPainter({required this.showRoute});

  @override
  void paint(Canvas canvas, Size size) {
    final lakePaint = Paint()
      ..color = const Color(0xFFC7E2F7)
      ..style = PaintingStyle.fill;

    // 1. Hồ Tây & Hồ Trúc Bạch
    final lakePath = Path();
    lakePath.moveTo(size.width * 0.45, 0);
    lakePath.cubicTo(
      size.width * 0.4, size.height * 0.15,
      size.width * 0.85, size.height * 0.12,
      size.width * 0.8, size.height * 0.28,
    );
    lakePath.cubicTo(
      size.width * 0.75, size.height * 0.38,
      size.width * 0.55, size.height * 0.35,
      size.width * 0.6, size.height * 0.22,
    );
    lakePath.cubicTo(
      size.width * 0.45, size.height * 0.25,
      size.width * 0.35, size.height * 0.1,
      size.width * 0.45, 0,
    );
    lakePath.close();
    canvas.drawPath(lakePath, lakePaint);

    // 2. Mạng lưới đường xá
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;

    final roadBorderPaint = Paint()
      ..color = const Color(0xFFD6DFE8)
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke;

    // Tuyến đường Hoàng Quốc Việt
    final hqv = Path()
      ..moveTo(0, size.height * 0.32)
      ..lineTo(size.width * 0.4, size.height * 0.32);
    canvas.drawPath(hqv, roadBorderPaint);
    canvas.drawPath(hqv, roadPaint);

    // Tuyến Vành Đai 2 / Võ Chí Công
    final vd2 = Path()
      ..moveTo(size.width * 0.32, 0)
      ..lineTo(size.width * 0.32, size.height * 0.7);
    canvas.drawPath(vd2, roadBorderPaint);
    canvas.drawPath(vd2, roadPaint);

    // Tuyến Cầu Giấy - Kim Mã - Nguyễn Thái Học
    final cg = Path()
      ..moveTo(0, size.height * 0.52)
      ..cubicTo(
        size.width * 0.3, size.height * 0.52,
        size.width * 0.6, size.height * 0.55,
        size.width, size.height * 0.54,
      );
    canvas.drawPath(cg, roadBorderPaint);
    canvas.drawPath(cg, roadPaint);

    // 3. Đường Lộ trình Xanh (Route Polyline) từ Nguyễn Đình Hoàn đến Ngọc Hà
    if (showRoute) {
      final routeBorderPaint = Paint()
        ..color = const Color(0xFF0056B3)
        ..strokeWidth = 6.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final routePaint = Paint()
        ..color = const Color(0xFF007BF0)
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final routePath = Path();
      // Điểm đón: Nguyễn Đình Hoàn (khoảng x: 105, y: 350)
      routePath.moveTo(110, 360);
      routePath.lineTo(110, 340);
      routePath.lineTo(135, 340);
      routePath.lineTo(135, 375);
      routePath.cubicTo(160, 380, 210, 375, 235, 385);
      routePath.cubicTo(265, 395, 290, 420, 340, 425);

      canvas.drawPath(routePath, routeBorderPaint);
      canvas.drawPath(routePath, routePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => oldDelegate.showRoute != showRoute;
}
