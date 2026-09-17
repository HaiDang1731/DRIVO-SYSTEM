import 'package:flutter/material.dart';
import 'core/api_service.dart';
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
    // Nếu có token hợp lệ -> tự động lấy user info
    if (ApiService.getToken() != null) {
      try {
        final res = await ApiService.getMe();
        if (res['success'] == true) {
          final loginRes = await ApiService.login('', '');
          // Dùng /auth/me để lấy role, parse từ token claims
          if (mounted) {
            setState(() {
              // getMe chỉ trả roles & userId, cần đọc từ saved prefs hoặc re-login
              // Tạm thời load từ SharedPreferences nếu có
              _checking = false;
            });
            // Thử lấy user đầy đủ từ saved token
            await _loadUserFromToken();
            return;
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _loadUserFromToken() async {
    try {
      // Gọi /auth/me để lấy userId và roles
      final meRes = await ApiService.getMe();
      if (meRes['success'] == true) {
        // Build minimal AuthUser từ data /me
        final data = meRes['data'] ?? meRes;
        final userId = int.tryParse(data['userId']?.toString() ?? '0') ?? 0;
        final roles = List<String>.from(data['roles'] ?? []);

        if (mounted && userId > 0) {
          setState(() {
            _user = AuthUser(
              id: userId,
              fullName: '',   // Sẽ load từ profile sau
              phone: '',
              roles: roles,
            );
            _checking = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  void _handleLogin(dynamic user) {
    if (user is AuthUser) {
      setState(() => _user = user);
    }
  }

  Future<void> _handleLogout() async {
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
