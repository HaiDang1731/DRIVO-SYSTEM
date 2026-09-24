import { useState, useEffect, useMemo } from 'react';
import { ResponsiveContainer, ComposedChart, Line, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend } from 'recharts';
import { api, RevenueReport } from '../services/api';
import { formatVND, vehicleTypeLabel } from '../utils/geo';

function isoDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function daysAgo(n: number): string {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return isoDate(d);
}

const PRESETS: { label: string; range: () => [string, string] }[] = [
  { label: 'Hôm nay', range: () => [daysAgo(0), daysAgo(0)] },
  { label: '7 ngày', range: () => [daysAgo(6), daysAgo(0)] },
  { label: '30 ngày', range: () => [daysAgo(29), daysAgo(0)] },
  {
    label: 'Tháng này',
    range: () => {
      const now = new Date();
      return [isoDate(new Date(now.getFullYear(), now.getMonth(), 1)), isoDate(now)];
    },
  },
];

export function ReportsPage() {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  const [range, setRange] = useState<[string, string]>(() => PRESETS[2].range());
  const [revenue, setRevenue] = useState<RevenueReport | null>(null);
  const [revenueLoading, setRevenueLoading] = useState(true);
  const [revenueError, setRevenueError] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      const res = await api.getReportSummary();
      if (res.success) setData(res.data);
      setLoading(false);
    };
    load();
  }, []);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      setRevenueLoading(true);
      setRevenueError(null);
      try {
        const res = await api.getRevenueReport(range[0], range[1]);
        if (cancelled) return;
        if (res.success && res.data) setRevenue(res.data);
        else setRevenueError(res.message || 'Không tải được báo cáo doanh thu');
      } catch {
        if (!cancelled) setRevenueError('Không kết nối được máy chủ API');
      }
      if (!cancelled) setRevenueLoading(false);
    };
    load();
    return () => { cancelled = true; };
  }, [range]);

  const chartData = useMemo(
    () =>
      (revenue?.byDay ?? []).map((d) => ({
        name: new Date(`${d.date}T00:00:00`).toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit' }),
        commission: d.totals.commission,
        platformNet: d.totals.platformNet,
        trips: d.totals.trips,
      })),
    [revenue],
  );

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val || 0);

  const s = revenue?.summary;
  const commissionRate = s && s.grossFare > 0 ? (s.commission / s.grossFare) * 100 : 0;
  const revenueCards = [
    { label: 'Tổng cước (trước khuyến mãi)', value: s?.grossFare, icon: '🧾', color: '#6C63FF', note: `${s?.trips ?? 0} chuyến hoàn thành` },
    { label: 'Hoa hồng DRIVO', value: s?.commission, icon: '💼', color: '#00D4AA', note: `≈ ${commissionRate.toFixed(1)}% tổng cước` },
    { label: 'Khuyến mãi DRIVO chịu', value: s?.voucherCost, icon: '🎟️', color: '#FFA502', note: 'Trừ vào phần của DRIVO' },
    { label: 'DRIVO thực thu', value: s?.platformNet, icon: '🏦', color: '#FF4757', note: 'Hoa hồng − khuyến mãi' },
  ];

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Báo cáo Hoạt động & Chỉ số Kinh doanh</h2>
          <p>Doanh thu nền tảng, hiệu suất vận hành và tài xế xuất sắc</p>
        </div>
      </div>

      {/* ── Doanh thu nền tảng ── */}
      <div className="card" style={{ padding: 24, marginBottom: 24 }}>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
          <h3 style={{ margin: 0, color: 'var(--text-primary)' }}>Doanh thu nền tảng DRIVO</h3>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center' }}>
            {PRESETS.map((p) => {
              const [f, t] = p.range();
              const active = f === range[0] && t === range[1];
              return (
                <button key={p.label} className={`btn btn-sm ${active ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setRange([f, t])}>
                  {p.label}
                </button>
              );
            })}
            <input type="date" className="input" style={{ width: 150 }} value={range[0]} max={range[1]}
              onChange={(e) => e.target.value && setRange([e.target.value, range[1]])} />
            <span style={{ color: 'var(--text-muted)' }}>→</span>
            <input type="date" className="input" style={{ width: 150 }} value={range[1]} min={range[0]} max={daysAgo(0)}
              onChange={(e) => e.target.value && setRange([range[0], e.target.value])} />
          </div>
        </div>

        {revenueError && <div className="error-msg" style={{ marginBottom: 16 }}>{revenueError}</div>}

        <div className="stats-grid" style={{ marginBottom: 24, opacity: revenueLoading ? 0.5 : 1 }}>
          {revenueCards.map((c) => (
            <div className="stat-card" key={c.label}>
              <div className="stat-icon" style={{ backgroundColor: `${c.color}22`, color: c.color }}>{c.icon}</div>
              <div className="stat-label">{c.label}</div>
              <div className="stat-value" style={c.value != null && c.value < 0 ? { color: '#FF4757' } : undefined}>{formatVND(c.value ?? 0)}</div>
              <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>{c.note}</div>
            </div>
          ))}
        </div>

        <h4 style={{ margin: '0 0 12px', color: 'var(--text-secondary)' }}>Theo ngày</h4>
        {chartData.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>{revenueLoading ? 'Đang tải...' : 'Chưa có dữ liệu'}</div>
        ) : (
          <div style={{ height: 320, width: '100%', marginBottom: 24 }}>
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={chartData} margin={{ top: 10, right: 10, bottom: 10, left: 10 }}>
                <CartesianGrid stroke="#ffffff10" strokeDasharray="3 3" vertical={false} />
                <XAxis dataKey="name" stroke="#888" tick={{ fill: '#888', fontSize: 12 }} axisLine={false} tickLine={false} />
                <YAxis yAxisId="left" stroke="#888" tick={{ fill: '#888', fontSize: 12 }} axisLine={false} tickLine={false}
                  tickFormatter={(v) => `${Number(v).toLocaleString('vi-VN')}đ`} width={90} />
                <YAxis yAxisId="right" orientation="right" allowDecimals={false} stroke="#888" tick={{ fill: '#888', fontSize: 12 }} axisLine={false} tickLine={false} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#1c1c1e', borderColor: '#333', borderRadius: 8, color: '#fff' }}
                  formatter={(v: any, name: any) => (name === 'Số chuyến' ? v : formatVND(Number(v)))}
                />
                <Legend />
                <Bar yAxisId="left" dataKey="commission" name="Hoa hồng" fill="#00D4AA" radius={[4, 4, 0, 0]} barSize={16} />
                <Bar yAxisId="left" dataKey="platformNet" name="DRIVO thực thu" fill="#6C63FF" radius={[4, 4, 0, 0]} barSize={16} />
                <Line yAxisId="right" type="monotone" dataKey="trips" name="Số chuyến" stroke="#FFA502" strokeWidth={2} dot={{ r: 3 }} />
              </ComposedChart>
            </ResponsiveContainer>
          </div>
        )}

        <h4 style={{ margin: '0 0 12px', color: 'var(--text-secondary)' }}>Theo loại xe</h4>
        <div className="table-responsive">
          <table className="table">
            <thead>
              <tr>
                <th>Loại xe</th>
                <th>Số chuyến</th>
                <th>Tổng cước</th>
                <th>Khách trả</th>
                <th>Trả tài xế</th>
                <th>Hoa hồng</th>
                <th>Khuyến mãi</th>
                <th>DRIVO thực thu</th>
              </tr>
            </thead>
            <tbody>
              {(revenue?.byVehicleType ?? []).length === 0 ? (
                <tr><td colSpan={8} style={{ textAlign: 'center', color: 'var(--text-muted)' }}>Không có chuyến hoàn thành trong khoảng này</td></tr>
              ) : (
                revenue!.byVehicleType.map((v) => (
                  <tr key={v.vehicleType}>
                    <td><strong>{vehicleTypeLabel(v.vehicleType)}</strong></td>
                    <td>{v.totals.trips}</td>
                    <td>{formatVND(v.totals.grossFare)}</td>
                    <td>{formatVND(v.totals.customerPaid)}</td>
                    <td>{formatVND(v.totals.driverPayout)}</td>
                    <td style={{ color: '#00D4AA' }}>{formatVND(v.totals.commission)}</td>
                    <td style={{ color: '#FFA502' }}>{v.totals.voucherCost ? `−${formatVND(v.totals.voucherCost)}` : '—'}</td>
                    <td><strong style={{ color: v.totals.platformNet < 0 ? '#FF4757' : 'var(--text-primary)' }}>{formatVND(v.totals.platformNet)}</strong></td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── Chỉ số hoạt động ── */}
      {loading ? (
        <div style={{ padding: 60, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tổng hợp báo cáo...</div>
      ) : (
        <div>
          <div className="stats-grid" style={{ marginBottom: 24 }}>
            <div className="stat-card">
              <div className="stat-icon" style={{ backgroundColor: '#6C63FF22', color: '#6C63FF' }}>💰</div>
              <div className="stat-label">Tổng cước khách đã trả (toàn thời gian)</div>
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
