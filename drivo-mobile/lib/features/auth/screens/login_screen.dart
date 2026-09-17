import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_service.dart';
import '../../../core/theme.dart';

class LoginScreen extends StatefulWidget {
  final Function(AuthUser) onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  String? _error;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_phoneCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.login(_phoneCtrl.text.trim(), _passCtrl.text.trim());
      if (res['success'] == true) {
        final data = res['data'];
        await ApiService.saveTokens(data['accessToken'], data['refreshToken']);
        final user = AuthUser.fromJson(data['user']);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_json', data['user'].toString());
        widget.onLogin(user);
      } else {
        setState(() { _error = res['message'] ?? 'Đăng nhập thất bại'; });
      }
    } catch (e) {
      setState(() { _error = 'Không thể kết nối server. Kiểm tra kết nối mạng.'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0F1A), Color(0xFF16162A), Color(0xFF0F0F1A)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(),
                      // Logo
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [DrivoColors.primary, DrivoColors.accent]),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: DrivoColors.primary.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
                        ),
                        child: const Icon(Icons.directions_car_rounded, color: Colors.white, size: 40),
                      ),
                      const SizedBox(height: 20),
                      Text('DRIVO', style: GoogleFonts.inter(
                        fontSize: 36, fontWeight: FontWeight.w900, color: DrivoColors.textPrimary, letterSpacing: -1,
                      )),
                      const SizedBox(height: 6),
                      Text('Ứng dụng đặt tài xế thông minh', style: GoogleFonts.inter(
                        fontSize: 14, color: DrivoColors.textMuted,
                      )),
                      const SizedBox(height: 48),

                      // Card
                      DrivoCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Đăng nhập', style: GoogleFonts.inter(
                              fontSize: 20, fontWeight: FontWeight.w700, color: DrivoColors.textPrimary,
                            )),
                            const SizedBox(height: 4),
                            Text('Nhập thông tin tài khoản để tiếp tục', style: GoogleFonts.inter(
                              fontSize: 13, color: DrivoColors.textSecondary,
                            )),
                            const SizedBox(height: 24),

                            if (_error != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: DrivoColors.danger.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: DrivoColors.danger.withOpacity(0.35)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.warning_rounded, color: DrivoColors.danger, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_error!, style: const TextStyle(color: DrivoColors.danger, fontSize: 13))),
                                ]),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Phone
                            TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: DrivoColors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'Số điện thoại',
                                prefixIcon: Icon(Icons.phone_outlined, color: DrivoColors.textMuted),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Password
                            TextField(
                              controller: _passCtrl,
                              obscureText: !_showPass,
                              style: const TextStyle(color: DrivoColors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'Mật khẩu',
                                prefixIcon: const Icon(Icons.lock_outline, color: DrivoColors.textMuted),
                                suffixIcon: IconButton(
                                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility, color: DrivoColors.textMuted),
                                  onPressed: () => setState(() => _showPass = !_showPass),
                                ),
                              ),
                              onSubmitted: (_) => _login(),
                            ),
                            const SizedBox(height: 24),

                            DrivoPrimaryButton(
                              label: 'Đăng nhập',
                              icon: Icons.login_rounded,
                              loading: _loading,
                              onTap: _login,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      Text('Tài khoản của bạn do quản trị viên cấp', style: GoogleFonts.inter(
                        fontSize: 12, color: DrivoColors.textMuted,
                      )),
                      const Spacer(),
                      Text('DRIVO v1.0 © 2026', style: GoogleFonts.inter(fontSize: 11, color: DrivoColors.textMuted)),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
