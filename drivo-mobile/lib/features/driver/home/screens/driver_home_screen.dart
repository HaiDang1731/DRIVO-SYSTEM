import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/api_service.dart';
import '../../../../../core/theme.dart';

class DriverHomeScreen extends StatefulWidget {
  final AuthUser user;
  final VoidCallback onLogout;
  const DriverHomeScreen({super.key, required this.user, required this.onLogout});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  int _tab = 0;
  DriverProfile? _profile;
  bool _loadingProfile = true;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    final res = await ApiService.getDriverProfile();
    if (res['success'] == true) {
      setState(() {
        _profile = DriverProfile.fromJson(res['data']);
        _isOnline = _profile?.driverStatus == 'Online';
        _loadingProfile = false;
      });
      // Nếu lần đầu đăng nhập → nhắc đổi mật khẩu
      if (_profile?.isFirstLogin == true && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showChangePasswordDialog(forced: true));
      }
    } else {
      setState(() => _loadingProfile = false);
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
              decoration: BoxDecoration(color: DrivoColors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
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
          _HomeTab(profile: _profile, isOnline: _isOnline, loading: _loadingProfile,
            onToggleOnline: () => setState(() => _isOnline = !_isOnline)),
          _EarningsTab(profile: _profile),
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
        indicatorColor: DrivoColors.primary.withOpacity(0.2),
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
}

// ── Home Tab ─────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  final DriverProfile? profile;
  final bool isOnline;
  final bool loading;
  final VoidCallback onToggleOnline;
  const _HomeTab({required this.profile, required this.isOnline, required this.loading, required this.onToggleOnline});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: loading
        ? const Center(child: CircularProgressIndicator(color: DrivoColors.primary))
        : SingleChildScrollView(
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
                    profile?.fullName.split(' ').last[0] ?? '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Xin chào!', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
                  Text(profile?.fullName ?? '...', style: GoogleFonts.inter(
                    color: DrivoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16,
                  )),
                ])),
                DrivoBadge(profile?.verificationStatus ?? 'Pending'),
              ]),
              const SizedBox(height: 24),

              // Online Toggle
              DrivoCard(
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isOnline ? '🟢 Đang hoạt động' : '⚫ Ngoại tuyến',
                      style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(isOnline ? 'Đang nhận yêu cầu đặt xe' : 'Bật để nhận chuyến',
                      style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 12)),
                  ])),
                  Switch(
                    value: isOnline,
                    onChanged: profile?.verificationStatus == 'Approved' ? (_) => onToggleOnline() : null,
                    activeColor: DrivoColors.accent,
                    thumbColor: WidgetStateProperty.all(Colors.white),
                  ),
                ]),
              ),

              if (profile?.verificationStatus != 'Approved') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DrivoColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DrivoColors.warning.withOpacity(0.3)),
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
              const SizedBox(height: 24),

              // Stats
              const SectionHeader('THỐNG KÊ'),
              Row(children: [
                Expanded(child: _StatCard('Chuyến đã chạy', '${profile?.totalTrips ?? 0}', Icons.route_rounded, DrivoColors.primary)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard('Đánh giá TB', '${(profile?.ratingAverage ?? 0).toStringAsFixed(1)}⭐', Icons.star_rounded, DrivoColors.warning)),
              ]),
              const SizedBox(height: 24),

              // Recent activity placeholder
              const SectionHeader('HOẠT ĐỘNG GẦN ĐÂY'),
              DrivoCard(
                child: Column(children: [
                  const SizedBox(height: 20),
                  const Icon(Icons.inbox_outlined, color: DrivoColors.textMuted, size: 40),
                  const SizedBox(height: 12),
                  Text('Chưa có chuyến nào', style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 14)),
                  Text('Bật trực tuyến để bắt đầu nhận chuyến', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 20),
                ]),
              ),
            ]),
          ),
    );
  }
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
class _EarningsTab extends StatelessWidget {
  final DriverProfile? profile;
  const _EarningsTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Thu nhập', style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          DrivoCard(
            child: Column(children: [
              Text('Tổng thu nhập', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                '${profile?.totalEarnings.toStringAsFixed(0) ?? '0'} đ',
                style: GoogleFonts.inter(
                  fontSize: 36, fontWeight: FontWeight.w900,
                  foreground: Paint()..shader = const LinearGradient(
                    colors: [DrivoColors.primary, DrivoColors.accent],
                  ).createShader(const Rect.fromLTWH(0, 0, 200, 50)),
                ),
              ),
              const SizedBox(height: 8),
              DrivoBadge('${profile?.totalTrips ?? 0} chuyến đã hoàn thành'),
            ]),
          ),
          const SizedBox(height: 24),
          const SectionHeader('LỊCH SỬ THU NHẬP'),
          DrivoCard(
            child: Column(children: [
              const SizedBox(height: 30),
              const Icon(Icons.bar_chart_outlined, color: DrivoColors.textMuted, size: 48),
              const SizedBox(height: 12),
              Text('Chưa có dữ liệu', style: GoogleFonts.inter(color: DrivoColors.textSecondary)),
              const SizedBox(height: 30),
            ]),
          ),
        ]),
      ),
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
    final res = await ApiService.updateDriverProfile({
      'fullName': _nameCtrl.text,
      'email': _emailCtrl.text,
    });
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
          // Avatar
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [DrivoColors.primary, DrivoColors.accent]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: DrivoColors.primary.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 6))],
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
                color: DrivoColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DrivoColors.warning.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, color: DrivoColors.warning, size: 14),
                const SizedBox(width: 8),
                Text('Vui lòng đổi mật khẩu mặc định', style: GoogleFonts.inter(color: DrivoColors.warning, fontSize: 12)),
              ]),
            ),
          ],
          const SizedBox(height: 24),

          // Info
          const SectionHeader('THÔNG TIN CÁ NHÂN'),
          DrivoCard(
            child: Column(children: [
              if (_editing) ...[
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: DrivoColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Họ và tên'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  style: const TextStyle(color: DrivoColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
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
                    onPressed: () {
                      _nameCtrl.text = p.fullName;
                      _emailCtrl.text = p.email ?? '';
                      setState(() => _editing = true);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Chỉnh sửa thông tin'),
                    style: ElevatedButton.styleFrom(backgroundColor: DrivoColors.primary.withOpacity(0.15)),
                  )),
              ]),
            ]),
          ),
          const SizedBox(height: 16),

          // Actions
          const SectionHeader('TÀI KHOẢN'),
          DrivoCard(
            child: Column(children: [
              _ActionRow(Icons.lock_outline, 'Đổi mật khẩu', DrivoColors.primary, widget.onChangePassword),
              const Divider(color: DrivoColors.border, height: 1),
              _ActionRow(Icons.help_outline, 'Hỗ trợ', DrivoColors.textSecondary, () {}),
              const Divider(color: DrivoColors.border, height: 1),
              _ActionRow(Icons.logout_rounded, 'Đăng xuất', DrivoColors.danger, widget.onLogout),
            ]),
          ),
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
