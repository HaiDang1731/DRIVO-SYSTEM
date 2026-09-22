import { useState, useEffect, useCallback } from 'react';
import { api } from './services/api';
import './index.css';

// ── Types ────────────────────────────────────────────────────
interface User { id: number; fullName: string; phone: string; email: string; roles: string[]; }
interface Driver {
  driverId: number; userId: number; fullName: string; phone: string; email: string;
  licenseNumber: string; licenseClass: string; verificationStatus: string;
  driverStatus: string;
  accountStatus: string; ratingAverage: number; totalTrips: number; createdAt: string;
  documents?: { id: number; documentType: string; fileUrl: string; verificationStatus: string; }[];
}

// ── Toast ────────────────────────────────────────────────────
function Toast({ msg, type, onClose }: { msg: string; type: 'success' | 'error'; onClose: () => void }) {
  useEffect(() => { const t = setTimeout(onClose, 3000); return () => clearTimeout(t); }, [onClose]);
  return (
    <div className={`toast ${type}`}>
      {type === 'success' ? '✓' : '✕'} {msg}
    </div>
  );
}

// ── Badge ────────────────────────────────────────────────────
function Badge({ value }: { value: string }) {
  const map: Record<string, string> = {
    Pending: 'pending', Approved: 'approved', Rejected: 'rejected',
    Online: 'active', Offline: 'offline', Busy: 'driver',
    Active: 'approved', Locked: 'locked', CUSTOMER: 'customer', DRIVER: 'driver',
  };
  return <span className={`badge ${map[value] ?? 'pending'}`}>{value}</span>;
}

// ── Avatar ───────────────────────────────────────────────────
function Avatar({ name }: { name: string }) {
  return <div className="avatar">{name?.split(' ').slice(-1)[0]?.[0] ?? '?'}</div>;
}

// ── Sidebar ──────────────────────────────────────────────────
const PAGES = [
  { key: 'dashboard', icon: '⬡', label: 'Dashboard' },
  { key: 'drivers', icon: '🚗', label: 'Tài xế' },
  { key: 'customers', icon: '👥', label: 'Khách hàng' },
  { key: 'bookings', icon: '📋', label: 'Chuyến đi' },
  { key: 'payments', icon: '💳', label: 'Thanh toán' },
];

function Sidebar({ page, setPage, user, onLogout }:
  { page: string; setPage: (p: string) => void; user: User | null; onLogout: () => void }) {
  return (
    <div className="sidebar">
      <div className="sidebar-logo">
        <h1>🚗 DRIVO</h1>
        <span>Admin Dashboard</span>
      </div>
      <nav className="sidebar-nav">
        <div className="nav-section-title">Menu</div>
        {PAGES.map(p => (
          <div key={p.key} className={`nav-item ${page === p.key ? 'active' : ''}`}
            onClick={() => setPage(p.key)}>
            <span className="icon">{p.icon}</span>
            {p.label}
          </div>
        ))}
      </nav>
      <div className="sidebar-footer">
        <div className="nav-item" style={{ marginBottom: 8 }}>
          <Avatar name={user?.fullName ?? 'Admin'} />
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-primary)' }}>{user?.fullName}</div>
            <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>Administrator</div>
          </div>
        </div>
        <button className="btn btn-ghost" style={{ width: '100%', justifyContent: 'center' }}
          onClick={onLogout}>🚪 Đăng xuất</button>
      </div>
    </div>
  );
}

