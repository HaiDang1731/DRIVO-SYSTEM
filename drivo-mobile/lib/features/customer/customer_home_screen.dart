import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import 'booking/screens/customer_booking_screen.dart';

// ═══════════════════════════════════════════════
//   DRIVO Customer Home Screen  — Premium Design
// ═══════════════════════════════════════════════

class CustomerHomeScreen extends StatefulWidget {
  final AuthUser user;
  final VoidCallback onLogout;

  const CustomerHomeScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen>
    with TickerProviderStateMixin {
  int _currentTab = 0;
  BookingDetail? _activeBooking;

  AnimationController? _pulseCtrl;
  AnimationController? _floatCtrl;
  Animation<double>? _pulseAnim;
  Animation<double>? _floatAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut),
    );
    _floatAnim = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _floatCtrl!, curve: Curves.easeInOut),
    );

    _checkActiveBooking();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkActiveBooking() async {
    try {
      final res = await ApiService.getActiveBooking();
      if (res['success'] == true && res['data'] != null) {
        if (mounted) setState(() => _activeBooking = BookingDetail.fromJson(res['data']));
      }
    } catch (_) {}
  }

  void _openBooking() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => CustomerBookingScreen(
          user: widget.user,
          initialActiveBooking: _activeBooking,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    ).then((_) => _checkActiveBooking());
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
    ));

    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _HomeTabView(
            user: widget.user,
            activeBooking: _activeBooking,
            onOpenBooking: _openBooking,
            pulseAnim: _pulseAnim ?? const AlwaysStoppedAnimation(1.0),
            floatAnim: _floatAnim ?? const AlwaysStoppedAnimation(0.0),
          ),
          _ActivityTabView(user: widget.user, onOpenBooking: _openBooking),
          _SupportTabView(),
          _ProfileTabView(user: widget.user, onLogout: widget.onLogout),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 80 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1228),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavBtn(0, Icons.home_rounded, Icons.home_outlined, 'Trang chủ'),
            _buildNavBtn(1, Icons.receipt_long_rounded, Icons.receipt_long_outlined, 'Hoạt động'),
            // Center gift button
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showGiftModal();
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 26),
              ),
            ),
            _buildNavBtn(2, Icons.support_agent_rounded, Icons.support_agent_outlined, 'Hỗ trợ'),
            _buildNavBtn(3, Icons.person_rounded, Icons.person_outlined, 'Tài khoản'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBtn(int idx, IconData active, IconData inactive, String label) {
    final isSelected = _currentTab == idx;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currentTab = idx);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? active : inactive,
              color: isSelected ? const Color(0xFF6C63FF) : Colors.white38,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected ? const Color(0xFF6C63FF) : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGiftModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GiftModalSheet(onOpenBooking: _openBooking),
    );
  }
}

// ─────────────────────────────────────────────────────────
// HOME TAB VIEW
// ─────────────────────────────────────────────────────────
class _HomeTabView extends StatelessWidget {
  final AuthUser user;
  final BookingDetail? activeBooking;
  final VoidCallback onOpenBooking;
  final Animation<double> pulseAnim;
  final Animation<double> floatAnim;

