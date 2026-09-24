import { useState, useEffect } from 'react';
import { api } from '../services/api';
import { Badge } from '../components/Badge';

export function VouchersPage() {
  const [vouchers, setVouchers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({
    code: '',
    title: '',
    description: '',
    discountType: 'PERCENT',
    discountValue: 20,
    maxDiscountAmount: 50000,
    minOrderAmount: 0,
    usageLimit: 100
  });

  const load = async () => {
    setLoading(true);
    const res = await api.getVouchers();
    if (res.success) setVouchers(res.data || []);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    const res = await api.createVoucher(form);
    if (res.success) {
      alert('Tạo mã khuyến mãi thành công!');
      setShowCreate(false);
      load();
    } else {
      alert(res.message || 'Lỗi tạo voucher');
    }
  };

  const handleToggle = async (id: number) => {
    await api.toggleVoucher(id);
    load();
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm('Xóa mã giảm giá này?')) return;
    await api.deleteVoucher(id);
    load();
  };

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val || 0);

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản lý Mã Giảm Giá & Khuyến Mãi</h2>
          <p>Tạo chiến dịch chiết khấu linh hoạt, giới hạn lượt dùng và kích hoạt mã ưu đãi cho khách hàng</p>
        </div>
        <div className="topbar-actions">
          <button className="btn btn-primary" onClick={() => setShowCreate(true)}>+ Tạo Mã Mới</button>
        </div>
      </div>

      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tải mã giảm giá...</div>
        ) : vouchers.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Chưa có mã khuyến mãi nào.</div>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Mã code</th>
                  <th>Chương trình</th>
                  <th>Mức giảm</th>
                  <th>Giảm tối đa</th>
                  <th>Đơn tối thiểu</th>
                  <th>Lượt dùng / Giới hạn</th>
                  <th>Trạng thái</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {vouchers.map((v) => (
                  <tr key={v.id}>
                    <td><strong style={{ color: 'var(--accent)', letterSpacing: 1 }}>{v.code}</strong></td>
                    <td>
                      <div><strong>{v.title}</strong></div>
                      <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{v.description}</div>
                    </td>
                    <td>{v.discountType === 'PERCENT' ? `${v.discountValue}%` : formatCurrency(v.discountValue)}</td>
                    <td>{v.maxDiscountAmount ? formatCurrency(v.maxDiscountAmount) : 'Không giới hạn'}</td>
                    <td>{formatCurrency(v.minOrderAmount)}</td>
                    <td>{v.usedCount} / {v.usageLimit}</td>
                    <td><Badge type={v.isActive ? 'success' : 'danger'}>{v.isActive ? 'Hoạt động' : 'Tạm dừng'}</Badge></td>
                    <td>
                      <div style={{ display: 'flex', gap: 6 }}>
                        <button className={`btn btn-sm ${v.isActive ? 'btn-danger' : 'btn-success'}`} onClick={() => handleToggle(v.id)}>
                          {v.isActive ? 'Tắt' : 'Bật'}
                        </button>
                        <button className="btn btn-sm btn-ghost" onClick={() => handleDelete(v.id)}>Xóa</button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showCreate && (
        <div className="modal-backdrop">
          <div className="modal" style={{ width: 500 }}>
            <div className="modal-header">
              <h3 className="modal-title">Thêm Mã Giảm Giá Mới</h3>
              <button className="btn-close" onClick={() => setShowCreate(false)}>✕</button>
            </div>
            <form onSubmit={handleCreate}>
              <div className="modal-body">
                <div className="input-group">
                  <label>Mã Voucher (viết liền không dấu)</label>
                  <input type="text" className="input" required value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} placeholder="VD: DRIVO50K" />
                </div>
                <div className="input-group">
                  <label>Tên chương trình</label>
                  <input type="text" className="input" required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} placeholder="VD: Giảm 50K ngày vàng" />
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                  <div className="input-group">
                    <label>Loại giảm giá</label>
                    <select className="input" value={form.discountType} onChange={(e) => setForm({ ...form, discountType: e.target.value })}>
                      <option value="PERCENT">Phần trăm (%)</option>
                      <option value="FIXED">Số tiền cố định (VNĐ)</option>
                    </select>
                  </div>
                  <div className="input-group">
                    <label>Giá trị giảm</label>
                    <input type="number" className="input" required value={form.discountValue} onChange={(e) => setForm({ ...form, discountValue: Number(e.target.value) })} />
                  </div>
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                  <div className="input-group">
                    <label>Giảm tối đa (VNĐ)</label>
                    <input type="number" className="input" value={form.maxDiscountAmount} onChange={(e) => setForm({ ...form, maxDiscountAmount: Number(e.target.value) })} />
                  </div>
                  <div className="input-group">
                    <label>Số lượt phát hành</label>
                    <input type="number" className="input" required value={form.usageLimit} onChange={(e) => setForm({ ...form, usageLimit: Number(e.target.value) })} />
                  </div>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-ghost" onClick={() => setShowCreate(false)}>Huy</button>
                <button type="submit" className="btn btn-primary">Tạo Voucher</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
