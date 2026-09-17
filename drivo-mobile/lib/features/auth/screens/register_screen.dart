import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api_service.dart';

class RegisterScreen extends StatefulWidget {
  final Function(dynamic) onLogin;
  const RegisterScreen({super.key, required this.onLogin});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _loading        = false;
  String? _errorMsg;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _errorMsg = null; });

    try {
      // 1. Đăng ký
      final regRes = await ApiService.register(
        fullName: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passCtrl.text,
        role: 'CUSTOMER',
      );

      if (regRes['success'] != true) {
        setState(() {
          _errorMsg = regRes['message'] ?? 'Đăng ký thất bại. Vui lòng thử lại.';
          _loading = false;
        });
        return;
      }

      // 2. Tự động đăng nhập
      final loginRes = await ApiService.login(
        _phoneCtrl.text.trim(), _passCtrl.text,
      );

      if (loginRes['success'] == true && loginRes['data'] != null) {
        final data = loginRes['data'];
        await ApiService.saveTokens(data['accessToken'], data['refreshToken']);
        final user = AuthUser.fromJson(data['user']);
        if (mounted) widget.onLogin(user);
      } else {
        if (mounted) {
          setState(() {
            _errorMsg = 'Đăng ký thành công! Vui lòng đăng nhập.';
            _loading = false;
          });
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMsg = 'Lỗi kết nối. Kiểm tra mạng và thử lại.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background glow
          Positioned(
            top: -80, right: -60,
            child: Container(
              width: 240, height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF6C63FF).withValues(alpha: 0.3),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                      ),
                    ),

                    const SizedBox(height: 32),

                    Text('Tạo tài khoản',
                      style: GoogleFonts.poppins(
                        fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Đăng ký miễn phí và đặt tài xế lái hộ ngay hôm nay',
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white54, height: 1.5),
                    ),

                    const SizedBox(height: 36),

                    // Form fields
                    _buildField(
                      controller: _nameCtrl,
                      label: 'Họ và tên',
                      hint: 'Nguyễn Văn A',
                      icon: Icons.person_rounded,
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Vui lòng nhập họ tên (tối thiểu 2 ký tự)' : null,
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      controller: _phoneCtrl,
                      label: 'Số điện thoại',
                      hint: '0901 234 567',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Vui lòng nhập số điện thoại';
                        if (v.length < 10 || v.length > 11) return 'Số điện thoại không hợp lệ';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      controller: _passCtrl,
                      label: 'Mật khẩu',
                      hint: 'Tối thiểu 6 ký tự',
                      icon: Icons.lock_rounded,
                      obscure: _obscurePass,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: Colors.white38, size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Mật khẩu tối thiểu 6 ký tự' : null,
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      controller: _confirmCtrl,
                      label: 'Xác nhận mật khẩu',
                      hint: 'Nhập lại mật khẩu',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscureConfirm,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: Colors.white38, size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      validator: (v) => v != _passCtrl.text ? 'Mật khẩu không khớp' : null,
                    ),

                    // Error message
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_errorMsg!,
                                style: GoogleFonts.inter(color: const Color(0xFFEF4444), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Submit button
                    GestureDetector(
                      onTap: _loading ? null : _submit,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 17),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _loading
                                ? [Colors.grey.shade700, Colors.grey.shade600]
                                : [const Color(0xFF6C63FF), const Color(0xFF3B82F6)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _loading ? [] : [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withValues(alpha: 0.45),
                              blurRadius: 20, offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5,
                                  ),
                                )
                              : Text('Đăng ký ngay',
                                  style: GoogleFonts.inter(
                                    fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: RichText(
                          text: TextSpan(
                            text: 'Đã có tài khoản? ',
                            style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
                            children: [
                              TextSpan(
                                text: 'Đăng nhập',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF6C63FF),
                                  fontWeight: FontWeight.w700, fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70,
        )),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
            ),
            errorStyle: GoogleFonts.inter(color: const Color(0xFFEF4444), fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          ),
        ),
      ],
    );
  }
}
