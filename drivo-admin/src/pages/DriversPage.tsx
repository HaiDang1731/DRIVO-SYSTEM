import { useState, useEffect, useCallback } from 'react';
import { api } from '../services/api';
import { Toast } from '../components/Toast';
import { Avatar } from '../components/Avatar';
import { Badge } from '../components/Badge';
import { useNavigate } from 'react-router-dom';
import { CreateDriverModal } from '../components/CreateDriverModal';
import { VerifyModal } from '../components/VerifyModal';

export function DriversPage() {
  const [drivers, setDrivers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');
  const [search, setSearch] = useState('');

  const [toast, setToast] = useState<{ msg: string, type: 'success' | 'error' } | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [verifyTarget, setVerifyTarget] = useState<any>(null);
  const navigate = useNavigate();

  const load = useCallback(async () => {
    setLoading(true);
    const res = await api.getDrivers(filter, 1, 100);
    setLoading(false);
    if (res.success) setDrivers(res.data.items || res.data || []);
    else setToast({ msg: 'Lỗi tải danh sách tài xế', type: 'error' });
  }, [filter]);

  useEffect(() => { load(); }, [load]);

  const filtered = drivers.filter(d =>
    !search || d.fullName.toLowerCase().includes(search.toLowerCase()) ||
    d.phone.includes(search) || d.licenseNumber.toLowerCase().includes(search.toLowerCase())
  );

  const handleToggleLock = async (d: any) => {
    const newStatus = d.accountStatus === 'Locked' ? 'Active' : 'Locked';
    await api.setDriverStatus(d.driverId, newStatus);
    setToast({ msg: `Đã ${newStatus === 'Locked' ? 'khóa' : 'mở khóa'} tài khoản`, type: 'success' });
    load();
  };


  return (
    <div>
      {toast && <Toast msg={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
      {showCreate && <CreateDriverModal onClose={() => setShowCreate(false)} onCreated={() => { load(); setToast({ msg: 'Tạo tài xế thành công!', type: 'success' }); }} />}
      {verifyTarget && <VerifyModal driver={verifyTarget} onClose={() => setVerifyTarget(null)} onDone={() => { load(); setToast({ msg: 'Cập nhật  thành công!', type: 'success' }); }} />}

      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản lý tài xế</h2>
          <p>Tạo, duy trì và quản lý tài khoản tài xế</p>
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
              {s === '' ? 'Tất cả' : s === 'Pending' ? 'Đang chờ duyệt' : s === 'Approved' ? 'Đã duyệt' : 'Không duyệt'}
            </button>
          ))}
          <div style={{ marginLeft: 'auto', fontSize: 13, color: 'var(--text-muted)' }}>
            {filtered.length} tài xế
          </div>
        </div>
      </div>

      <div className="card">
        {loading ? (
          <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>Đang tải...</div>
        ) : filtered.length === 0 ? (
          <div className="empty-state">
            <div className="empty-icon">🚗</div>
            <h3>Chưa có tài xế nào</h3>
            <p>Nhấp "+ Thêm tài xế" để đăng ký tài xế đầu tiên</p>
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
                  <th>Xác minh</th>
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
                          <div className="phone">{d.email ?? '-'}</div>
                        </div>
                      </div>
                    </td>
                    <td style={{ color: 'var(--text-primary)', fontWeight: 500 }}>{d.phone}</td>
                    <td>
                      <div style={{ fontFamily: 'monospace', color: 'var(--accent)', fontSize: 12 }}>{d.licenseNumber || 'Chưa khai báo'}</div>
                      {(() => {
                        if (!d.licenseExpiryDate) return null;
                        const days = Math.ceil((new Date(`${d.licenseExpiryDate}T00:00:00`).getTime() - Date.now()) / 86400000);
                        if (days < 0) return <div style={{ fontSize: 11, color: '#FF4757' }}>Hết hạn</div>;
                        if (days <= 30) return <div style={{ fontSize: 11, color: '#FFA502' }}>Hết hạn sau {days} ngày</div>;
                        return null;
                      })()}
                    </td>
                    <td>{d.licenseClass ?? '-'}</td>
                    <td>
                      <Badge value={d.verificationStatus} />
                      {d.profileReviewPending && (
                        <div style={{ fontSize: 11, color: '#FFA502', marginTop: 4 }}>
                          ⚠ Cần duyệt lại{d.pendingDocuments ? ` · ${d.pendingDocuments} ảnh chờ` : ''}
                        </div>
                      )}
                      {!d.profileReviewPending && d.pendingDocuments > 0 && (
                        <div style={{ fontSize: 11, color: '#FFA502', marginTop: 4 }}>{d.pendingDocuments} ảnh chờ duyệt</div>
                      )}
                    </td>
                    <td><Badge value={d.driverStatus} /></td>
                    <td>{new Date(d.createdAt).toLocaleDateString('vi-VN')}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 6 }}>
                        {d.verificationStatus === 'Pending' && (
                          <button className="btn btn-sm btn-success" onClick={() => setVerifyTarget(d)}>
                            Duyệt
                          </button>
                        )}
                        <button className="btn btn-sm btn-ghost" onClick={() => navigate('/drivers/' + d.driverId)}>
                          Chi tiết
                        </button>
                        <button className={`btn btn-sm ${d.accountStatus === 'Locked' ? 'btn-danger' : 'btn-success'}`}
                          onClick={() => handleToggleLock(d)}>
                          {d.accountStatus === 'Locked' ? 'Mở khóa' : 'Khóa'}
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
