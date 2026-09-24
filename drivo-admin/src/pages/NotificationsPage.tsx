import { useState, useEffect } from 'react';
import { api } from '../services/api';


export function NotificationsPage() {
  const [list, setList] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [targetGroup, setTargetGroup] = useState('ALL');

  const load = async () => {
    setLoading(true);
    const res = await api.getNotifications();
    if (res.success) setList(res.data || []);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title || !message) return;
    const res = await api.broadcastNotification({ title, message, targetGroup });
    if (res.success) {
      alert(res.message || 'Đã gửi thông báo thành công!');
      setTitle('');
      setMessage('');
      load();
    }
  };

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản Lý Thông Báo Hệ Thống</h2>
          <p>Gửi thông báo Push đến toàn bộ tài xế hoặc khách hàng</p>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '400px 1fr', gap: 24 }}>
        <div className="card">
          <h3 style={{ marginBottom: 16, color: 'var(--text-primary)' }}>Đã Gửi Thông Báo Mới</h3>
          <form onSubmit={handleSend} style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div className="input-group">
              <label>Đối tượng</label>
              <select className="input" value={targetGroup} onChange={(e) => setTargetGroup(e.target.value)}>
                <option value="ALL">Toàn bộ người dùng</option>
                <option value="DRIVERS">Chỉ tài xế</option>
                <option value="CUSTOMERS">Chỉ khách hàng</option>
              </select>
            </div>
            <div className="input-group">
              <label>Tiêu đề thông báo</label>
              <input type="text" className="input" required value={title} onChange={(e) => setTitle(e.target.value)} placeholder="VD: Khuyến mãi tuần tốt..." />
            </div>
            <div className="input-group">
              <label>Nội dung chi tiết</label>
              <textarea className="input" rows={4} required value={message} onChange={(e) => setMessage(e.target.value)} placeholder="Nhập nội dung thông báo..." />
            </div>
            <button type="submit" className="btn btn-primary" style={{ marginTop: 8 }}>Gửi thông báo ngay</button>
          </form>
        </div>

        <div className="card" style={{ padding: 0 }}>
          <h3 style={{ padding: '20px 24px 0 24px', margin: 0, color: 'var(--text-primary)' }}>Lịch sử thông báo đã gửi</h3>
          {loading ? (
            <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tải thông báo...</div>
          ) : list.length === 0 ? (
            <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Chưa có thông báo nào được gửi.</div>
          ) : (
            <div className="table-responsive">
              <table className="table">
                <thead>
                  <tr>
                    <th>Tiêu đề</th>
                    <th>Nội dung</th>
                    <th>Đối tượng</th>
                    <th>Thời gian</th>
                  </tr>
                </thead>
                <tbody>
                  {list.map((n) => (
                    <tr key={n.id}>
                      <td><strong>{n.title}</strong></td>
                      <td style={{ maxWidth: 250 }}>{n.message}</td>
                      <td>{n.targetUser} ({n.targetPhone})</td>
                      <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{new Date(n.createdAt).toLocaleString('vi-VN')}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
