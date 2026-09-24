import { useState } from 'react';
import { api } from '../services/api';

export function LoginPage({ onLogin }: { onLogin: (user: any) => void }) {
  const [email, setEmail] = useState('admin@drivo.local');
  const [password, setPassword] = useState('Admin@123');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true); setError('');
    const res = await api.login(email, password);
    setLoading(false);
    if (res.success && res.data) {
      if (!res.data.user.roles?.some((r: string) => r.toUpperCase() === 'ADMIN')) {
        setError('Tài khoản không có quyền truy cập Admin');
        return;
      }
      api.setToken(res.data.accessToken);
      localStorage.setItem('drivo_user', JSON.stringify(res.data.user));
      onLogin(res.data.user);
    } else {
      setError(res.message || 'Đăng nhập thất bại');
    }
  };

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-logo">
          <h1>🚗 DRIVO ADMIN</h1>
          <p>Đăng nhập hệ thống quản trị</p>
        </div>

        {error && <div className="error-msg">⚠️ {error}</div>}

        <form onSubmit={handleLogin}>
          <div className="form-group">
            <label className="form-label">Email quản trị</label>
            <input className="form-input" type="email" required value={email} onChange={e => setEmail(e.target.value)} placeholder="admin@drivo.local" />
          </div>
          <div className="form-group">
            <label className="form-label">Mật khẩu</label>
            <input className="form-input" type="password" required value={password} onChange={e => setPassword(e.target.value)} placeholder="••••••••" />
          </div>
          <button type="submit" className="btn btn-primary" style={{ width: '100%', marginTop: 10 }} disabled={loading}>
            {loading ? 'Đang xử lý...' : 'Đăng nhập'}
          </button>
        </form>
      </div>
    </div>
  );
}
