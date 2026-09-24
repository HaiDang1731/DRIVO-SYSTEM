import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api_service.dart';
import '../../../core/theme.dart';

/// Màn Hồ sơ của tài xế: thông tin cá nhân + CCCD, GPLX, ảnh giấy tờ, liên hệ khẩn cấp, tài khoản nhận tiền.
/// Mỗi mục sửa riêng trong bottom sheet. Đổi GPLX/CCCD/ngày sinh/tài khoản nhận tiền hoặc tải ảnh mới
/// khi đã được duyệt -> DRIVO duyệt lại (tài xế vẫn chạy được).
class DriverProfileView extends StatefulWidget {
  final DriverProfile? profile;
  final VoidCallback onChanged;
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;

  const DriverProfileView({
    super.key,
    required this.profile,
    required this.onChanged,
    required this.onChangePassword,
    required this.onLogout,
  });

  @override
  State<DriverProfileView> createState() => _DriverProfileViewState();
}

enum _FieldKind { text, phone, digits, number, date, gender }

class _Field {
  final String key;
  final String label;
  final _FieldKind kind;
  final String? hint;
  final bool upper;
  const _Field(this.key, this.label, {this.kind = _FieldKind.text, this.hint, this.upper = false});
}

const _docTypes = <String, String>{
  'DRIVER_LICENSE_FRONT': 'GPLX mặt trước',
  'DRIVER_LICENSE_BACK': 'GPLX mặt sau',
  'CCCD_FRONT': 'CCCD mặt trước',
  'CCCD_BACK': 'CCCD mặt sau',
  'PROFILE_PHOTO': 'Ảnh chân dung',
};

const _genderLabels = {'MALE': 'Nam', 'FEMALE': 'Nữ', 'OTHER': 'Khác'};

String _fmtDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _show(dynamic v) => (v == null || v.toString().trim().isEmpty) ? '—' : v.toString();

/// Che bớt số nhạy cảm: 0123456789 -> ••••••6789
String _mask(String? v, {int keep = 4}) {
  if (v == null || v.isEmpty) return '—';
  if (v.length <= keep) return v;
  return '${'•' * (v.length - keep)}${v.substring(v.length - keep)}';
}

class _DriverProfileViewState extends State<DriverProfileView> {
  String? _uploadingType;

