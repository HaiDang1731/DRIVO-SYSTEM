import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api_service.dart';
import '../../../core/theme.dart';

String _vnd(double v) {
  final s = v.abs().toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${v < 0 ? '-' : ''}$s ₫';
}

String _signed(double v) => '${v > 0 ? '+' : ''}${_vnd(v)}';

String _time(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Ví ký quỹ tài xế: phải giữ tối thiểu 500.000đ để nhận cuốc. Chuyến tiền mặt trừ hoa hồng,
/// chuyến trả qua app cộng thu nhập. Nạp/rút tạo yêu cầu, DRIVO duyệt sau khi đối chiếu chuyển khoản.
class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  WalletInfo? _w;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = _w == null);
    final res = await ApiService.getWallet();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['success'] == true && res['data'] != null) {
        _w = WalletInfo.fromJson(res['data']);
        _error = null;
      } else {
        _error = res['message']?.toString() ?? 'Không tải được ví';
      }
    });
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? DrivoColors.danger : DrivoColors.success,
    ));
  }

  // ── Nạp tiền ────────────────────────────────────────────────
  Future<void> _topup() async {
    final w = _w;
    if (w == null) return;
    final need = (w.minBalance - w.balance).clamp(0, double.infinity).toDouble();
    final amount = await _askAmount(
      title: 'Nạp tiền vào ví',
      hint: need > 0 ? 'Cần nạp thêm ít nhất ${_vnd(need)} để nhận cuốc' : 'Tối thiểu 50.000 ₫',
      presets: [if (need > 0) (need / 1000).ceil() * 1000.0, 500000, 1000000, 2000000],
      initial: need > 0 ? (need / 1000).ceil() * 1000.0 : 500000,
      confirmLabel: 'Tạo lệnh nạp',
    );
    if (amount == null) return;
    final res = await ApiService.walletTopup(amount);
    if (res['success'] != true) {
      _snack(res['message']?.toString() ?? 'Không tạo được lệnh nạp', error: true);
      return;
    }
    await _load();
    final tx = WalletTx.fromJson(res['data']['transaction']);
    if (mounted) await _showTransferInfo(tx);
  }

  Future<void> _showTransferInfo(WalletTx tx) async {
    final w = _w!;
    Widget line(String label, String value, {bool copy = false, bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11.5)),
                Text(value,
                    style: GoogleFonts.inter(
                        color: strong ? DrivoColors.accent : DrivoColors.textPrimary,
                        fontSize: strong ? 16 : 14,
                        fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
              ]),
            ),
            if (copy)
              IconButton(
                tooltip: 'Sao chép',
                icon: const Icon(Icons.copy_rounded, size: 18, color: DrivoColors.primary),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value.replaceAll(' ₫', '').replaceAll('.', '').trim()));
                  _snack('Đã sao chép $label');
                },
              ),
          ]),
        );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DrivoColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Chuyển khoản để nạp ví',
                style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Ghi ĐÚNG nội dung chuyển khoản để DRIVO cộng tiền vào ví của bạn.',
                style: GoogleFonts.inter(color: DrivoColors.warning, fontSize: 12.5)),
            const SizedBox(height: 12),
            DrivoCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: [
                line('Ngân hàng', w.drivoBankName),
                line('Số tài khoản', w.drivoAccountNumber, copy: true),
                line('Chủ tài khoản', w.drivoAccountHolder),
                line('Số tiền', _vnd(tx.amount), copy: true, strong: true),
                line('Nội dung chuyển khoản', tx.referenceCode ?? '', copy: true, strong: true),
              ]),
            ),
            const SizedBox(height: 10),
            Text('Bản demo: đây là tài khoản giả. DRIVO duyệt lệnh nạp trong trang quản trị (Ví tài xế).',
                style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11.5)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tôi đã chuyển khoản')),
          ]),
        ),
      ),
    );
  }

  // ── Rút tiền ────────────────────────────────────────────────
  Future<void> _withdraw() async {
    final w = _w;
    if (w == null) return;
    if ((w.payoutAccountNumber ?? '').isEmpty) {
      _snack('Vui lòng khai báo Tài khoản nhận tiền trong mục Hồ sơ trước khi rút.', error: true);
      return;
    }
    if (w.withdrawable < 50000) {
      _snack('Chỉ rút được phần vượt mức ký quỹ ${_vnd(w.minBalance)}. Hiện có thể rút ${_vnd(w.withdrawable)}.', error: true);
      return;
    }
    final amount = await _askAmount(
      title: 'Rút tiền về ${w.payoutBankName ?? 'ngân hàng'}',
      hint: 'Có thể rút tối đa ${_vnd(w.withdrawable)} · về TK ${w.payoutAccountNumber} (${w.payoutAccountHolder ?? ''})',
      presets: [w.withdrawable - w.withdrawable % 1000],
      initial: w.withdrawable - w.withdrawable % 1000,
      confirmLabel: 'Gửi yêu cầu rút',
    );
    if (amount == null) return;
    final res = await ApiService.walletWithdraw(amount);
    _snack(res['message']?.toString() ?? (res['success'] == true ? 'Đã gửi yêu cầu' : 'Rút tiền thất bại'),
        error: res['success'] != true);
    _load();
  }

  Future<double?> _askAmount({
    required String title,
    required String hint,
    required List<double> presets,
    required double initial,
    required String confirmLabel,
  }) {
    final ctrl = TextEditingController(text: initial.toStringAsFixed(0));
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DrivoColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(hint, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12.5)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in presets.where((p) => p > 0).toSet())
                ActionChip(
                  label: Text(_vnd(p)),
                  onPressed: () => ctrl.text = p.toStringAsFixed(0),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: DrivoColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Số tiền (₫)'),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: DrivoColors.textSecondary, side: const BorderSide(color: DrivoColors.border)),
                  child: const Text('Hủy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final v = double.tryParse(ctrl.text.trim());
                    if (v == null || v <= 0) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(ctx, v);
                  },
                  child: Text(confirmLabel),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _cancelRequest(WalletTx tx) async {
    final res = await ApiService.cancelWalletRequest(tx.id);
    _snack(res['message']?.toString() ?? 'Đã hủy', error: res['success'] != true);
    _load();
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final w = _w;
    return Scaffold(
      backgroundColor: DrivoColors.bgDark,
      appBar: AppBar(
        backgroundColor: DrivoColors.bgDark,
        foregroundColor: DrivoColors.textPrimary,
        title: Text('Ví tài xế', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DrivoColors.primary))
          : w == null
              ? Center(child: Text(_error ?? 'Lỗi', style: const TextStyle(color: DrivoColors.danger)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _balanceCard(w),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _topup,
                            icon: const Icon(Icons.add_card_rounded, size: 18),
                            label: const Text('Nạp tiền'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _withdraw,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DrivoColors.textPrimary,
                              side: const BorderSide(color: DrivoColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.account_balance_outlined, size: 18),
                            label: const Text('Rút tiền'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _howItWorks(w),
                      const SizedBox(height: 20),
                      const SectionHeader('LỊCH SỬ GIAO DỊCH'),
                      if (w.transactions.isEmpty)
                        DrivoCard(
                          child: Text('Chưa có giao dịch nào. Nạp tiền để bắt đầu nhận cuốc.',
                              style: GoogleFonts.inter(color: DrivoColors.textSecondary)),
                        )
                      else
                        for (final t in w.transactions) ...[_txTile(t), const SizedBox(height: 8)],
                    ],
                  ),
                ),
    );
  }

  Widget _balanceCard(WalletInfo w) => DrivoCard(
        child: Column(children: [
          Text('Số dư ví', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 13)),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(_vnd(w.balance),
                style: GoogleFonts.inter(
                    color: w.canTakeTrips ? DrivoColors.success : DrivoColors.warning,
                    fontSize: 32,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (w.canTakeTrips ? DrivoColors.success : DrivoColors.warning).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              w.canTakeTrips
                  ? 'Đủ ký quỹ ${_vnd(w.minBalance)} · có thể nhận cuốc'
                  : 'Cần nạp thêm ${_vnd(w.minBalance - w.balance)} để nhận cuốc',
              style: GoogleFonts.inter(
                  color: w.canTakeTrips ? DrivoColors.success : DrivoColors.warning,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          Text('Có thể rút: ${_vnd(w.withdrawable)}', style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
        ]),
      );

  Widget _howItWorks(WalletInfo w) => DrivoCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ví hoạt động thế nào?',
              style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 6),
          for (final s in [
            'Giữ tối thiểu ${_vnd(w.minBalance)} trong ví để bật trực tuyến và nhận cuốc.',
            'Chuyến khách trả tiền mặt: bạn giữ tiền mặt, ví tự trừ hoa hồng DRIVO.',
            'Chuyến khách trả qua app: ví tự cộng phần thu nhập của bạn.',
            'Chỉ rút được phần vượt mức ký quỹ, về tài khoản khai trong Hồ sơ.',
          ])
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $s', style: GoogleFonts.inter(color: DrivoColors.textSecondary, fontSize: 12.5)),
            ),
        ]),
      );

  Widget _txTile(WalletTx t) {
    final pending = t.status == 'PENDING';
    final rejected = t.status == 'REJECTED';
    final color = rejected
        ? DrivoColors.textMuted
        : pending
            ? DrivoColors.warning
            : t.amount >= 0
                ? DrivoColors.success
                : DrivoColors.danger;
    return DrivoCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(t.typeLabel,
                style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
          Text(_signed(t.amount),
              style: GoogleFonts.inter(
                  color: color,
                  fontWeight: FontWeight.w800,
                  decoration: rejected ? TextDecoration.lineThrough : null)),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            _time(t.createdAt),
            if (t.bookingCode != null) '#${t.bookingCode}',
            if (pending) 'Chờ DRIVO duyệt',
            if (rejected) 'Đã hủy/từ chối',
            if (t.balanceAfter != null) 'Số dư ${_vnd(t.balanceAfter!)}',
          ].join(' · '),
          style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11.5),
        ),
        if (t.type == 'TOPUP' && pending && t.referenceCode != null) ...[
          const SizedBox(height: 4),
          Text('Nội dung CK: ${t.referenceCode}',
              style: GoogleFonts.inter(color: DrivoColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
        if (rejected && t.note != null) ...[
          const SizedBox(height: 4),
          Text(t.note!, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11.5)),
        ],
        if (pending)
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (t.type == 'TOPUP')
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                onPressed: () => _showTransferInfo(t),
                child: const Text('Xem thông tin CK'),
              ),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 32), foregroundColor: DrivoColors.danger),
              onPressed: () => _cancelRequest(t),
              child: const Text('Hủy yêu cầu'),
            ),
          ]),
      ]),
    );
  }
}