// ── Login Page ───────────────────────────────────────────────
function LoginPage({ onLogin }: { onLogin: (user: User) => void }) {
  const [email, setEmail] = useState('admin@drivo.local');
  const [password, setPassword] = useState('Admin@123');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError('');
    const res = await api.login(email, password);
    setLoading(false);
    if (res.success) {
      api.setToken(res.data.accessToken);
      localStorage.setItem('drivo_user', JSON.stringify(res.data.user));
      onLogin(res.data.user);
    } else {
      setError(res.message ?? 'Đăng nhập thất bại');
    }
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-logo">
          <h1>🚗 DRIVO</h1>
          <p>Quản trị hệ thống đặt tài xế</p>
        </div>
        {error && <div className="error-msg">⚠️ {error}</div>}
        <form onSubmit={handleLogin}>
          <div className="form-group">
            <label className="form-label">Email</label>
            <input className="form-input" value={email} onChange={e => setEmail(e.target.value)}
              placeholder="Nhập địa chỉ email..." required />
          </div>
          <div className="form-group">
            <label className="form-label">Mật khẩu</label>
            <input className="form-input" type="password" value={password}
              onChange={e => setPassword(e.target.value)} placeholder="Nhập mật khẩu..." required />
          </div>
          <button className="btn btn-primary" style={{ width: '100%', justifyContent: 'center', padding: '13px', marginTop: 4 }}
            type="submit" disabled={loading}>
            {loading ? '⏳ Đang đăng nhập...' : '🔐 Đăng nhập'}
          </button>
        </form>
        <div style={{ textAlign: 'center', marginTop: 20, fontSize: 12, color: 'var(--text-muted)' }}>
          DRIVO Admin v1.0 — Chỉ dành cho Quản trị viên
        </div>
      </div>
    </div>
  );
}