  Map<String, dynamic> get _raw => widget.profile?.raw ?? const {};

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? DrivoColors.danger : DrivoColors.success,
    ));
  }

  // ── Mức độ hoàn thiện hồ sơ ─────────────────────────────────
  List<String> _missing(DriverProfile p) {
    final r = p.raw;
    bool empty(String k) => r[k] == null || r[k].toString().trim().isEmpty;
    return [
      if (empty('dateOfBirth')) 'Ngày sinh',
      if (empty('idCardNumber')) 'Số CCCD',
      if (empty('licenseNumber')) 'Số GPLX',
      if (empty('licenseClass')) 'Hạng bằng',
      if (empty('licenseExpiryDate')) 'Hạn GPLX',
      if (empty('emergencyContactPhone')) 'Liên hệ khẩn cấp',
      if (empty('bankAccountNumber')) 'Tài khoản nhận tiền',
      for (final e in _docTypes.entries)
        if (p.doc(e.key) == null) 'Ảnh ${e.value}',
    ];
  }

  // ── Sửa 1 mục ───────────────────────────────────────────────
  Future<void> _editSection(String title, List<_Field> fields, {String? note}) async {
    final ctrls = {for (final f in fields) f.key: TextEditingController(text: _raw[f.key]?.toString() ?? '')};
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DrivoColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> save() async {
          final body = <String, dynamic>{};
          for (final f in fields) {
            final v = ctrls[f.key]!.text.trim();
            if (f.kind == _FieldKind.number) {
              if (v.isNotEmpty) body[f.key] = int.tryParse(v);
            } else if (f.kind == _FieldKind.date) {
              if (v.isNotEmpty) body[f.key] = v;
            } else {
              body[f.key] = f.upper ? v.toUpperCase() : v;
            }
          }
          setSheet(() {
            saving = true;
            error = null;
          });
          final res = await ApiService.updateDriverProfile(body);
          if (!ctx.mounted) return;
          if (res['success'] == true) {
            Navigator.pop(ctx);
            _snack(res['message']?.toString() ?? 'Đã lưu');
            widget.onChanged();
          } else {
            setSheet(() {
              saving = false;
              error = res['message']?.toString() ?? 'Lưu thất bại';
            });
          }
        }

        Widget input(_Field f) {
          final c = ctrls[f.key]!;
          switch (f.kind) {
            case _FieldKind.date:
              return InkWell(
                onTap: () async {
                  final cur = DateTime.tryParse(c.text);
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: cur ?? (f.key == 'dateOfBirth' ? DateTime(now.year - 25) : now),
                    firstDate: DateTime(1940),
                    lastDate: DateTime(now.year + 40),
                    helpText: f.label,
                  );
                  if (picked != null) setSheet(() => c.text = _isoDate(picked));
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: f.label, suffixIcon: const Icon(Icons.calendar_month_outlined)),
                  child: Text(c.text.isEmpty ? 'Chọn ngày' : _fmtDate(c.text),
                      style: TextStyle(color: c.text.isEmpty ? DrivoColors.textMuted : DrivoColors.textPrimary)),
                ),
              );
            case _FieldKind.gender:
              return DropdownButtonFormField<String>(
                initialValue: _genderLabels.containsKey(c.text) ? c.text : null,
                decoration: InputDecoration(labelText: f.label),
                dropdownColor: DrivoColors.bgCard,
                style: const TextStyle(color: DrivoColors.textPrimary),
                items: _genderLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => c.text = v ?? '',
              );
            default:
              return TextField(
                controller: c,
                style: const TextStyle(color: DrivoColors.textPrimary),
                textCapitalization: f.upper ? TextCapitalization.characters : TextCapitalization.sentences,
                keyboardType: switch (f.kind) {
                  _FieldKind.phone => TextInputType.phone,
                  _FieldKind.number || _FieldKind.digits => TextInputType.number,
                  _ => TextInputType.text,
                },
                decoration: InputDecoration(labelText: f.label, hintText: f.hint),
              );
          }
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: DrivoColors.border, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 14),
              Text(title, style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              if (note != null) ...[
                const SizedBox(height: 6),
                Text(note, style: GoogleFonts.inter(color: DrivoColors.warning, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              for (final f in fields) ...[input(f), const SizedBox(height: 12)],
              if (error != null) ...[
                Text(error!, style: GoogleFonts.inter(color: DrivoColors.danger, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving ? null : () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: DrivoColors.textSecondary, side: const BorderSide(color: DrivoColors.border)),
                    child: const Text('Hủy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Lưu'),
                  ),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
    for (final c in ctrls.values) {
      c.dispose();
    }
  }

  // ── Ảnh giấy tờ ─────────────────────────────────────────────
  Future<void> _pickAndUpload(String type) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: DrivoColors.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: DrivoColors.primary),
            title: const Text('Chụp ảnh', style: TextStyle(color: DrivoColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: DrivoColors.primary),
            title: const Text('Chọn từ thư viện', style: TextStyle(color: DrivoColors.textPrimary)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    } catch (_) {
      _snack('Không mở được máy ảnh/thư viện ảnh.', error: true);
      return;
    }
    if (file == null) return;

    setState(() => _uploadingType = type);
    try {
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final mime = file.mimeType ??
          (name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      final res = await ApiService.uploadDriverDocument(type, bytes, file.name, mime);
      if (res['success'] == true) {
        _snack(res['message']?.toString() ?? 'Đã tải ảnh lên');
        widget.onChanged();
      } else {
        _snack(res['message']?.toString() ?? 'Tải ảnh thất bại', error: true);
      }
    } catch (_) {
      _snack('Không tải được ảnh, kiểm tra kết nối mạng.', error: true);
    }
    if (mounted) setState(() => _uploadingType = null);
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    if (p == null) return const Center(child: CircularProgressIndicator(color: DrivoColors.primary));
    final r = p.raw;
    final missing = _missing(p);
    final portrait = p.doc('PROFILE_PHOTO');

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Ảnh + tên
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [DrivoColors.primary, DrivoColors.accent]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: DrivoColors.primary.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            clipBehavior: Clip.antiAlias,
            child: portrait != null
                ? Image.network(portrait.fullUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => _initial(p))
                : _initial(p),
          ),
          const SizedBox(height: 12),
          Text(p.fullName, style: GoogleFonts.inter(color: DrivoColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            DrivoBadge(p.verificationStatus),
            const SizedBox(width: 8),
            DrivoBadge(p.driverStatus),
          ]),
          if (p.isFirstLogin) ...[
            const SizedBox(height: 12),
            _banner(Icons.lock_outline, 'Vui lòng đổi mật khẩu mặc định', DrivoColors.warning),
          ],
          if (p.profileReviewPending) ...[
            const SizedBox(height: 12),
            _banner(Icons.hourglass_top_rounded, 'Thông tin/giấy tờ vừa cập nhật đang chờ DRIVO duyệt lại', DrivoColors.warning),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            _banner(Icons.info_outline, 'Hồ sơ còn thiếu: ${missing.join(', ')}', DrivoColors.primary),
          ],
          const SizedBox(height: 20),

          _section(
            'THÔNG TIN CÁ NHÂN',
            onEdit: () => _editSection('Thông tin cá nhân', const [
              _Field('fullName', 'Họ và tên'),
              _Field('email', 'Email', hint: 'vd: ten@gmail.com'),
              _Field('dateOfBirth', 'Ngày sinh', kind: _FieldKind.date),
              _Field('gender', 'Giới tính', kind: _FieldKind.gender),
              _Field('address', 'Địa chỉ thường trú'),
              _Field('idCardNumber', 'Số CCCD', kind: _FieldKind.digits, hint: '12 chữ số'),
            ], note: 'Đổi ngày sinh hoặc số CCCD sẽ được DRIVO duyệt lại.'),
            rows: [
              _row(Icons.phone_outlined, 'Số điện thoại (tên đăng nhập)', p.phone),
              _row(Icons.email_outlined, 'Email', _show(r['email'])),
              _row(Icons.cake_outlined, 'Ngày sinh', _fmtDate(r['dateOfBirth'])),
              _row(Icons.wc_outlined, 'Giới tính', _genderLabels[r['gender']] ?? '—'),
              _row(Icons.home_outlined, 'Địa chỉ', _show(r['address'])),
              _row(Icons.credit_card_outlined, 'Số CCCD', _show(r['idCardNumber'])),
            ],
          ),

          _section(
            'GIẤY PHÉP LÁI XE',
            onEdit: () => _editSection('Giấy phép lái xe', const [
              _Field('licenseNumber', 'Số GPLX', upper: true),
              _Field('licenseClass', 'Hạng bằng', hint: 'vd: B2, C, D', upper: true),
              _Field('licenseExpiryDate', 'Ngày hết hạn', kind: _FieldKind.date),
              _Field('drivingExperienceYears', 'Số năm kinh nghiệm lái xe', kind: _FieldKind.number),
            ], note: 'Đổi thông tin GPLX sẽ được DRIVO duyệt lại.'),
            rows: [
              _row(Icons.badge_outlined, 'Số GPLX', _show(r['licenseNumber'])),
              _row(Icons.drive_eta_outlined, 'Hạng bằng', _show(r['licenseClass'])),
              _expiryRow(r['licenseExpiryDate']),
              _row(Icons.timeline_outlined, 'Kinh nghiệm',
                  r['drivingExperienceYears'] == null ? '—' : '${r['drivingExperienceYears']} năm'),
            ],
          ),

          _docsSection(p),

          _section(
            'LIÊN HỆ KHẨN CẤP',
            onEdit: () => _editSection('Liên hệ khẩn cấp', const [
              _Field('emergencyContactName', 'Họ tên người thân'),
              _Field('emergencyContactRelation', 'Quan hệ', hint: 'vd: Vợ, Bố, Anh trai'),
              _Field('emergencyContactPhone', 'Số điện thoại', kind: _FieldKind.phone),
            ]),
            rows: [
              _row(Icons.person_outline, 'Người liên hệ',
                  r['emergencyContactName'] == null
                      ? '—'
                      : '${r['emergencyContactName']}${r['emergencyContactRelation'] != null ? ' (${r['emergencyContactRelation']})' : ''}'),
              _row(Icons.phone_in_talk_outlined, 'Số điện thoại', _show(r['emergencyContactPhone'])),
            ],
          ),

          _section(
            'TÀI KHOẢN NHẬN TIỀN',
            onEdit: () => _editSection('Tài khoản nhận tiền', const [
              _Field('bankName', 'Ngân hàng', hint: 'vd: Vietcombank'),
              _Field('bankAccountNumber', 'Số tài khoản', kind: _FieldKind.digits),
              _Field('bankAccountHolder', 'Chủ tài khoản', hint: 'Viết hoa không dấu', upper: true),
            ], note: 'Đổi tài khoản nhận tiền sẽ được DRIVO duyệt lại.'),
            rows: [
              _row(Icons.account_balance_outlined, 'Ngân hàng', _show(r['bankName'])),
              _row(Icons.numbers_outlined, 'Số tài khoản', _mask(r['bankAccountNumber'])),
              _row(Icons.person_pin_outlined, 'Chủ tài khoản', _show(r['bankAccountHolder'])),
            ],
          ),

          const SizedBox(height: 4),
          const Align(alignment: Alignment.centerLeft, child: SectionHeader('TÀI KHOẢN')),
          DrivoCard(
            child: Column(children: [
              _action(Icons.lock_outline, 'Đổi mật khẩu', DrivoColors.primary, widget.onChangePassword),
              const Divider(color: DrivoColors.border, height: 1),
              _action(Icons.logout_rounded, 'Đăng xuất', DrivoColors.danger, widget.onLogout),
            ]),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _initial(DriverProfile p) => Center(
        child: Text(p.fullName.trim().isEmpty ? '?' : p.fullName.trim().split(' ').last[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32)),
      );

  Widget _banner(IconData icon, String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 12.5))),
        ]),
      );

  Widget _section(String title, {required VoidCallback onEdit, required List<Widget> rows}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: SectionHeader(title)),
            TextButton.icon(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                foregroundColor: DrivoColors.primary,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('Sửa', style: TextStyle(fontSize: 13)),
            ),
          ]),
          DrivoCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Column(children: rows)),
        ]),
      );

  Widget _row(IconData icon, String label, String value, {Color? valueColor, String? note}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, color: DrivoColors.textMuted, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 11)),
              Text(value, style: GoogleFonts.inter(color: valueColor ?? DrivoColors.textPrimary, fontWeight: FontWeight.w500)),
              if (note != null) Text(note, style: GoogleFonts.inter(color: valueColor ?? DrivoColors.textMuted, fontSize: 11)),
            ]),
          ),
        ]),
      );

  Widget _expiryRow(dynamic iso) {
    final d = iso == null ? null : DateTime.tryParse(iso.toString());
    if (d == null) return _row(Icons.event_outlined, 'Ngày hết hạn', '—');
    final days = d.difference(DateTime.now()).inDays;
    if (days < 0) {
      return _row(Icons.event_busy_outlined, 'Ngày hết hạn', _fmtDate(iso), valueColor: DrivoColors.danger,
          note: 'GPLX đã hết hạn, vui lòng cập nhật');
    }
    if (days <= 30) {
      return _row(Icons.event_outlined, 'Ngày hết hạn', _fmtDate(iso), valueColor: DrivoColors.warning,
          note: 'Còn $days ngày');
    }
    return _row(Icons.event_outlined, 'Ngày hết hạn', _fmtDate(iso));
  }

  Widget _docsSection(DriverProfile p) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('ẢNH GIẤY TỜ'),
          DrivoCard(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text('Chụp rõ nét, đủ 4 góc, không lóa. Ảnh mới sẽ được DRIVO duyệt.',
                  style: GoogleFonts.inter(color: DrivoColors.textMuted, fontSize: 12)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.25,
                children: _docTypes.entries.map((e) => _docTile(e.key, e.value, p.doc(e.key))).toList(),
              ),
            ]),
          ),
        ]),
      );

  Widget _docTile(String type, String label, DriverDoc? doc) {
    final uploading = _uploadingType == type;
    final (statusText, statusColor) = switch (doc?.verificationStatus) {
      'Approved' => ('Đã duyệt', DrivoColors.success),
      'Rejected' => ('Bị từ chối', DrivoColors.danger),
      'Pending' => ('Chờ duyệt', DrivoColors.warning),
      _ => ('Chưa có ảnh', DrivoColors.textMuted),
    };
    return InkWell(
      onTap: uploading || _uploadingType != null ? null : () => _pickAndUpload(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: doc == null ? 0.2 : 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (doc != null)
            Image.network(doc.fullUrl, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: DrivoColors.textMuted))
          else
            const Center(child: Icon(Icons.add_a_photo_outlined, color: DrivoColors.textMuted, size: 28)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              color: Colors.black.withValues(alpha: 0.65),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                Text(
                  doc?.verificationStatus == 'Rejected' && doc?.rejectionReason != null
                      ? '$statusText: ${doc!.rejectionReason}'
                      : statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
          if (uploading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            ),
        ]),
      ),
    );
  }

  Widget _action(IconData icon, String label, Color color, VoidCallback onTap) => InkWell(
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