  const _HomeTabView({
    required this.user,
    required this.activeBooking,
    required this.onOpenBooking,
    required this.pulseAnim,
    required this.floatAnim,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ─── HERO SLIVER ───
        SliverToBoxAdapter(child: _buildHero(context)),

        // ─── CONTENT ───
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Active booking banner
              if (activeBooking != null) ...[
                const SizedBox(height: 20),
                _buildActiveBanner(context),
              ],

              const SizedBox(height: 24),
              _buildQuickBookCard(context),

              const SizedBox(height: 28),
              _buildSectionLabel('LÁI HỘ & DỊCH VỤ XE'),
              const SizedBox(height: 14),
              _buildServicesGrid(context),

              const SizedBox(height: 28),
              _buildSectionLabel('DỊCH VỤ LIÊN KẾT'),
              const SizedBox(height: 14),
              _buildLinkedGrid(context),

              const SizedBox(height: 28),
              _buildPromoCard(context),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Hero ───────────────────────────────────────────────
  Widget _buildHero(BuildContext context) {
    return Container(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient cosmic
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0B1639),
                  Color(0xFF1A0533),
                  Color(0xFF0D1F47),
                ],
              ),
            ),
          ),

          // Decorative circles
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6C63FF).withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF3B82F6).withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Top Row: Country + Hotline
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildGlassChip(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🇻🇳', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text('Việt Nam',
                                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white60),
                          ],
                        ),
                      ),
                      _buildGlassChip(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF34D399), size: 15),
                            const SizedBox(width: 6),
                            Text('Hotline',
                                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                        onTap: () {},
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Greeting + Avatar
                  Row(
                    children: [
                      // Avatar with glow
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'D',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Xin chào 👋',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.fullName.isNotEmpty ? user.fullName : 'Khách hàng',
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Points pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.04),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars_rounded, color: Color(0xFFFBBF24), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '0 điểm tích lũy',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 14,
                          color: Colors.white24,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Đổi thưởng',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFBBF24),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFFFBBF24)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom fade
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, const Color(0xFF080C1A)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassChip({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  // ── Active Booking Banner ──────────────────────────────
  Widget _buildActiveBanner(BuildContext context) {
    return GestureDetector(
      onTap: onOpenBooking,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF3B82F6).withValues(alpha: 0.2),
              const Color(0xFF6C63FF).withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.navigation_rounded, color: Color(0xFF60A5FA), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đang có chuyến đi #${activeBooking!.bookingCode}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                  ),
                  Text(
                    activeBooking!.statusDisplay,
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF60A5FA), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF60A5FA)),
          ],
        ),
      ),
    );
  }

  // ── Quick Book Card ────────────────────────────────────
  Widget _buildQuickBookCard(BuildContext context) {
    return GestureDetector(
      onTap: onOpenBooking,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6), Color(0xFF06B6D4)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      'Dịch vụ hàng đầu',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Đặt tài xế\nlái hộ ngay',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Đặt chuyến',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: const Color(0xFF6C63FF),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF6C63FF)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.drive_eta_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section Label ──────────────────────────────────────
  Widget _buildSectionLabel(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white70,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  // ── Services Grid ──────────────────────────────────────
  Widget _buildServicesGrid(BuildContext context) {
    final services = [
      _ServiceItem(icon: Icons.directions_car_rounded, label: 'Lái hộ ô tô', color: const Color(0xFF6C63FF), onTap: onOpenBooking, hot: true),
      _ServiceItem(icon: Icons.access_time_filled_rounded, label: 'Thuê theo giờ', color: const Color(0xFF3B82F6), onTap: onOpenBooking),
      _ServiceItem(icon: Icons.calendar_month_rounded, label: 'Thuê theo ngày', color: const Color(0xFF06B6D4), onTap: onOpenBooking),
      _ServiceItem(icon: Icons.two_wheeler_rounded, label: 'Lái hộ xe máy', color: const Color(0xFF10B981), onTap: onOpenBooking),
      _ServiceItem(icon: Icons.verified_user_rounded, label: 'Đăng kiểm hộ', color: const Color(0xFFF59E0B), onTap: () {}),
      _ServiceItem(icon: Icons.car_rental_rounded, label: 'Thuê tài xế & xe', color: const Color(0xFFEF4444), onTap: () {}),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: services.map((s) => _buildServiceCell(s)).toList(),
    );
  }

  Widget _buildServiceCell(_ServiceItem s) {
    return GestureDetector(
      onTap: s.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: s.hot ? s.color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05),
            width: s.hot ? 1.5 : 1,
          ),
          boxShadow: s.hot
              ? [BoxShadow(color: s.color.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 4))]
              : [],
        ),
        child: Stack(
          children: [
            if (s.hot)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: s.color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('HOT', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(s.icon, color: s.color, size: 26),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    s.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Linked Services Grid ───────────────────────────────
  Widget _buildLinkedGrid(BuildContext context) {
    final items = [
      _ServiceItem(icon: Icons.videocam_rounded, label: 'Tra cứu phạt nguội', color: const Color(0xFFF59E0B), onTap: () {}),
      _ServiceItem(icon: Icons.phone_android_rounded, label: 'Thuê xe tự lái', color: const Color(0xFF06B6D4), onTap: () {}),
      _ServiceItem(icon: Icons.handyman_rounded, label: 'Cứu hộ 24/7', color: const Color(0xFFEF4444), onTap: () {}),
    ];

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: item != items.last ? 12 : 0,
            ),
            child: _buildServiceCell(item),
          ),
        );
      }).toList(),
    );
  }

  // ── Promo Card ─────────────────────────────────────────
  Widget _buildPromoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1F2A45),
            const Color(0xFF162032),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.local_offer_rounded, color: Color(0xFFFBBF24), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DRIVO10K - Giảm 10.000đ',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Áp dụng cho chuyến lái hộ đầu tiên của bạn',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onOpenBooking,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)]),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                'Dùng ngay',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool hot;

  const _ServiceItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.hot = false,
  });
}

