import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/api_service.dart';

class CustomerVehiclesScreen extends StatefulWidget {
  const CustomerVehiclesScreen({super.key});

  @override
  State<CustomerVehiclesScreen> createState() => _CustomerVehiclesScreenState();
}

class _CustomerVehiclesScreenState extends State<CustomerVehiclesScreen> {
  List<CustomerVehicle> _vehicles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getCustomerVehicles();
      if (res['success'] == true && res['data'] != null) {
        final list = (res['data'] as List).map((x) => CustomerVehicle.fromJson(x)).toList();
        if (mounted) setState(() { _vehicles = list; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteVehicle(int id) async {
    final res = await ApiService.deleteCustomerVehicle(id);
    if (res['success'] == true) {
      _loadVehicles();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa xe'), backgroundColor: Color(0xFF10B981)));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Lỗi'), backgroundColor: const Color(0xFFEF4444)));
    }
  }

  void _showAddVehicleDialog() {
    final brandCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    String vehicleType = 'Car';
    String transmission = 'Automatic';
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF111827),
          title: Text('Thêm xe mới', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: brandCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Hãng xe (VD: Toyota)', labelStyle: TextStyle(color: Colors.white54))),
                const SizedBox(height: 8),
                TextField(controller: modelCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Dòng xe (VD: Vios)', labelStyle: TextStyle(color: Colors.white54))),
                const SizedBox(height: 8),
                TextField(controller: plateCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Biển số (Bắt buộc)', labelStyle: TextStyle(color: Colors.white54))),
                const SizedBox(height: 8),
                TextField(controller: colorCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Màu xe', labelStyle: TextStyle(color: Colors.white54))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: transmission,
                  dropdownColor: const Color(0xFF1F2937),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Hộp số', labelStyle: TextStyle(color: Colors.white54)),
                  items: const [
                    DropdownMenuItem(value: 'Automatic', child: Text('Tự động')),
                    DropdownMenuItem(value: 'Manual', child: Text('Số sàn')),
                  ],
                  onChanged: (v) => setDialogState(() => transmission = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text('Hủy', style: GoogleFonts.inter(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                if (plateCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập biển số'), backgroundColor: Color(0xFFEF4444)));
                  return;
                }
                setDialogState(() => saving = true);
                final res = await ApiService.addCustomerVehicle({
                  'brand': brandCtrl.text,
                  'model': modelCtrl.text,
                  'licensePlate': plateCtrl.text,
                  'color': colorCtrl.text,
                  'vehicleType': vehicleType,
                  'transmission': transmission,
                });
                setDialogState(() => saving = false);
                if (res['success'] == true) {
                  Navigator.pop(ctx);
                  _loadVehicles();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thêm xe thành công'), backgroundColor: Color(0xFF10B981)));
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Lỗi'), backgroundColor: const Color(0xFFEF4444)));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Thêm', style: GoogleFonts.inter(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1228),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Danh sách xe của tôi', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Color(0xFF6C63FF)),
            onPressed: _showAddVehicleDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : _vehicles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.directions_car_filled_rounded, color: Color(0xFF6C63FF), size: 36),
                      ),
                      const SizedBox(height: 16),
                      Text('Bạn chưa thêm xe nào', style: GoogleFonts.inter(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Thêm xe để đặt tài xế dễ dàng hơn', style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: _showAddVehicleDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text('Thêm xe ngay', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _vehicles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final v = _vehicles[i];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.directions_car_filled_rounded, color: Color(0xFF6C63FF), size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.displayInfo, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                      child: Text(v.transmission == 'Automatic' ? 'Tự động' : 'Số sàn', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF10B981))),
                                    ),
                                    if (v.color != null && v.color!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text('Màu: ${v.color}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF111827),
                                  title: Text('Xóa xe?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                                  content: Text('Bạn có chắc chắn muốn xóa xe ${v.displayInfo} không?', style: GoogleFonts.inter(color: Colors.white70)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text('Hủy', style: GoogleFonts.inter(color: Colors.white54)),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _deleteVehicle(v.id);
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                      child: Text('Xóa', style: GoogleFonts.inter(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
