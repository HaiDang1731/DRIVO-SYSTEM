import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../services/api';
import { Badge } from '../components/Badge';

export function BookingsPage() {
  const [bookings, setBookings] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const navigate = useNavigate();

  const load = async () => {
    setLoading(true);
    const res = await api.getBookings(statusFilter || undefined, search || undefined);
    if (res.success) {
      setBookings(res.data?.items || []);
    }
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, [statusFilter, search]);

  const handleCancel = async (id: number) => {
    const reason = window.prompt('Nhập lý do hủy chuyến:');
    if (!reason) return;
    const res = await api.cancelBooking(id, reason);
    if (res.success) {
      alert('Đã hủy chuyến đi thành công!');
      load();
    }
  };

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val || 0);

  const formatDate = (dateStr: string) => new Date(dateStr).toLocaleString('vi-VN');

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản lý Chuyến đi</h2>
          <p>Theo dõi lịch trình, trạng thái và giá cước các cuốc xe theo thời gian thực</p>
        </div>
      </div>

      <div className="filter-bar" style={{ display: 'flex', gap: 12, marginBottom: 20 }}>
        <div className="search-box" style={{ flex: 1, maxWidth: 350 }}>
          <span className="search-icon">🔍</span>
          <input
            type="text"
            className="search-input"
            placeholder="Tìm theo mã cuốc, địa chỉ, khách, tài xế..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>

        <div className="filter-pills">
          <button className={`filter-pill ${statusFilter === '' ? 'active' : ''}`} onClick={() => setStatusFilter('')}>Tất cả</button>
          <button className={`filter-pill ${statusFilter === 'Pending' ? 'active' : ''}`} onClick={() => setStatusFilter('Pending')}>Chờ tài xế</button>
          <button className={`filter-pill ${statusFilter === 'DriverAssigned' ? 'active' : ''}`} onClick={() => setStatusFilter('DriverAssigned')}>Đã nhận</button>
          <button className={`filter-pill ${statusFilter === 'InProgress' ? 'active' : ''}`} onClick={() => setStatusFilter('InProgress')}>Đang chạy</button>
          <button className={`filter-pill ${statusFilter === 'Completed' ? 'active' : ''}`} onClick={() => setStatusFilter('Completed')}>Hoàn thành</button>
          <button className={`filter-pill ${statusFilter === 'Cancelled' ? 'active' : ''}`} onClick={() => setStatusFilter('Cancelled')}>Đã hủy</button>
        </div>
      </div>

      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>⏳ Đang tải danh sách chuyến đi...</div>
        ) : bookings.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Không tìm thấy chuyến đi nào.</div>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Mã cuốc</th>
                  <th>Khách hàng</th>
                  <th>Tài xế</th>
                  <th>Điểm đón & Điểm đến</th>
                  <th>Khoảng cách</th>
                  <th>Giá cước</th>
                  <th>Trạng thái</th>
                  <th>Thời gian</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {bookings.map((b) => (
                  <tr key={b.id} className="row-clickable" onClick={() => navigate(`/bookings/${b.id}`)} title="Xem chi tiết chuyến">
                    <td><strong style={{ color: 'var(--accent)' }}>{b.bookingCode}</strong></td>
                    <td>
                      <div>{b.customerName}</div>
                      <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{b.customerPhone}</div>
                    </td>
                    <td>
                      <div>{b.driverName}</div>
                      <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{b.driverPhone}</div>
                    </td>
                    <td style={{ maxWidth: 220 }}>
                      <div style={{ fontSize: 13, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={b.pickupAddress}>🟢 {b.pickupAddress}</div>
                      <div style={{ fontSize: 13, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={b.destinationAddress}>🔴 {b.destinationAddress}</div>
                    </td>
                    <td>{b.distanceKm ? `${b.distanceKm} km` : '—'}</td>
                    <td><strong style={{ color: '#00D4AA' }}>{formatCurrency(b.price)}</strong></td>
                    <td><Badge type={b.status === 'Completed' ? 'success' : b.status === 'Cancelled' ? 'danger' : 'warning'}>{b.status}</Badge></td>
                    <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{formatDate(b.createdAt)}</td>
                    <td>
                      {b.status !== 'Completed' && b.status !== 'Cancelled' && (
                        <button className="btn btn-sm btn-danger" onClick={(e) => { e.stopPropagation(); handleCancel(b.id); }}>Hủy cuốc</button>
                      )}
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
