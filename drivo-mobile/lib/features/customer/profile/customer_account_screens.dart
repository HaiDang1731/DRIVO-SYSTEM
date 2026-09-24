import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_service.dart';

const _bg = Color(0xFF080C1A);
const _card = Color(0xFF111827);
const _accent = Color(0xFF6C63FF);

String vndText(double v) =>
    '${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}đ';

/// Server trả giờ UTC không kèm 'Z'.
DateTime? _utc(dynamic s) {
  if (s == null) return null;
  final t = s.toString();
  return DateTime.tryParse(RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(t) ? t : '${t}Z')?.toLocal();
}

String _dateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

// ── Phương thức thanh toán mặc định (lưu trên máy, màn đặt xe đọc lại) ──────────
class PaymentPreference {
  static const _key = 'default_payment_method';
  static const options = <String, IconData>{
    'Tiền mặt': Icons.payments_rounded,
    'Ví điện tử': Icons.account_balance_wallet_rounded,
    'Chuyển khoản QR': Icons.qr_code_2_rounded,
  };

  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    return options.containsKey(v) ? v! : 'Tiền mặt';
  }

  static Future<void> set(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value);
  }
}

Future<void> showPaymentMethodSheet(BuildContext context) async {
  var current = await PaymentPreference.get();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    backgroundColor: _card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Phương thức thanh toán mặc định',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Tự chọn sẵn khi bạn đặt chuyến, vẫn đổi được ở màn đặt xe.',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 12.5)),
            const SizedBox(height: 10),
            for (final e in PaymentPreference.options.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(e.value, color: const Color(0xFF3B82F6)),
                title: Text(e.key, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: e.key == 'Tiền mặt'
                    ? null
                    : Text('Bản demo: thanh toán giả lập', style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5)),
                trailing: current == e.key ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)) : null,
                onTap: () async {
                  await PaymentPreference.set(e.key);
                  setSheet(() => current = e.key);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
          ]),
        ),
      ),
    ),
  );
}

// ── Giới thiệu ─────────────────────────────────────────────────
void showAboutDrivo(BuildContext context) {
  Widget line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13))),
        ]),
      );
  showModalBottomSheet(
    context: context,
    backgroundColor: _card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accent, Color(0xFF3B82F6)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.directions_car_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DRIVO', style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Phiên bản 2.0 (demo)', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 14),
          Text(
            'Dịch vụ thuê tài xế lái hộ chính xe của bạn. Tài xế tới bằng xe điện gấp, '
            'gấp xe bỏ cốp rồi đưa bạn và xe về an toàn.',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          line(Icons.support_agent_rounded, 'Tổng đài hỗ trợ 24/7: 1900 0000 (demo)'),
          line(Icons.email_outlined, 'Email: hotro@drivo.vn (demo)'),
          line(Icons.shield_outlined, 'Tài xế được xác minh GPLX, CCCD trước khi nhận chuyến'),
          const SizedBox(height: 8),
          Text('© 2026 DRIVO', style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5)),
        ]),
      ),
    ),
  );
}

// ── Lịch sử giao dịch ──────────────────────────────────────────
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/bookings/customer-history?page=1&pageSize=100');
    if (!mounted) return;
    setState(() {
      if (res['success'] == true && res['data'] is List) {
        _items = (res['data'] as List)
            .cast<Map<String, dynamic>>()
            .where((b) => b['status'] == 'Completed' && b['finalPrice'] != null)
            .toList();
        _error = null;
      } else {
        _items = [];
        _error = res['message']?.toString() ?? 'Không tải được lịch sử';
      }
    });
  }

  static String _method(String? m) => switch (m) {
        'MockEwallet' => 'Ví điện tử',
        'MockBanking' => 'Chuyển khoản QR',
        _ => 'Tiền mặt',
      };

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final total = (items ?? []).fold<double>(0, (s, b) => s + ((b['finalPrice'] as num?)?.toDouble() ?? 0));
    final saved = (items ?? []).fold<double>(0, (s, b) => s + ((b['discount'] as num?)?.toDouble() ?? 0));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: Text('Lịch sử giao dịch', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      Expanded(child: _stat('Tổng đã thanh toán', vndText(total), Colors.white)),
                      Expanded(child: _stat('Tiết kiệm nhờ khuyến mãi', vndText(saved), const Color(0xFF10B981))),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text('Chưa có giao dịch nào. Các chuyến đã hoàn thành sẽ hiện ở đây.',
                          textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white54)),
                    )
                  else
                    for (final b in items) ...[_tile(b), const SizedBox(height: 10)],
                ],
              ),
            ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.inter(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      ]);

  Widget _tile(Map<String, dynamic> b) {
    final price = (b['finalPrice'] as num?)?.toDouble() ?? 0;
    final discount = (b['discount'] as num?)?.toDouble() ?? 0;
    final done = _utc(b['completedAt'] ?? b['createdAt']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('#${b['bookingCode']}',
                style: GoogleFonts.inter(color: const Color(0xFF8B85FF), fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Text('-${vndText(price)}', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 4),
        Text(
          '${b['pickupAddress']} → ${b['destinationAddress']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(color: Colors.white60, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _chip(_method(b['paymentMethod']), const Color(0xFF3B82F6)),
          if (discount > 0) _chip('${b['voucherCode'] ?? 'Khuyến mãi'} -${vndText(discount)}', const Color(0xFF10B981)),
          if (done != null) _chip(_dateTime(done), Colors.white38),
        ]),
      ]),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
      );
}

// ── Thông báo ──────────────────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.get('/notifications?take=100');
    if (!mounted) return;
    setState(() {
      _items = res['success'] == true
          ? ((res['data']?['items'] as List?) ?? []).cast<Map<String, dynamic>>()
          : [];
    });
  }

  Future<void> _readAll() async {
    await ApiService.post('/notifications/read-all', {});
    _load();
  }

  Future<void> _open(Map<String, dynamic> n) async {
    if (n['isRead'] != true) {
      ApiService.post('/notifications/${n['id']}/read', {});
      setState(() => n['isRead'] = true);
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('${n['title']}', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('${n['message']}', style: GoogleFonts.inter(color: Colors.white70, height: 1.4)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final hasUnread = (items ?? []).any((n) => n['isRead'] != true);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: Text('Thông báo', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _readAll,
              style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
              child: const Text('Đọc tất cả'),
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.notifications_none_rounded, color: Colors.white24, size: 56),
                      const SizedBox(height: 10),
                      Text('Chưa có thông báo nào', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white54)),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final n = items[i];
                        final unread = n['isRead'] != true;
                        final at = _utc(n['createdAt']);
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _open(n),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: unread ? const Color(0xFF17213A) : _card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: unread ? _accent.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.campaign_rounded, color: unread ? _accent : Colors.white38, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${n['title']}',
                                      style: GoogleFonts.inter(
                                          color: Colors.white, fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text('${n['message']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(color: Colors.white60, fontSize: 12.5)),
                                  if (at != null) ...[
                                    const SizedBox(height: 4),
                                    Text(_dateTime(at), style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
                                  ],
                                ]),
                              ),
                              if (unread)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 6),
                                  decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