// ── Dashboard Page ───────────────────────────────────────────
function DashboardPage() {
  const stats = [
    { label: 'Tổng tài xế', value: '—', icon: '🚗', color: '#6C63FF', change: '', dir: 'up' },
    { label: 'Chờ duyệt', value: '—', icon: '⏳', color: '#FFA502', change: '', dir: 'up' },
    { label: 'Khách hàng', value: '—', icon: '👥', color: '#00D4AA', change: '', dir: 'up' },
    { label: 'Chuyến hôm nay', value: '0', icon: '📋', color: '#FF4757', change: '', dir: 'up' },
  ];
  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Dashboard</h2>
          <p>Tổng quan hoạt động hệ thống DRIVO</p>
        </div>
        <div className="topbar-actions">
          <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>
            📅 {new Date().toLocaleDateString('vi-VN', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
          </div>
        </div>
      </div>

      <div className="stat-grid">
        {stats.map((s, i) => (
          <div className="stat-card" key={i} style={{ '--gradient': `linear-gradient(90deg, ${s.color}, ${s.color}88)` } as React.CSSProperties}>
            <div className="stat-icon" style={{ background: `${s.color}20` }}>{s.icon}</div>
            <div className="stat-value">{s.value}</div>
            <div className="stat-label">{s.label}</div>
          </div>
        ))}
      </div>

      <div className="card" style={{ textAlign: 'center', padding: '60px' }}>
        <div style={{ fontSize: 48, marginBottom: 16 }}>🚀</div>
        <h3 style={{ color: 'var(--text-primary)', marginBottom: 8 }}>Hệ thống DRIVO đang hoạt động</h3>
        <p style={{ color: 'var(--text-muted)', fontSize: 14 }}>
          API kết nối thành công • Quản lý tài xế và chuyến đi tại menu bên trái
        </p>
      </div>
    </div>
  );
}

// ── Create Driver Modal ──────────────────────────────────────
function CreateDriverModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
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
          <div className="modal-title">🚗 Thêm Tài Xế Mới</div>
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
            💡 Mật khẩu mặc định = Số điện thoại. Tài xế cần đổi mật khẩu khi đăng nhập lần đầu.
          </div>
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button type="button" className="btn btn-ghost" onClick={onClose}>Hủy</button>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? '⏳ Đang tạo...' : '✓ Tạo tài khoản'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Verify Driver Modal ──────────────────────────────────────
function VerifyModal({ driver, onClose, onDone }: { driver: Driver; onClose: () => void; onDone: () => void }) {
  const [reason, setReason] = useState('');
  const [loading, setLoading] = useState(false);

  const verify = async (status: string) => {
    setLoading(true);
    await api.verifyDriver(driver.driverId, status, reason);
    setLoading(false);
    onDone(); onClose();
  };

  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div className="modal-header">
          <div className="modal-title">📋 Duyệt Hồ Sơ Tài Xế</div>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>
        <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: 10, padding: 16, marginBottom: 20 }}>
          <div className="user-cell" style={{ marginBottom: 12 }}>
            <Avatar name={driver.fullName} />
            <div>
              <div className="name">{driver.fullName}</div>
              <div className="phone">{driver.phone} • {driver.licenseNumber}</div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <Badge value={driver.verificationStatus} />
            <Badge value={driver.driverStatus} />
          </div>
          {driver.documents && driver.documents.length > 0 && (
            <div style={{ marginTop: 12 }}>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 6 }}>GIẤY TỜ</div>
              {driver.documents.map(d => (
                <div key={d.id} style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 3 }}>
                  📎 {d.documentType} — <Badge value={d.verificationStatus} />
                </div>
              ))}
            </div>
          )}
        </div>
        <div className="form-group">
          <label className="form-label">Lý do từ chối (bắt buộc khi từ chối)</label>
          <textarea className="form-input" rows={3} value={reason} onChange={e => setReason(e.target.value)}
            placeholder="Nhập lý do từ chối hồ sơ..." style={{ resize: 'vertical' }} />
        </div>
        <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button className="btn btn-ghost" onClick={onClose}>Hủy</button>
          <button className="btn btn-danger" disabled={loading} onClick={() => verify('Rejected')}>
            ✕ Từ chối
          </button>
          <button className="btn btn-success" disabled={loading} onClick={() => verify('Approved')}>
            ✓ Duyệt
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Drivers Page ─────────────────────────────────────────────
function DriversPage() {
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [filter, setFilter] = useState('');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(false);
  const [showCreate, setShowCreate] = useState(false);
  const [verifyTarget, setVerifyTarget] = useState<Driver | null>(null);
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const res = await api.getDrivers(filter || undefined, 1, 50);
    setLoading(false);
    if (res.success) setDrivers(res.data);
  }, [filter]);

  useEffect(() => { load(); }, [load]);

  const filtered = drivers.filter(d =>
    !search || d.fullName.toLowerCase().includes(search.toLowerCase()) ||
    d.phone.includes(search) || d.licenseNumber.toLowerCase().includes(search.toLowerCase())
  );

  const handleToggleLock = async (d: Driver) => {
    const newStatus = d.accountStatus === 'Locked' ? 'Active' : 'Locked';
    await api.setDriverStatus(d.driverId, newStatus);
    setToast({ msg: `Đã ${newStatus === 'Locked' ? 'khóa' : 'mở khóa'} tài khoản`, type: 'success' });
    load();
  };

  return (
    <div>
      {toast && <Toast msg={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
      {showCreate && <CreateDriverModal onClose={() => setShowCreate(false)} onCreated={() => { load(); setToast({ msg: 'Tạo tài xế thành công!', type: 'success' }); }} />}
      {verifyTarget && <VerifyModal driver={verifyTarget} onClose={() => setVerifyTarget(null)} onDone={() => { load(); setToast({ msg: 'Cập nhật hồ sơ thành công!', type: 'success' }); }} />}

      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản lý Tài xế</h2>
          <p>Tạo, duyệt và quản lý tài khoản tài xế</p>
        </div>
        <div className="topbar-actions">
          <button className="btn btn-primary" onClick={() => setShowCreate(true)}>
            + Thêm tài xế
          </button>
        </div>
      </div>

      {/* Filter & Search */}
      <div className="card" style={{ marginBottom: 20, padding: '16px 20px' }}>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>
          <div className="search-bar">
            🔍
            <input placeholder="Tìm theo tên, SĐT, GPLX..." value={search}
              onChange={e => setSearch(e.target.value)} />
          </div>
          {['', 'Pending', 'Approved', 'Rejected'].map(s => (
            <button key={s} className={`btn btn-sm ${filter === s ? 'btn-primary' : 'btn-ghost'}`}
              onClick={() => setFilter(s)}>
              {s === '' ? 'Tất cả' : s === 'Pending' ? '⏳ Chờ duyệt' : s === 'Approved' ? '✅ Đã duyệt' : '❌ Từ chối'}
            </button>
          ))}
          <div style={{ marginLeft: 'auto', fontSize: 13, color: 'var(--text-muted)' }}>
            {filtered.length} tài xế
          </div>
        </div>
      </div>

      <div className="card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>⏳ Đang tải...</div>
        ) : filtered.length === 0 ? (
          <div className="empty-state">
            <div className="empty-icon">🚗</div>
            <h3>Chưa có tài xế nào</h3>
            <p>Nhấn "+ Thêm tài xế" để đăng ký tài xế đầu tiên</p>
          </div>
        ) : (
          <div className="table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Tài xế</th>
                  <th>Số điện thoại</th>
                  <th>GPLX</th>
                  <th>Hạng bằng</th>
                  <th>Trạng thái duyệt</th>
                  <th>Hoạt động</th>
                  <th>Ngày tạo</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map(d => (
                  <tr key={d.driverId}>
                    <td>
                      <div className="user-cell">
                        <Avatar name={d.fullName} />
                        <div>
                          <div className="name">{d.fullName}</div>
                          <div className="phone">{d.email ?? '—'}</div>
                        </div>
                      </div>
                    </td>
                    <td style={{ color: 'var(--text-primary)', fontWeight: 500 }}>{d.phone}</td>
                    <td style={{ fontFamily: 'monospace', color: 'var(--accent)', fontSize: 12 }}>{d.licenseNumber}</td>
                    <td>{d.licenseClass ?? '—'}</td>
                    <td><Badge value={d.verificationStatus} /></td>
                    <td><Badge value={d.driverStatus} /></td>
                    <td>{new Date(d.createdAt).toLocaleDateString('vi-VN')}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 6 }}>
                        {d.verificationStatus === 'Pending' && (
                          <button className="btn btn-sm btn-success" onClick={() => setVerifyTarget(d)}>
                            Duyệt
                          </button>
                        )}
                        {d.verificationStatus !== 'Pending' && (
                          <button className="btn btn-sm btn-ghost" onClick={() => setVerifyTarget(d)}>
                            Chi tiết
                          </button>
                        )}
                        <button className={`btn btn-sm ${d.accountStatus === 'Locked' ? 'btn-danger' : 'btn-success'}`}
                          onClick={() => handleToggleLock(d)}>
                          {d.accountStatus === 'Locked' ? '🔒' : '🔓'}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

// ── Coming Soon Page ─────────────────────────────────────────
function ComingSoon({ title }: { title: string }) {
  return (
    <div>
      <div className="topbar">
        <div className="topbar-title"><h2>{title}</h2><p>Đang phát triển</p></div>
      </div>
      <div className="card" style={{ textAlign: 'center', padding: '80px 20px' }}>
        <div style={{ fontSize: 64, marginBottom: 20 }}>🏗️</div>
        <h2 style={{ color: 'var(--text-primary)', marginBottom: 12 }}>{title} đang được xây dựng</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: 14 }}>Tính năng này sẽ sớm ra mắt trong phiên bản tiếp theo</p>
      </div>
    </div>
  );
}

// ── App Root ─────────────────────────────────────────────────
export default function App() {
  const [user, setUser] = useState<User | null>(() => {
    const saved = localStorage.getItem('drivo_user');
    return saved ? JSON.parse(saved) : null;
  });
  const [page, setPage] = useState('dashboard');

  const handleLogout = () => {
    api.clearToken();
    setUser(null);
  };

  if (!user) return <LoginPage onLogin={setUser} />;

  const renderPage = () => {
    switch (page) {
      case 'dashboard': return <DashboardPage />;
      case 'drivers': return <DriversPage />;
      case 'customers': return <ComingSoon title="Khách hàng" />;
      case 'bookings': return <ComingSoon title="Chuyến đi" />;
      case 'payments': return <ComingSoon title="Thanh toán" />;
      default: return <DashboardPage />;
    }
  };

  return (
    <div className="layout">
      <Sidebar page={page} setPage={setPage} user={user} onLogout={handleLogout} />
      <main className="main">{renderPage()}</main>
    </div>
  );
}
