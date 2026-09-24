import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Một lý do hủy chuyến (mã gửi lên API + nhãn hiển thị).
class CancelReason {
  final String code;
  final String label;
  final String? hint;
  final bool enabled;
  /// true = lần hủy này không tính vào tỉ lệ hoàn thành của tài xế.
  final bool noFault;

  const CancelReason(this.code, this.label, {this.hint, this.enabled = true, this.noFault = false});
}

class CancelChoice {
  final String code;
  final String? note;
  const CancelChoice(this.code, this.note);
}

/// Hộp chọn lý do hủy. [dark] = giao diện tài xế (nền tối), còn lại là giao diện khách (nền sáng).
/// Lý do mã OTHER bắt buộc nhập ghi chú.
Future<CancelChoice?> showCancelReasonSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<CancelReason> reasons,
  bool dark = false,
}) async {
  final bg = dark ? const Color(0xFF16162A) : Colors.white;
  final fg = dark ? const Color(0xFFF0F0FF) : const Color(0xFF0F172A);
  final muted = dark ? const Color(0xFF8888AA) : const Color(0xFF64748B);
  const danger = Color(0xFFEF4444);
  const ok = Color(0xFF10B981);
  final noteCtrl = TextEditingController();
  String? selected;
  String? error;

  final result = await showModalBottomSheet<CancelChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      void submit() {
        if (selected == null) {
          setS(() => error = 'Vui lòng chọn lý do hủy');
          return;
        }
        final note = noteCtrl.text.trim();
        if (selected == 'OTHER' && note.isEmpty) {
          setS(() => error = 'Vui lòng ghi rõ lý do');
          return;
        }
        FocusScope.of(ctx).unfocus();
        Navigator.pop(ctx, CancelChoice(selected!, note.isEmpty ? null : note));
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: muted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: fg)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 12.5, color: muted)),
            ],
            const SizedBox(height: 12),
            for (final r in reasons)
              Opacity(
                opacity: r.enabled ? 1 : 0.45,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: r.enabled ? () => setS(() { selected = r.code; error = null; }) : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected == r.code ? danger : muted.withValues(alpha: 0.25),
                        width: selected == r.code ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        selected == r.code ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected == r.code ? danger : muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
                          if (r.hint != null)
                            Text(r.hint!, style: GoogleFonts.inter(fontSize: 11.5, color: r.noFault && r.enabled ? ok : muted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            TextField(
              controller: noteCtrl,
              maxLength: 300,
              maxLines: 2,
              style: GoogleFonts.inter(fontSize: 13.5, color: fg),
              decoration: InputDecoration(
                hintText: selected == 'OTHER' ? 'Ghi rõ lý do (bắt buộc)' : 'Ghi chú thêm (không bắt buộc)',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: muted),
                counterStyle: GoogleFonts.inter(fontSize: 10, color: muted),
                filled: true,
                fillColor: dark ? const Color(0x0AFFFFFF) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: GoogleFonts.inter(fontSize: 12.5, color: danger, fontWeight: FontWeight.w600)),
              ),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    FocusScope.of(ctx).unfocus();
                    Navigator.pop(ctx);
                  },
                  child: Text('Không hủy', style: GoogleFonts.inter(color: muted, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: submit,
                  child: Text('Xác nhận hủy', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ]),
        ),
      );
    }),
  );
  // Chờ sheet chạy xong hiệu ứng đóng (và bàn phím hạ xuống) rồi mới dispose / cho màn gọi đổi giao diện,
  // tránh lỗi "_dependents.isEmpty" khi TextField còn trên cây widget.
  await Future.delayed(const Duration(milliseconds: 400));
  noteCtrl.dispose();
  return result;
}

/// Phí chờ ước tính (giống server): (số phút chờ tròn xuống − phút miễn phí) × giá/phút, làm tròn 1.000đ.
double estimateWaitingFee(Duration waited, int freeMin, double pricePerMin) {
  final extra = waited.inMinutes - freeMin;
  if (extra <= 0 || pricePerMin <= 0) return 0;
  return (extra * pricePerMin / 1000).round() * 1000.0;
}

String _mmss(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _vnd(double v) {
  final s = v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$sđ';
}

/// Đồng hồ chờ tại điểm đón: đếm ngược thời gian miễn phí (theo bảng giá admin), hết thì hiện phí chờ đang tính.
/// [builder] nhận trạng thái để màn hình tự thêm nút (vd. tài xế: "Khách vẫn đi" / "Hủy").
class WaitingTimerCard extends StatefulWidget {
  final DateTime arrivedAt;
  final int freeWaitingMin;
  final double waitingPricePerMin;
  final bool dark;
  /// Dòng mô tả thêm dưới đồng hồ (tùy vai trò).
  final String Function(bool overFree)? note;
  final Widget Function(BuildContext context, bool overFree)? actions;

  const WaitingTimerCard({
    super.key,
    required this.arrivedAt,
    required this.freeWaitingMin,
    required this.waitingPricePerMin,
    this.dark = false,
    this.note,
    this.actions,
  });

  @override
  State<WaitingTimerCard> createState() => _WaitingTimerCardState();
}

class _WaitingTimerCardState extends State<WaitingTimerCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var waited = DateTime.now().difference(widget.arrivedAt);
    if (waited.isNegative) waited = Duration.zero;
    final free = Duration(minutes: widget.freeWaitingMin);
    final overFree = waited >= free;
    final color = overFree ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final fg = widget.dark ? const Color(0xFFF0F0FF) : const Color(0xFF0F172A);
    final muted = widget.dark ? const Color(0xFF8888AA) : const Color(0xFF64748B);
    final fee = estimateWaitingFee(waited, widget.freeWaitingMin, widget.waitingPricePerMin);

    final headline = overFree
        ? (widget.waitingPricePerMin > 0
            ? 'Đang tính phí chờ ${_vnd(widget.waitingPricePerMin)}/phút'
            : 'Đã hết thời gian chờ miễn phí')
        : 'Miễn phí chờ ${widget.freeWaitingMin} phút';
    final big = overFree ? 'Đã chờ ${_mmss(waited)}' : 'Còn ${_mmss(free - waited)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(overFree ? Icons.timer_rounded : Icons.hourglass_bottom_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(headline, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ),
          Text(big, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ]),
        if (overFree && fee > 0) ...[
          const SizedBox(height: 4),
          Text('Phí chờ hiện tại: ${_vnd(fee)}',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ],
        if (widget.note != null) ...[
          const SizedBox(height: 4),
          Text(widget.note!(overFree), style: GoogleFonts.inter(fontSize: 12, color: muted)),
        ],
        if (widget.actions != null) widget.actions!(context, overFree),
      ]),
    );
  }
}