// ─────────────────────────────────────────────────────────
// GIFT MODAL SHEET
// ─────────────────────────────────────────────────────────
class _GiftModalSheet extends StatelessWidget {
  final VoidCallback onOpenBooking;
  const _GiftModalSheet({required this.onOpenBooking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF0E1228),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.card_giftcard_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text('Voucher & Ưu đãi DRIVO', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          _buildVoucherItem(context, 'DRIVO10K', 'Giảm 10.000đ cho chuyến lái hộ đầu tiên', const Color(0xFF6C63FF), onOpenBooking),
          const SizedBox(height: 12),
          _buildVoucherItem(context, 'HELLO2026', 'Giảm 20.000đ dành cho khách hàng mới', const Color(0xFF3B82F6), onOpenBooking),
        ],
      ),
    );
  }

  Widget _buildVoucherItem(BuildContext ctx, String code, String desc, Color color, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141829),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.confirmation_num_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
                const SizedBox(height: 2),
                Text(desc, style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white54)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text('Dùng', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// ACTIVITY TAB
// ─────────────────────────────────────────────────────────
class _ActivityTabView extends StatefulWidget {
  final AuthUser user;
  final VoidCallback onOpenBooking;
  const _ActivityTabView({required this.user, required this.onOpenBooking});

  @override
  State<_ActivityTabView> createState() => _ActivityTabViewState();
}

class _ActivityTabViewState extends State<_ActivityTabView> {
  List<BookingDetail> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getCustomerHistory();
      if (res['success'] == true && res['data'] != null) {
        final list = (res['data'] as List).map((x) => BookingDetail.fromJson(x)).toList();
        if (mounted) setState(() { _history = list; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1228),
        title: Text('Lịch sử chuyến đi', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF6C63FF)),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF6C63FF), size: 36),
                      ),
                      const SizedBox(height: 16),
                      Text('Chưa có chuyến đi nào', style: GoogleFonts.inter(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Đặt tài xế lái hộ ngay hôm nay!', style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: widget.onOpenBooking,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text('Đặt chuyến ngay', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final b = _history[i];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('#${b.bookingCode}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF6C63FF))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Text(b.statusDisplay, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF10B981))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _tripRow(Icons.trip_origin_rounded, b.pickupAddress, const Color(0xFF6C63FF)),
                          const SizedBox(height: 6),
                          _tripRow(Icons.location_on_rounded, b.destinationAddress, const Color(0xFFEF4444)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _tripRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// SUPPORT TAB
// ─────────────────────────────────────────────────────────
class _SupportTabView extends StatelessWidget {
  const _SupportTabView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1228),
        title: Text('Hỗ trợ 24/7', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.support_agent_rounded, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                Text('Tổng đài hỗ trợ\nDRIVO 24/7', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2)),
                const SizedBox(height: 8),
                Text('Sẵn sàng hỗ trợ bạn kể cả ban đêm và ngày lễ — gọi miễn phí.', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF6C63FF)),
                      const SizedBox(width: 8),
                      Text('Gọi 1900 6868', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFF6C63FF))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _faq('Tài xế có bằng lái và bảo hiểm không?', 'Tất cả tài xế DRIVO đều được kiểm duyệt hồ sơ kỹ lưỡng, có bằng lái hợp lệ và bảo hiểm trách nhiệm dân sự toàn phần.'),
          const SizedBox(height: 10),
          _faq('Xe điện gấp để vào cốp là sao?', 'Tài xế DRIVO mang theo dòng xe điện gấp chuyên dụng nhỏ gọn để sau khi lái xe của bạn đến điểm đến, họ có thể tự di chuyển về — không cần bạn đưa về!'),
          const SizedBox(height: 10),
          _faq('Có thể đặt chuyến cho người thân không?', 'Hoàn toàn có thể! Chọn "Đặt hộ" trong màn hình Đặt chuyến để điền thông tin người nhận khác.'),
        ],
      ),
    );
  }

  Widget _faq(String q, String a) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ExpansionTile(
        iconColor: const Color(0xFF6C63FF),
        collapsedIconColor: Colors.white38,
        title: Text(q, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5, color: Colors.white)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(a, style: GoogleFonts.inter(fontSize: 13, color: Colors.white54, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// PROFILE TAB
// ─────────────────────────────────────────────────────────
class _ProfileTabView extends StatelessWidget {
  final AuthUser user;
  final VoidCallback onLogout;
  const _ProfileTabView({required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B1639), Color(0xFF1A0533)],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 2),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'D',
                        style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(user.fullName, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(user.phone, style: GoogleFonts.inter(fontSize: 14, color: Colors.white54)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _statPill('0 Điểm', '⭐'),
                      const SizedBox(width: 12),
                      _statPill('0 Chuyến', '🚗'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _menuGroup([
                  _menuItem(Icons.directions_car_filled_rounded, 'Danh sách xe của tôi', const Color(0xFF6C63FF)),
                  _menuItem(Icons.credit_card_rounded, 'Phương thức thanh toán', const Color(0xFF3B82F6)),
                  _menuItem(Icons.receipt_long_rounded, 'Lịch sử giao dịch', const Color(0xFF06B6D4)),
                ]),
                const SizedBox(height: 12),
                _menuGroup([
                  _menuItem(Icons.notifications_rounded, 'Thông báo', const Color(0xFFF59E0B)),
                  _menuItem(Icons.security_rounded, 'Bảo mật & Quyền riêng tư', const Color(0xFF10B981)),
                  _menuItem(Icons.info_outline_rounded, 'Về DRIVO v2.0', Colors.white38),
                ]),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: onLogout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
                        const SizedBox(width: 8),
                        Text('Đăng xuất', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFFEF4444))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String emoji) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text('$emoji  $label', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  Widget _menuGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(children: children),
    );
  }

  Widget _menuItem(IconData icon, String title, Color color) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 19),
      ),
      title: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
      trailing: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
      onTap: () {},
    );
  }
}
