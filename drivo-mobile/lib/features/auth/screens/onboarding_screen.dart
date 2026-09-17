import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final Function(dynamic) onLogin;
  const OnboardingScreen({super.key, required this.onLogin});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
    ));
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _goLogin() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LoginScreen(onLogin: widget.onLogin),
    ));
  }

  void _goRegister() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RegisterScreen(onLogin: widget.onLogin),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background gradient ──────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0B1639), Color(0xFF1A0533), Color(0xFF0D1F47)],
              ),
            ),
          ),

          // ── Glow circles ────────────────────────────────────
          Positioned(
            top: -80, right: -60,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF6C63FF).withValues(alpha: 0.35),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: 100, left: -60,
            child: Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF3B82F6).withValues(alpha: 0.25),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          // ── Main content ────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 60),

                      // Logo
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                              blurRadius: 24, spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.drive_eta_rounded, color: Colors.white, size: 38),
                      ),

                      const SizedBox(height: 28),

                      // Brand name
                      Text('DRIVO',
                        style: GoogleFonts.poppins(
                          fontSize: 42, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 2,
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Tagline
                      Text(
                        'Tài xế lái hộ\nchuẩn chuyên nghiệp.',
                        style: GoogleFonts.poppins(
                          fontSize: 26, fontWeight: FontWeight.w700,
                          color: Colors.white, height: 1.25,
                        ),
                      ),

                      const SizedBox(height: 16),

                      Text(
                        'Uống xong, về nhà an toàn.\nTài xế DRIVO đến tận nơi,\nlái xe của bạn về đích.',
                        style: GoogleFonts.inter(
                          fontSize: 15, color: Colors.white60, height: 1.7,
                        ),
                      ),

                      const Spacer(),

                      // Feature pills
                      Wrap(
                        spacing: 10, runSpacing: 10,
                        children: [
                          _pill(Icons.verified_rounded, 'Tài xế được kiểm duyệt'),
                          _pill(Icons.electric_bike_rounded, 'Xe điện gấp DRIVO'),
                          _pill(Icons.shield_rounded, 'An toàn 24/7'),
                          _pill(Icons.payment_rounded, 'Giá cố định, minh bạch'),
                        ],
                      ),

                      const SizedBox(height: 40),

                      // CTA buttons
                      _buildRegisterBtn(),
                      const SizedBox(height: 14),
                      _buildLoginBtn(),
                      const SizedBox(height: 16),

                      Center(
                        child: Text(
                          'Bằng cách tiếp tục, bạn đồng ý với\nĐiều khoản dịch vụ & Chính sách bảo mật của DRIVO',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 11.5, color: Colors.white30, height: 1.6,
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF6C63FF), size: 14),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(
            fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70,
          )),
        ],
      ),
    );
  }

  Widget _buildRegisterBtn() {
    return GestureDetector(
      onTap: _goRegister,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.45),
              blurRadius: 20, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text('Tạo tài khoản miễn phí',
            style: GoogleFonts.inter(
              fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginBtn() {
    return GestureDetector(
      onTap: _goLogin,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Center(
          child: Text('Đã có tài khoản? Đăng nhập',
            style: GoogleFonts.inter(
              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
