import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api_service.dart';
import 'core/tracking_service.dart';
import 'core/theme.dart';
import 'features/auth/screens/onboarding_screen.dart';
import 'features/driver/home/screens/driver_home_screen.dart';
import 'features/customer/home/screens/customer_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const DrivoApp());
}

class DrivoApp extends StatelessWidget {
  const DrivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DRIVO',
      debugShowCheckedModeBanner: false,
      theme: DrivoTheme.theme,
      // Chạm vào vùng trống bất kỳ (kể cả trong bottom sheet/dialog) -> đóng bàn phím.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      home: const _RootRouter(),
    );
  }
}

/// Route điều hướng màn hình dựa theo token và role
class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  AuthUser? _user;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Không có token đã lưu -> thẳng ra onboarding.
    if (ApiService.getToken() == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      // getMe() tự làm mới access token (401) bằng refresh token nếu hết hạn.
      final res = await ApiService.getMe();
      if (res['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        final userJson = prefs.getString('user_json');
        if (userJson != null) {
          final user = AuthUser.fromJson(Map<String, dynamic>.from(jsonDecode(userJson)));
          if (mounted) {
            setState(() {
              _user = user;
              _checking = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    // Token/refresh token đều không còn dùng được -> đăng xuất hẳn để tránh trạng thái lưng chừng.
    await ApiService.clearTokens();
    if (mounted) setState(() => _checking = false);
  }

  void _handleLogin(dynamic user) {
    if (user is AuthUser) {
      setState(() => _user = user);
    }
  }

  Future<void> _handleLogout() async {
    await TrackingService.instance.disconnect();
    await ApiService.logout();
    await ApiService.clearTokens();
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    // Màn hình loading/splash khi đang kiểm tra session
    if (_checking) {
      return Scaffold(
        backgroundColor: DrivoColors.bgDark,
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [DrivoColors.primary, DrivoColors.accent]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.drive_eta_rounded, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: DrivoColors.primary),
          ]),
        ),
      );
    }

    // Chưa đăng nhập -> Onboarding
    if (_user == null) {
      return OnboardingScreen(onLogin: _handleLogin);
    }

    // Route dựa theo role
    if (_user!.isDriver) {
      return DriverHomeScreen(user: _user!, onLogout: _handleLogout);
    }

    // Mặc định -> Customer
    return CustomerHomeScreen(user: _user!, onLogout: _handleLogout);
  }
}
