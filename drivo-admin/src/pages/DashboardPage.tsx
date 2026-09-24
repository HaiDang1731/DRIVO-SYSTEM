import { useEffect, useState } from 'react';
import { api } from '../services/api';
import { ResponsiveContainer, ComposedChart, Line, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend } from 'recharts';

export function DashboardPage() {
  const [overview, setOverview] = useState<any>(null);
  const [chartData, setChartData] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [platformToday, setPlatformToday] = useState<number | null>(null);

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
      const now = new Date();
      const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
      const [resOverview, resChart, resRevenue] = await Promise.all([
        api.getDashboardOverview(),
        api.getDashboardChart(7),
        api.getRevenueReport(today, today)
      ]);

      if (resOverview.success) setOverview(resOverview.data);
      if (resRevenue.success && resRevenue.data) setPlatformToday(resRevenue.data.summary.platformNet);
      if (resChart.success) {
        // Format date for chart
        const formatted = resChart.data.map((item: any) => ({
          ...item,
          name: new Date(item.date).toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit' })
        }));
        setChartData(formatted);
      }
      setLoading(false);
    };
    fetchData();
  }, []);

  const stats = [
    { label: 'Tài xế', value: overview?.totalDrivers ?? '—', icon: '🚗', color: '#6C63FF' },
    { label: 'Chờ duyệt', value: overview?.totalPendingDrivers ?? '—', icon: '⏳', color: '#FFA502' },
    { label: 'Khách hàng', value: overview?.totalCustomers ?? '—', icon: '👥', color: '#00D4AA' },
    { label: 'Tổng cước hôm nay', value: overview ? new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(overview.totalRevenueToday) : '—', icon: '💰', color: '#FF4757' },
    { label: 'DRIVO thực thu hôm nay', value: platformToday != null ? new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(platformToday) : '—', icon: '🏦', color: '#00D4AA' },
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
            {new Date().toLocaleDateString('vi-VN', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
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

      <div className="card" style={{ marginTop: 24, padding: 24 }}>
        <h3 style={{ marginBottom: 20, color: 'var(--text-primary)' }}>Doanh thu & Chuyến đi (7 ngày qua)</h3>
        {loading ? (
          <div style={{ height: 300, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)' }}>
            ⏳ Đang tải dữ liệu...
          </div>
        ) : chartData.length === 0 ? (
          <div style={{ height: 300, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)' }}>
            Chưa có dữ liệu
          </div>
        ) : (
          <div style={{ height: 400, width: '100%' }}>
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={chartData} margin={{ top: 20, right: 20, bottom: 20, left: 20 }}>
                <CartesianGrid stroke="#ffffff10" strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="name" stroke="#888" tick={{ fill: '#888', fontSize: 12 }} axisLine={false} tickLine={false} dy={10} />
                <YAxis yAxisId="left" stroke="#888" tick={{ fill: '#888', fontSize: 12 }} axisLine={false} tickLine={false} tickFormatter={(value) => `${value.toLocaleString()}đ`} />
                <YAxis yAxisId="right" orientation="right" stroke="#888" tick={{ fill: '#888', fontSize: 12 }} axisLine={false} tickLine={false} />
                <Tooltip 
                  contentStyle={{ backgroundColor: '#1c1c1e', borderColor: '#333', borderRadius: 8, color: '#fff' }}
                  itemStyle={{ color: '#fff' }}
                />
                <Legend wrapperStyle={{ paddingTop: 20 }} />
                <Bar yAxisId="left" dataKey="revenue" name="Doanh thu (VNĐ)" barSize={20} fill="#6C63FF" radius={[4, 4, 0, 0]} />
                <Line yAxisId="right" type="monotone" dataKey="tripsCount" name="Số chuyến đi" stroke="#00D4AA" strokeWidth={3} dot={{ r: 4, fill: '#00D4AA', strokeWidth: 0 }} activeDot={{ r: 6 }} />
              </ComposedChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>
    </div>
  );
}
