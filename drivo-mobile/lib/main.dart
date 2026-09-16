import 'package:flutter/material.dart';
import 'core/api_service.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/driver/driver_home_screen.dart';
import 'features/customer/customer_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init(); // load saved token từ SharedPreferences
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

/// Route đến đúng màn hình dựa theo token và role
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
    // Nếu có token hợp lệ → tự động lấy user info
    if (ApiService.getToken() != null) {
      try {
        final res = await ApiService.getMe();
        if (res['success'] == true) {
          setState(() {
            _user = AuthUser.fromJson(res['data']);
            _checking = false;
          });
          return;
        }
      } catch (_) {}
    }
    setState(() => _checking = false);
  }

  void _handleLogin(AuthUser user) => setState(() => _user = user);

  Future<void> _handleLogout() async {
    await ApiService.logout();
    await ApiService.clearTokens();
    setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
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
              child: const Icon(Icons.directions_car_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: DrivoColors.primary),
          ]),
        ),
      );
    }

    if (_user == null) {
      return LoginScreen(onLogin: _handleLogin);
    }

    // Route dựa theo role
    if (_user!.isDriver) {
      return DriverHomeScreen(user: _user!, onLogout: _handleLogout);
    }

    // Mặc định → Customer
    return CustomerHomeScreen(user: _user!, onLogout: _handleLogout);
  }
}
