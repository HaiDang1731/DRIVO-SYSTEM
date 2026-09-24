import { useState, useEffect } from 'react';
import { api } from '../services/api';
import { Avatar } from '../components/Avatar';
import { Badge } from '../components/Badge';

export function AdminAccountsPage() {
  const [admins, setAdmins] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({ fullName: '', phone: '', email: '', password: '' });

  const load = async () => {
    setLoading(true);
    const res = await api.getAdmins();
    if (res.success) setAdmins(res.data || []);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    const res = await api.createAdmin(form);
    if (res.success) {
      alert('Tạo tài khoản Quản trị viên thành công!');
      setShowCreate(false);
      setForm({ fullName: '', phone: '', email: '', password: '' });
      load();
    } else {
      alert(res.message || 'Lỗi tạo admin');
    }
  };

  const handleToggle = async (id: number) => {
    await api.toggleAdminStatus(id);
    load();
  };

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản lý Tài khoản Quản trị (Admin)</h2>
          <p>Phân quyền nội bộ, cấp tài khoản và quản lý trạng thái tài khoản ban điều hành</p>
        </div>
        <div className="topbar-actions">
          <button className="btn btn-primary" onClick={() => setShowCreate(true)}>+ Thêm Quản Trị Viên</button>
        </div>
      </div>

      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>⏳ Đang tải danh sách Admin...</div>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Quản trị viên</th>
                  <th>Số điện thoại</th>
                  <th>Email</th>
                  <th>Trạng thái</th>
                  <th>Lần đăng nhập cuối</th>
                  <th>Ngày tạo</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {admins.map((a) => (
                  <tr key={a.id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <Avatar name={a.fullName} />
                        <div><strong>{a.fullName}</strong></div>
                      </div>
                    </td>
                    <td>{a.phone}</td>
                    <td>{a.email || '-'}</td>
                    <td><Badge type={a.status === 'Active' ? 'success' : 'danger'}>{a.status}</Badge></td>
                    <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{a.lastLoginAt ? new Date(a.lastLoginAt).toLocaleString('vi-VN') : 'Chưa'}</td>
                    <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{new Date(a.createdAt).toLocaleDateString('vi-VN')}</td>
                    <td>
                      <button className={`btn btn-sm ${a.status === 'Active' ? 'btn-danger' : 'btn-success'}`} onClick={() => handleToggle(a.id)}>
                        {a.status === 'Active' ? 'Khóa' : 'Mở'}
                      </button>
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
          <div className="modal" style={{ width: 450 }}>
            <div className="modal-header">
              <h3 className="modal-title">🛡️ Thêm Tài Khoản Admin</h3>
              <button className="btn-close" onClick={() => setShowCreate(false)}>✕</button>
            </div>
            <form onSubmit={handleCreate}>
              <div className="modal-body">
                <div className="input-group">
                  <label>Họ và tên</label>
                  <input type="text" className="input" required value={form.fullName} onChange={(e) => setForm({ ...form, fullName: e.target.value })} />
                </div>
                <div className="input-group">
                  <label>Số điện thoại (Tên đăng nhập)</label>
                  <input type="text" className="input" required value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
                </div>
                <div className="input-group">
                  <label>Email</label>
                  <input type="email" className="input" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
                </div>
                <div className="input-group">
                  <label>Mật khẩu khởi tạo</label>
                  <input type="password" className="input" required value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-ghost" onClick={() => setShowCreate(false)}>Hủy</button>
                <button type="submit" className="btn btn-primary">Tạo Admin</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
