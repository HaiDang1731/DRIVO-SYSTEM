import { useState, useEffect } from 'react';
import { api } from '../services/api';

export function ReportsPage() {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const res = await api.getReportSummary();
      if (res.success) setData(res.data);
      setLoading(false);
    };
    load();
  }, []);

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val || 0);

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Báo cáo Hoạt động & Chỉ số Kinh doanh</h2>
          <p>Tổng quan hiệu suất vận hành, tỷ lệ hoàn thành chuyến và tài xế xuất sắc</p>
        </div>
      </div>

      {loading ? (
        <div style={{ padding: 60, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tổng hợp báo cáo...</div>
      ) : (
        <div>
          <div className="stats-grid" style={{ marginBottom: 24 }}>
            <div className="stat-card">
              <div className="stat-icon" style={{ backgroundColor: '#6C63FF22', color: '#6C63FF' }}>💰</div>
              <div className="stat-label">Tổng doanh thu hệ thống</div>
              <div className="stat-value">{formatCurrency(data?.totalRevenue)}</div>
            </div>
            <div className="stat-card">
              <div className="stat-icon" style={{ backgroundColor: '#00D4AA22', color: '#00D4AA' }}>✅</div>
              <div className="stat-label">Tỷ lệ hoàn thành chuyến đi</div>
              <div className="stat-value">{data?.completionRate}%</div>
            </div>
            <div className="stat-card">
              <div className="stat-icon" style={{ backgroundColor: '#FFA50222', color: '#FFA502' }}>📋</div>
              <div className="stat-label">Số chuyến hoàn tất / Tổng</div>
              <div className="stat-value">{data?.completedBookings} / {data?.totalBookings}</div>
            </div>
            <div className="stat-card">
              <div className="stat-icon" style={{ backgroundColor: '#FF475722', color: '#FF4757' }}>👥</div>
              <div className="stat-label">Tài xế & Khách hàng</div>
              <div className="stat-value">{data?.totalDrivers} tài xế /  {data?.totalCustomers} khách</div>
            </div>
          </div>

          <div className="card" style={{ padding: 24 }}>
            <h3 style={{ marginBottom: 16, color: 'var(--text-primary)' }}>Top 5 Tài xế Xuất Sắc Nhất Hệ Thống</h3>
            <div className="table-responsive">
              <table className="table">
                <thead>
                  <tr>
                    <th>Họ và tên</th>
                    <th>Số điện thoại</th>
                    <th>Tổng chuyến</th>
                    <th>Đánh giá</th>
                  </tr>
                </thead>
                <tbody>
                  {data?.topDrivers?.map((d: any) => (
                    <tr key={d.id}>
                      <td><strong>{d.fullName}</strong></td>
                      <td>{d.phone}</td>
                      <td><strong style={{ color: '#00D4AA' }}>{d.totalTrips} chuyến</strong></td>
                      <td>⭐{Number(d.ratingAverage).toFixed(1)} / 5.0</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
