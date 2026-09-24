import { useState, useEffect } from 'react';
import { api } from '../services/api';
import { Avatar } from '../components/Avatar';
import { Badge } from '../components/Badge';

export function CustomersPage() {
  const [customers, setCustomers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [selectedCustomer, setSelectedCustomer] = useState<any>(null);

  const load = async () => {
    setLoading(true);
    const res = await api.getCustomers(search);
    if (res.success) {
      setCustomers(res.data?.items || []);
    }
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, [search]);

  const handleToggleStatus = async (c: any) => {
    const newStatus = c.status === 'Active' ? 'Locked' : 'Active';
    await api.setCustomerStatus(c.id, newStatus);
    load();
  };

  const handleViewDetail = async (id: number) => {
    const res = await api.getCustomer(id);
    if (res.success) {
      setSelectedCustomer(res.data);
    }
  };

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val || 0);

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản lý Khách hàng</h2>
          <p>Xem danh sách khách hàng, phương tiện và lịch sử chi tiêu</p>
        </div>
      </div>

      <div className="filter-bar" style={{ marginBottom: 20 }}>
        <div className="search-box" style={{ maxWidth: 400 }}>
          <span className="search-icon">🔍</span>
          <input
            type="text"
            className="search-input"
            placeholder="Tìm theo tên, Số đt, email..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>⏳ Đang tải khách hàng...</div>
        ) : customers.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Không có khách hàng nào.</div>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Khách hàng</th>
                  <th>SỐ ĐT</th>
                  <th>Email</th>
                  <th>Số xe</th>
                  <th>Số chuyến</th>
                  <th>Tổng chi tiêu</th>
                  <th>Trạng thái</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {customers.map((c) => (
                  <tr key={c.id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <Avatar name={c.fullName} />
                        <div>
                          <strong>{c.fullName}</strong>
                          <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>ID: #{c.id}</div>
                        </div>
                      </div>
                    </td>
                    <td>{c.phone}</td>
                    <td>{c.email || '—'}</td>
                    <td>{c.vehicleCount} xe</td>
                    <td>{c.bookingCount} chuyến</td>
                    <td><strong style={{ color: '#00D4AA' }}>{formatCurrency(c.totalSpent)}</strong></td>
                    <td>
                      <Badge type={c.status === 'Active' ? 'success' : 'danger'}>
                        {c.status === 'Active' ? 'Hoạt động' : 'Bị khóa'}
                      </Badge>
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: 6 }}>
                        <button className="btn btn-sm btn-ghost" onClick={() => handleViewDetail(c.id)}>Chi tiết</button>
                        <button
                          className={`btn btn-sm ${c.status === 'Locked' ? 'btn-success' : 'btn-danger'}`}
                          onClick={() => handleToggleStatus(c)}
                        >
                          {c.status === 'Locked' ? 'Mở khóa' : 'Khóa'}
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

      {selectedCustomer && (
        <div className="modal-backdrop">
          <div className="modal" style={{ width: 650, maxWidth: '90vw' }}>
            <div className="modal-header">
              <h3 className="modal-title">Thông tin Khách hàng #{selectedCustomer.id}</h3>
              <button className="btn-close" onClick={() => setSelectedCustomer(null)}>&times;</button>
            </div>
            <div className="modal-body">
              <div style={{ display: 'flex', gap: 16, alignItems: 'center', marginBottom: 20 }}>
                <Avatar name={selectedCustomer.fullName} />
                <div>
                  <h4 style={{ margin: 0, color: 'var(--text-primary)' }}>{selectedCustomer.fullName}</h4>
                  <div style={{ color: 'var(--text-muted)', fontSize: 13 }}>{selectedCustomer.phone} • {selectedCustomer.email || 'Không có email'}</div>
                </div>
              </div>

              <h4 style={{ marginBottom: 10, color: 'var(--text-primary)' }}>🚗 Phương tiện sở hữu ({selectedCustomer.vehicles?.length || 0})</h4>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 20 }}>
                {selectedCustomer.vehicles?.map((v: any) => (
                  <div key={v.id} style={{ padding: 10, background: 'var(--bg-secondary)', borderRadius: 6, display: 'flex', justifyContent: 'space-between' }}>
                    <div>
                      <strong>{v.brand} {v.model} ({v.color})</strong>
                      <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Loại xe: {v.vehicleType} - Số: {v.transmission}</div>
                    </div>
                    <Badge type="info">{v.licensePlate}</Badge>
                  </div>
                ))}
              </div>

              <h4 style={{ marginBottom: 10, color: 'var(--text-primary)' }}> Chuyến đi gần đây</h4>
              {selectedCustomer.recentBookings?.length === 0 ? (
                <div style={{ color: 'var(--text-muted)', fontSize: 13 }}>Chưa có chuyến đi nào.</div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {selectedCustomer.recentBookings?.map((b: any) => (
                    <div key={b.id} style={{ padding: 10, background: 'var(--bg-secondary)', borderRadius: 6, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <div>
                        <strong>{b.bookingCode}</strong>
                        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{b.pickupAddress} - {b.destinationAddress}</div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <div style={{ color: '#00D4AA', fontWeight: 'bold' }}>{formatCurrency(b.price)}</div>
                        <Badge type={b.status === 'Completed' ? 'success' : 'info'}>{b.status}</Badge>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
