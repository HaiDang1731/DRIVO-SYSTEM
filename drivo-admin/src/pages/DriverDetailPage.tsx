import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { api } from '../services/api';
import { Avatar } from '../components/Avatar';
import { Badge } from '../components/Badge';
import { DriverLocationCard } from '../components/DriverLocationCard';
import { DriverProfilePanel } from '../components/DriverProfilePanel';

export default function DriverDetailPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<'profile' | 'trips' | 'ratings' | 'history' | 'revenue'>('profile');
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [resettingPassword, setResettingPassword] = useState(false);
  const [customPassword, setCustomPassword] = useState('');
  const [actionMsg, setActionMsg] = useState<{ text: string; type: 'success' | 'error' } | null>(null);

  const fetchDetail = async () => {
    if (!id) return;
    setLoading(true);
    const res = await api.getDriver(id);
    if (res.success) {
      setData(res.data);
    } else {
      setActionMsg({ text: res.message || 'Lỗi tải thông tin tài xế', type: 'error' });
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchDetail();
  }, [id]);

  const handleResetPassword = async () => {
    if (!window.confirm('Bạn có chắc chắn muốn đặt lại mật khẩu cho tài xế này?')) return;
    setResettingPassword(true);
    const res = await api.resetDriverPassword(id!, customPassword || undefined);
    if (res.success) {
      setActionMsg({ text: res.message || 'Đặt lại mật khẩu thành công!', type: 'success' });
      setCustomPassword('');
    } else {
      setActionMsg({ text: res.message || 'Lỗi khi đặt lại mật khẩu', type: 'error' });
    }
    setResettingPassword(false);
  };

  const handleToggleLock = async () => {
    if (!data) return;
    const newStatus = data.accountStatus === 'Locked' ? 'Active' : 'Locked';
    const res = await api.setDriverStatus(data.driverId, newStatus);
    if (res.success) {
      setActionMsg({ text: `Đã ${newStatus === 'Locked' ? 'khóa' : 'mở khóa'} tài khoản thành công!`, type: 'success' });
      fetchDetail();
    } else {
      setActionMsg({ text: res.message || 'Thao tác thất bại', type: 'error' });
    }
  };

  const formatCurrency = (val?: number) =>
    new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val || 0);

  const formatDate = (dateStr?: string) => {
    if (!dateStr) return;
    try {
      return new Date(dateStr).toLocaleString('vi-VN', {
        hour: '2-digit',
        minute: '2-digit',
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      });
    } catch {
      return dateStr;
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div className="topbar" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 24px', background: 'var(--bg-secondary)', borderBottom: '1px solid var(--border)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <button className="btn btn-ghost" onClick={() => navigate('/drivers')} style={{ padding: '8px 12px', marginRight: 16 }}>
            ← Quay lại
          </button>
          <span style={{ fontSize: 24 }}>🪪</span>
          <div>
            <h3 className="modal-title" style={{ margin: 0 }}>Hồ Sơ Toàn Diện Tài Xế</h3>
            <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>Mã tài xế: #{id} · User ID: #{data?.userId ?? '...'}</div>
          </div>
        </div>
      </div>

      {actionMsg && (
        <div
          style={{
            padding: '10px 20px',
            backgroundColor: actionMsg.type === 'success' ? '#00D4AA22' : '#FF475722',
            color: actionMsg.type === 'success' ? '#00D4AA' : '#FF4757',
            borderBottom: '1px solid var(--border)',
            fontSize: 13,
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center'
          }}
        >
          <span>{actionMsg.text}</span>
          <button style={{ background: 'none', border: 'none', color: 'inherit', cursor: 'pointer' }} onClick={() => setActionMsg(null)}>✕</button>
        </div>
      )}

      <div className="modal-body" style={{ padding: 0, flex: 1, display: 'flex', overflow: 'hidden' }}>
        {loading ? (
          <div style={{ padding: 60, width: '100%', textAlign: 'center', color: 'var(--text-muted)' }}>
            ⏳ Đang tải thông tin chi tiết từ hệ thống...
          </div>
        ) : !data ? (
          <div style={{ padding: 60, width: '100%', textAlign: 'center', color: 'var(--text-muted)' }}>
            Không tìm thấy dữ liệu tài xế.
          </div>
        ) : (
          <div style={{ display: 'flex', width: '100%', overflow: 'hidden' }}>
            {/* Sidebar Menu */}
            <div
              style={{
                width: 240,
                borderRight: '1px solid var(--border)',
                padding: '24px 16px',
                display: 'flex',
                flexDirection: 'column',
                gap: 6,
                background: 'rgba(255,255,255,0.01)'
              }}
            >
              <div style={{ textAlign: 'center', marginBottom: 20 }}>
                <div style={{ display: 'flex', justifyContent: 'center' }}>
                  <Avatar name={data.fullName} src={data.avatarUrl} size={72} />
                </div>
                <h4 style={{ marginTop: 12, marginBottom: 4, color: 'var(--text-primary)', fontSize: 16 }}>{data.fullName}</h4>
                <div style={{ color: 'var(--text-muted)', fontSize: 13, marginBottom: 10 }}>{data.phone}</div>
                <div style={{ display: 'flex', justifyContent: 'center', gap: 6, flexWrap: 'wrap' }}>
                  <Badge type={data.accountStatus === 'Active' ? 'success' : 'danger'}>
                    {data.accountStatus === 'Active' ? 'Hoạt động' : 'Bị khóa'}
                  </Badge>
                  <Badge type={data.verificationStatus === 'Approved' ? 'success' : data.verificationStatus === 'Pending' ? 'warning' : 'danger'}>
                    {data.verificationStatus}
                  </Badge>
                </div>
              </div>

              <button
                className={`btn btn-sm ${activeTab === 'profile' ? 'btn-primary' : 'btn-ghost'}`}
                style={{ justifyContent: 'flex-start' }}
                onClick={() => setActiveTab('profile')}
              >
                👤 Hồ sơ & Tài khoản
              </button>
              <button
                className={`btn btn-sm ${activeTab === 'trips' ? 'btn-primary' : 'btn-ghost'}`}
                style={{ justifyContent: 'flex-start' }}
                onClick={() => setActiveTab('trips')}
              >
                🚗 Chuyến đi ({data.trips?.length || 0})
              </button>
              <button
                className={`btn btn-sm ${activeTab === 'ratings' ? 'btn-primary' : 'btn-ghost'}`}
                style={{ justifyContent: 'flex-start' }}
                onClick={() => setActiveTab('ratings')}
              >
                ⭐Đánh giá ({data.ratings?.length || 0})
              </button>
              <button
                className={`btn btn-sm ${activeTab === 'revenue' ? 'btn-primary' : 'btn-ghost'}`}
                style={{ justifyContent: 'flex-start' }}
                onClick={() => setActiveTab('revenue')}
              >
                💰 Thống kê thu nhập
              </button>
              <button
                className={`btn btn-sm ${activeTab === 'history' ? 'btn-primary' : 'btn-ghost'}`}
                style={{ justifyContent: 'flex-start' }}
                onClick={() => setActiveTab('history')}
              >
                ⏱️Lịch sử trạng thái ({data.statusHistory?.length || 0})
              </button>

              <div style={{ marginTop: 'auto', paddingTop: 16, borderTop: '1px solid var(--border)' }}>
                <button
                  className={`btn btn-sm ${data.accountStatus === 'Locked' ? 'btn-success' : 'btn-danger'}`}
                  style={{ width: '100%' }}
                  onClick={handleToggleLock}
                >
                  {data.accountStatus === 'Locked' ? '🔓 Mở khóa tài khoản' : '🔒 Khóa tài khoản'}
                </button>
              </div>
            </div>

            {/* Tab Contents */}
            <div style={{ flex: 1, padding: '24px 28px', overflowY: 'auto' }}>
              {activeTab === 'profile' && (
                <div>
                  <DriverProfilePanel
                    data={data}
                    onReload={fetchDetail}
                    onMessage={(text, type) => setActionMsg({ text, type })}
                  />

                  <h4 style={{ marginBottom: 16, color: 'var(--text-primary)', borderBottom: '1px solid var(--border)', paddingBottom: 8 }}>
                    Vị Trí Hiện Tại
                  </h4>
                  <div style={{ marginBottom: 24 }}>
                    <DriverLocationCard driverId={Number(data.driverId ?? id)} />
                  </div>

                  <h4 style={{ marginBottom: 16, color: 'var(--text-primary)', borderBottom: '1px solid var(--border)', paddingBottom: 8 }}>
                    Bảo Mật & Mật Khẩu
                  </h4>
                  <div style={{ padding: 16, background: 'var(--bg-secondary)', borderRadius: 8 }}>
                    <p style={{ margin: '0 0 12px 0', fontSize: 13, color: 'var(--text-muted)' }}>
                      Mật khẩu tài khoản được mã hóa một chiều bằng chuẩn <strong>PBKDF2 (350.000 vòng lặp SHA256)</strong> để đảm bảo an toàn tối đa. Admin có thể đặt lại mật khẩu mới cho tài xế dưới đây:
                    </p>
                    <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                      <input
                        type="text"
                        className="input"
                        placeholder="Nhập mật khẩu mới (hoặc để trống để đặt lại vềSố Điện Thoại hoặc email)"
                        value={customPassword}
                        onChange={(e) => setCustomPassword(e.target.value)}
                        style={{ flex: 1 }}
                      />
                      <button
                        className="btn btn-primary"
                        onClick={handleResetPassword}
                        disabled={resettingPassword}
                      >
                        {resettingPassword ? 'Đang đặt lại...' : 'Đặt lại mật khẩu'}
                      </button>
                    </div>
                  </div>
                </div>
              )}

              {activeTab === 'trips' && (
                <div>
                  <h4 style={{ marginBottom: 16, color: 'var(--text-primary)' }}>Lịch Sử Chuyến Đi Thực Tế</h4>
                  {data.trips && data.trips.length > 0 ? (
                    <div className="table-responsive">
                      <table className="table">
                        <thead>
                          <tr>
                            <th>Mã chuyến</th>
                            <th>Khách hàng</th>
                            <th>Điểm đón</th>
                            <th>Điểm đến</th>
                            <th>Khoảng cách</th>
                            <th>Cước phí</th>
                            <th>Trạng thái</th>
                            <th>Thời gian</th>
                          </tr>
                        </thead>
                        <tbody>
                          {data.trips.map((t: any) => (
                            <tr key={t.id}>
                              <td><strong style={{ color: 'var(--accent)' }}>{t.bookingCode}</strong></td>
                              <td>
                                <div>{t.customerName || 'Khách vãng lai'}</div>
                                <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{t.customerPhone || ''}</div>
                              </td>
                              <td style={{ maxWidth: 160, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={t.pickupAddress}>{t.pickupAddress}</td>
                              <td style={{ maxWidth: 160, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={t.destinationAddress}>{t.destinationAddress}</td>
                              <td>{t.distanceKm ? `${t.distanceKm} km` : 'Không có dữ liệu'}</td>
                              <td><strong style={{ color: '#00D4AA' }}>{formatCurrency(t.amount)}</strong></td>
                              <td><Badge type={t.status === 'Completed' ? 'success' : t.status === 'Cancelled' ? 'danger' : 'info'}>{t.status}</Badge></td>
                              <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{formatDate(t.createdAt)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  ) : (
                    <div style={{ padding: 40, textAlign: 'center', background: 'var(--bg-secondary)', borderRadius: 8, color: 'var(--text-muted)' }}>
                      🚗 Tài xế này chưa có chuyến đi nào trong cơ sở dữ liệu.
                    </div>
                  )}
                </div>
              )}

              {activeTab === 'ratings' && (
                <div>
                  <h4 style={{ marginBottom: 16, color: 'var(--text-primary)' }}>Đánh Giá Từ Khách Hàng</h4>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 24, marginBottom: 24, padding: 18, background: 'var(--bg-secondary)', borderRadius: 8 }}>
                    <div style={{ fontSize: 42, fontWeight: 'bold', color: 'var(--accent)' }}>
                      {data.ratingAverage ? Number(data.ratingAverage).toFixed(1) : '5.0'}
                    </div>
                    <div>
                      <div style={{ color: '#F59E0B', fontSize: 20 }}>
                        {'⭐'.repeat(Math.round(data.ratingAverage || 5))}
                      </div>
                      <div style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 4 }}>
                        Tổng cộng <strong>{data.ratingCount || 0}</strong> lượt đánh giá.
                      </div>
                    </div>
                  </div>

                  {data.ratings && data.ratings.length > 0 ? (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
                      {data.ratings.map((r: any) => (
                        <div key={r.id} style={{ padding: 14, background: 'var(--bg-secondary)', borderRadius: 8 }}>
                          <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
                            <strong style={{ color: 'var(--text-primary)' }}>{r.customerName}</strong>
                            <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{formatDate(r.createdAt)}</span>
                          </div>
                          <div style={{ color: '#F59E0B', fontSize: 13, marginBottom: 6 }}>{'⭐'.repeat(r.score)}</div>
                          <div style={{ fontSize: 14, color: 'var(--text-secondary)' }}>{r.comment || 'Không có bình luận'}</div>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div style={{ padding: 40, textAlign: 'center', background: 'var(--bg-secondary)', borderRadius: 8, color: 'var(--text-muted)' }}>
                      ⭐Chưa có nhận xét đánh giá nào từ khách hàng.
                    </div>
                  )}
                </div>
              )}

              {activeTab === 'revenue' && (
                <div>
                  <h4 style={{ marginBottom: 16, color: 'var(--text-primary)' }}>Thống Kê Thu Nhập & Hoạt Động</h4>
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, marginBottom: 24 }}>
                    <div style={{ background: 'var(--bg-secondary)', padding: 20, borderRadius: 8 }}>
                      <div style={{ color: 'var(--text-muted)', fontSize: 13, marginBottom: 8 }}>Tổng doanh thu hoàn thành</div>
                      <div style={{ fontSize: 24, fontWeight: 'bold', color: '#00D4AA' }}>{formatCurrency(data.totalEarnings)}</div>
                    </div>
                    <div style={{ background: 'var(--bg-secondary)', padding: 20, borderRadius: 8 }}>
                      <div style={{ color: 'var(--text-muted)', fontSize: 13, marginBottom: 8 }}>Tổng sốchuyến hoàn tất</div>
                      <div style={{ fontSize: 24, fontWeight: 'bold', color: 'var(--accent)' }}>{data.totalTrips || 0}</div>
                    </div>
                    <div style={{ background: 'var(--bg-secondary)', padding: 20, borderRadius: 8 }}>
                      <div style={{ color: 'var(--text-muted)', fontSize: 13, marginBottom: 8 }}>Tổng quãng đường ước tính</div>
                      <div style={{ fontSize: 24, fontWeight: 'bold', color: '#FFA502' }}>{(data.totalDistanceKm || 0).toFixed(1)} km</div>
                    </div>
                  </div>
                </div>
              )}

              {activeTab === 'history' && (
                <div>
                  <h4 style={{ marginBottom: 16, color: 'var(--text-primary)' }}>Lịch Sử Thay Đổi Trạng Thái</h4>
                  {data.statusHistory && data.statusHistory.length > 0 ? (
                    <div className="table-responsive">
                      <table className="table">
                        <thead>
                          <tr>
                            <th>Thời gian</th>
                            <th>Trạng thái cũ</th>
                            <th>Trạng thái mới</th>
                            <th>Lý do</th>
                          </tr>
                        </thead>
                        <tbody>
                          {data.statusHistory.map((h: any) => (
                            <tr key={h.id}>
                              <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{formatDate(h.changedAt)}</td>
                              <td>{h.oldStatus || '—'}</td>
                              <td><Badge type="info">{h.newStatus}</Badge></td>
                              <td>{h.reason || '—'}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  ) : (
                    <div style={{ padding: 40, textAlign: 'center', background: 'var(--bg-secondary)', borderRadius: 8, color: 'var(--text-muted)' }}>
                      ⏱️Chưa có bản ghi lịch sử trạng thái nào.
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
