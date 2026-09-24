import { useState } from 'react';
import { api } from '../services/api';

export function CreateDriverModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [form, setForm] = useState({ fullName: '', phone: '', email: '', licenseNumber: '', licenseClass: 'B2' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError('');
    const res = await api.createDriver(form);
    setLoading(false);
    if (res.success) { onCreated(); onClose(); }
    else setError(res.message ?? 'Lỗi tạo tài xế');
  };

  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div className="modal-header">
          <div className="modal-title">🚙 Thêm Tài Xế Mới</div>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>
        {error && <div className="error-msg">⚠️ {error}</div>}
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label">Họ và tên *</label>
            <input className="form-input" required value={form.fullName}
              onChange={e => setForm(f => ({ ...f, fullName: e.target.value }))} placeholder="Nguyen Van A" />
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <div className="form-group">
              <label className="form-label">Số điện thoại *</label>
              <input className="form-input" required value={form.phone}
                onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} placeholder="09xxxxxxxx" />
            </div>
            <div className="form-group">
              <label className="form-label">Email</label>
              <input className="form-input" type="email" value={form.email}
                onChange={e => setForm(f => ({ ...f, email: e.target.value }))} placeholder="driver@email.com" />
            </div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <div className="form-group">
              <label className="form-label">Số GPLX *</label>
              <input className="form-input" required value={form.licenseNumber}
                onChange={e => setForm(f => ({ ...f, licenseNumber: e.target.value }))} placeholder="GPLX-B2-001" />
            </div>
            <div className="form-group">
              <label className="form-label">Hạng bằng lái</label>
              <select className="form-select" value={form.licenseClass}
                onChange={e => setForm(f => ({ ...f, licenseClass: e.target.value }))}>
                <option value="A1">A1 - Xe máy</option>
                <option value="A2">A2 - Mô tô</option>
                <option value="B1">B1 - Ô tô (không hành nghề)</option>
                <option value="B2">B2 - Ô tô (hành nghề)</option>
                <option value="C">C - Xe tải</option>
              </select>
            </div>
          </div>
          <div style={{ background: 'rgba(0,212,170,0.08)', border: '1px solid rgba(0,212,170,0.2)', borderRadius: 8, padding: '10px 14px', fontSize: 12, color: 'var(--accent)', marginBottom: 20 }}>
            ℹ️ Mật khẩu mặc định = Số điện thoại. Tài xế cần đổi mật khẩu khi đăng nhập lần đầu.
          </div>
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button type="button" className="btn btn-ghost" onClick={onClose}>Hủy</button>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? '⏳ Đang tạo...' : '➕ Tạo tài khoản'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
