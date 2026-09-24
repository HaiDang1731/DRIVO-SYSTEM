import { useState, useEffect } from 'react';
import { api } from '../services/api';
import { Badge } from '../components/Badge';

export function PaymentsPage() {
  const [payments, setPayments] = useState<any[]>([]);
  const [summary, setSummary] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const res = await api.getPayments();
      if (res.success) {
        setPayments(res.data?.items || []);
        setSummary(res.data?.summary || null);
      }
      setLoading(false);
    };
    load();
  }, []);

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val || 0);

  const formatDate = (dateStr: string) => new Date(dateStr).toLocaleString('vi-VN');

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản Lý Thanh Toán & Giao Dịch</h2>
          <p>Tổng hợp doanh thu, phương thức thanh toán và các khoản thu thành công</p>
        </div>
      </div>

      <div className="stats-grid" style={{ marginBottom: 24 }}>
        <div className="stat-card">
          <div className="stat-icon" style={{ backgroundColor: '#6C63FF22', color: '#6C63FF' }}>💰</div>
          <div className="stat-label">Tổng doanh thu đã thanh toán</div>
          <div className="stat-value">{formatCurrency(summary?.totalRevenue)}</div>
        </div>
        <div className="stat-card">
          <div className="stat-icon" style={{ backgroundColor: '#00D4AA22', color: '#00D4AA' }}>✅</div>
          <div className="stat-label">Giao dịch thành công</div>
          <div className="stat-value">{summary?.completedCount ?? '—'}</div>
        </div>
        <div className="stat-card">
          <div className="stat-icon" style={{ backgroundColor: '#FFA50222', color: '#FFA502' }}>⏳</div>
          <div className="stat-label">Chờ xử lý</div>
          <div className="stat-value">{summary?.pendingCount ?? '—'}</div>
        </div>
      </div>

      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tải giao dịch...</div>
        ) : payments.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Chưa có giao dịch thanh toán nào.</div>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Mã giao dịch</th>
                  <th>Mã chuyến</th>
                  <th>Khách hàng</th>
                  <th>Số tiền</th>
                  <th>Phương thức</th>
                  <th>Trạng thái</th>
                  <th>Ngày thanh toán</th>
                </tr>
              </thead>
              <tbody>
                {payments.map((p) => (
                  <tr key={p.id}>
                    <td>#{p.id}</td>
                    <td><strong style={{ color: 'var(--accent)' }}>{p.bookingCode}</strong></td>
                    <td>
                      <div>{p.customerName}</div>
                      <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{p.customerPhone}</div>
                    </td>
                    <td><strong style={{ color: '#00D4AA' }}>{formatCurrency(p.amount)}</strong></td>
                    <td><Badge type="info">{p.paymentMethod}</Badge></td>
                    <td><Badge type={p.paymentStatus === 'Success' ? 'success' : 'warning'}>{p.paymentStatus}</Badge></td>
                    <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{p.paidAt ? formatDate(p.paidAt) : 'Chưa'}</td>
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
