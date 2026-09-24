import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { api, AdminBookingDetail, TrailPoint } from '../services/api';
import { acquireTracking, onBookingStatusChanged, onDriverLocation } from '../services/tracking';
import { DotMarker, FitBounds, MapView, RealtimeIndicator, RouteLine } from '../components/MapKit';
import { Badge } from '../components/Badge';
import {
  BOOKING_STATUS_LABEL,
  HANOI_CENTER,
  LatLng,
  bookingStatusBadge,
  decodePolyline,
  formatDateTime,
  formatKm,
  formatVND,
  toLatLng,
} from '../utils/geo';

const ACTIVE_STATUSES = ['Pending', 'SearchingDriver', 'DriverAssigned', 'DriverAccepted', 'DriverArriving', 'DriverArrived', 'InProgress'];

function minutesBetween(a?: string | null, b?: string | null): number | null {
  if (!a || !b) return null;
  const d = (new Date(b).getTime() - new Date(a).getTime()) / 60000;
  return isFinite(d) ? Math.max(0, Math.round(d)) : null;
}

export function BookingDetailPage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [data, setData] = useState<AdminBookingDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [liveDriver, setLiveDriver] = useState<LatLng | null>(null);
  const [liveTrail, setLiveTrail] = useState<TrailPoint[]>([]);

  const load = useCallback(async () => {
    if (!id) return;
    try {
      const res = await api.getBookingDetail(id);
      if (res.success && res.data) {
        setData(res.data);
        setLiveTrail([]);
        setError('');
      } else setError(res.message || 'Không tìm thấy chuyến đi');
    } catch {
      setError('Không kết nối được máy chủ API');
    }
    setLoading(false);
  }, [id]);

  useEffect(() => { setLoading(true); void load(); }, [load]);

  const isActive = !!data && ACTIVE_STATUSES.includes(data.status);

  // Realtime: only while the booking is still active
  useEffect(() => {
    if (!isActive || !id) return;
    const bookingId = Number(id);
    const release = acquireTracking();
    const offStatus = onBookingStatusChanged((e) => {
      if (Number(e.bookingId) === bookingId) void load();
    });
    const offLoc = onDriverLocation((e) => {
      if (Number(e.bookingId) !== bookingId) return;
      setLiveDriver({ lat: e.latitude, lng: e.longitude });
      setLiveTrail((t) => [...t, { latitude: e.latitude, longitude: e.longitude, recordedAt: e.recordedAt }]);
    });
    const poll = setInterval(() => { void load(); }, 15000);
    return () => { offStatus(); offLoc(); release(); clearInterval(poll); };
  }, [isActive, id, load]);

  const pickup = data ? toLatLng(data.pickupLatitude, data.pickupLongitude) : null;
  const dest = data ? toLatLng(data.destinationLatitude, data.destinationLongitude) : null;
  const route = useMemo(() => decodePolyline(data?.routePolyline), [data?.routePolyline]);
  const trail = useMemo(
    () =>
      [...(data?.trail || []), ...(data?.status === 'InProgress' ? liveTrail : [])]
        .map((p) => toLatLng(p.latitude, p.longitude))
        .filter((p): p is LatLng => !!p),
    [data?.trail, data?.status, liveTrail],
  );
  const driverPos = liveDriver || (data ? toLatLng(data.driverLatitude, data.driverLongitude) : null);
  const fitPoints = useMemo(
    () => [pickup, dest, ...route, ...trail].filter((p): p is LatLng => !!p),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [data?.id, route, data?.trail],
  );

  if (loading) return <div className="card" style={{ textAlign: 'center', color: 'var(--text-muted)' }}>⏳ Đang tải chi tiết chuyến...</div>;
  if (!data) {
    return (
      <div>
        <button className="btn btn-ghost btn-sm" onClick={() => navigate('/bookings')}>← Quay lại</button>
        <div className="error-msg" style={{ marginTop: 16 }}>{error || 'Không tìm thấy chuyến đi'}</div>
      </div>
    );
  }

  const waitingMin = minutesBetween(data.arrivedAt, data.startedAt);
  const tripMin = minutesBetween(data.startedAt, data.completedAt);
  const est = data.estimatedDistanceKm ?? null;
  const act = data.actualDistanceKm ?? null;
  const tol = Number(data.pricingRule?.overDistanceTolerancePercent ?? data['overDistanceTolerancePercent'] ?? NaN);
  const overPct = est && act ? ((act - est) / est) * 100 : null;

  const timeline: { label: string; at?: string | null; icon: string }[] = [
    { label: 'Tạo chuyến', at: data.createdAt, icon: '📝' },
    { label: 'Tài xế nhận chuyến', at: data.acceptedAt, icon: '✅' },
    { label: 'Tài xế đến điểm đón (xe điện)', at: data.arrivedAt, icon: '🛴' },
    { label: 'Bắt đầu chuyến (lái xe khách)', at: data.startedAt, icon: '🚗' },
    { label: 'Hoàn thành', at: data.completedAt, icon: '🏁' },
  ];
  if (data.status === 'Cancelled') timeline.push({ label: 'Đã hủy', at: data.cancelledAt ?? null, icon: '❌' });

  const fees: { label: string; value?: number | null; note?: string; negative?: boolean; strong?: boolean }[] = [
    { label: 'Cước mở cửa (BaseFare)', value: data.baseFare },
    { label: 'Cước quãng đường (DistanceFare)', value: data.distanceFare },
    ...(data.timeFare != null ? [{ label: 'Cước thời gian (TimeFare)', value: data.timeFare }] : []),
    { label: 'Phụ phí (Surcharge — đêm)', value: data.surcharge },
    { label: 'Giá ước tính (EstimatedPrice)', value: data.estimatedPrice, strong: true },
    { label: 'Phí đón bằng xe điện (PickupFee)', value: data.pickupFee, note: data.pickupDistanceKm != null ? `chặng đón ${formatKm(data.pickupDistanceKm)}` : undefined },
    { label: 'Phí chờ (WaitingFee)', value: data.waitingFee, note: waitingMin != null ? `chờ ${waitingMin} phút` : undefined },
    { label: 'Phí vượt quãng đường (ExtraDistanceFee)', value: data.extraDistanceFee },
    { label: 'Giảm giá (Discount)', value: data.discount, negative: true },
    { label: 'Giá cuối cùng (FinalPrice)', value: data.finalPrice, strong: true },
    ...(data.finalPrice != null ? [
      {
        label: 'DRIVO thực thu (CommissionAmount)',
        value: data.commissionAmount,
        note: data.discount ? `hoa hồng ${formatVND((data.commissionAmount ?? 0) + data.discount)} − bù khuyến mãi ${formatVND(data.discount)}` : undefined,
      },
      { label: 'Tài xế thực nhận (DriverPayout)', value: data.driverPayout, strong: true },
    ] : []),
  ];

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>
            Chuyến {data.bookingCode}{' '}
            <Badge type={bookingStatusBadge(data.status)}>{BOOKING_STATUS_LABEL[data.status] || data.status}</Badge>
          </h2>
          <p>Tạo lúc {formatDateTime(data.createdAt)}</p>
        </div>
        <div className="topbar-actions">
          {isActive && <RealtimeIndicator />}
          <button className="btn btn-ghost btn-sm" onClick={() => void load()}>⟳ Làm mới</button>
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/bookings')}>← Danh sách chuyến</button>
        </div>
      </div>

      {error && <div className="error-msg">{error}</div>}

      <div className="detail-grid">
        <div className="card detail-map-card">
          <div className="detail-map">
            <MapView center={pickup || HANOI_CENTER} zoom={13}>
              <FitBounds points={fitPoints} fitKey={`${data.id}-${route.length}-${data.trail?.length ?? 0}`} />
              {route.length > 1 && <RouteLine path={route} color="#6C63FF" opacity={0.9} weight={5} />}
              {trail.length > 1 && <RouteLine path={trail} color="#00D4AA" opacity={0.95} weight={3} />}
              {pickup && <DotMarker position={pickup} title="Điểm đón" color="#2ED573" label="Điểm đón" />}
              {dest && <DotMarker position={dest} title="Điểm đến" color="#FF4757" label="Điểm đến" />}
              {driverPos && isActive && (
                <DotMarker position={driverPos} title="Tài xế" zIndex={50} color="#FFA502" label={`🛴 ${data.driver?.fullName || 'Tài xế'}`} />
              )}
            </MapView>
          </div>
          <div className="map-legend">
            <span><i style={{ background: '#6C63FF' }} /> Lộ trình dự kiến</span>
            <span><i style={{ background: 'var(--accent)' }} /> Lộ trình GPS thực tế ({data.trail?.length ?? 0} điểm)</span>
            <span><i style={{ background: 'var(--success)' }} /> Điểm đón</span>
            <span><i style={{ background: 'var(--danger)' }} /> Điểm đến</span>
          </div>
        </div>

        <div className="detail-side">
          <div className="card">
            <h3 className="section-title">Thông tin</h3>
            <div className="kv-list">
              <div><span>Khách hàng</span><b>{data.customer?.fullName || '—'} {data.customer?.phone ? `· ${data.customer.phone}` : ''}</b></div>
              <div><span>Tài xế</span><b>{data.driver?.fullName || 'Chưa có'} {data.driver?.phone ? `· ${data.driver.phone}` : ''}</b></div>
              {data.vehicle && (
                <div><span>Xe của khách</span><b>{[data.vehicle.brand, data.vehicle.model].filter(Boolean).join(' ')} {data.vehicle.licensePlate ? `· ${data.vehicle.licensePlate}` : ''}</b></div>
              )}
              <div><span>🟢 Điểm đón</span><b>{data.pickupAddress}</b></div>
              <div><span>🔴 Điểm đến</span><b>{data.destinationAddress}</b></div>
              {data.customerNote && <div><span>Ghi chú</span><b>{data.customerNote}</b></div>}
            </div>
          </div>

          <div className="card">
            <h3 className="section-title">Mốc thời gian</h3>
            <div className="timeline">
              {timeline.map((t) => (
                <div key={t.label} className={`timeline-item ${t.at ? 'done' : ''}`}>
                  <span className="timeline-icon">{t.icon}</span>
                  <div>
                    <div className="timeline-label">{t.label}</div>
                    <div className="timeline-time">{t.at ? formatDateTime(t.at) : 'Chưa diễn ra'}</div>
                  </div>
                </div>
              ))}
            </div>
            {(waitingMin != null || tripMin != null) && (
              <div className="timeline-summary">
                {waitingMin != null && <span>⏱️ Thời gian chờ: <b>{waitingMin} phút</b></span>}
                {tripMin != null && <span>🚗 Thời gian chạy: <b>{tripMin} phút</b></span>}
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="detail-grid detail-grid-even">
        <div className="card">
          <h3 className="section-title">So sánh quãng đường</h3>
          <div className="distance-compare">
            <div className="distance-box">
              <div className="distance-label">🛴 Chặng đón (xe điện)</div>
              <div className="distance-value">{formatKm(data.pickupDistanceKm)}</div>
              <div className="distance-hint">Tài xế → điểm đón, lúc nhận chuyến</div>
            </div>
            <div className="distance-box">
              <div className="distance-label">🗺️ Dự kiến (chặng chính)</div>
              <div className="distance-value">{formatKm(est)}</div>
              <div className="distance-hint">{data.estimatedDurationMin ? `~${data.estimatedDurationMin} phút` : 'Theo OSRM'}</div>
            </div>
            <div className="distance-box">
              <div className="distance-label">📡 Thực tế (GPS)</div>
              <div className="distance-value" style={{ color: overPct != null && !isNaN(tol) && overPct > tol ? 'var(--warning)' : undefined }}>
                {formatKm(act)}
              </div>
              <div className="distance-hint">
                {overPct != null ? `${overPct >= 0 ? '+' : ''}${overPct.toFixed(1)}% so với dự kiến` : 'Chưa có dữ liệu'}
                {!isNaN(tol) ? ` · ngưỡng ${tol}%` : ''}
              </div>
            </div>
          </div>
        </div>

        <div className="card" style={{ padding: 0 }}>
          <h3 className="section-title" style={{ padding: '20px 20px 0' }}>Chi tiết cước phí</h3>
          <div className="table-responsive">
            <table className="table fee-table">
              <tbody>
                {fees.map((f) => (
                  <tr key={f.label} className={f.strong ? 'fee-strong' : ''}>
                    <td>
                      {f.label}
                      {f.note && <div className="fee-note">{f.note}</div>}
                    </td>
                    <td className="fee-value">
                      {f.value == null ? '—' : `${f.negative && Number(f.value) > 0 ? '−' : ''}${formatVND(f.value)}`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {data.offers && data.offers.length > 0 && (
        <div className="card" style={{ marginTop: 20, padding: 0 }}>
          <h3 className="section-title" style={{ padding: '20px 20px 0' }}>Lịch sử gửi cuốc cho tài xế</h3>
          <p style={{ padding: '0 20px', margin: '6px 0 0', fontSize: 12, color: 'var(--text-muted)' }}>
            Cuốc được gửi lần lượt cho tài xế điểm cao nhất (gần + sao + tỉ lệ hoàn thành), mỗi người 3 phút.
            Sau 3 lượt chưa ai nhận thì mở cho mọi tài xế gần đó. Khách bấm "Làm mới" thì tìm lại từ lượt 1.
          </p>
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr><th>Lượt</th><th>Tài xế</th><th>Cách điểm đón</th><th>Kết quả</th><th>Gửi lúc</th><th>Phản hồi lúc</th></tr>
              </thead>
              <tbody>
                {data.offers.map((o, i) => {
                  const result: Record<string, { label: string; type: 'success' | 'danger' | 'warning' | 'info' }> = {
                    Sent: { label: 'Đang chờ', type: 'info' },
                    Accepted: { label: 'Đã nhận', type: 'success' },
                    Rejected: { label: 'Bỏ qua', type: 'danger' },
                    Expired: { label: 'Hết giờ', type: 'warning' },
                    Cancelled: { label: 'Đã hủy lượt', type: 'warning' },
                  };
                  const r = result[o.status] ?? { label: o.status, type: 'info' as const };
                  return (
                    <tr key={i}>
                      <td>
                        {(o.round % 10 <= 3 ? `#${o.round % 10}` : 'Mở chung') + (o.round > 10 ? ' (lần tìm trước)' : '')}
                      </td>
                      <td><Link to={`/drivers/${o.driverId}`}>{o.driverName}</Link></td>
                      <td>{o.distanceToPickupKm != null ? formatKm(o.distanceToPickupKm) : '—'}</td>
                      <td><Badge type={r.type}>{r.label}</Badge></td>
                      <td>{formatDateTime(o.sentAt)}</td>
                      <td>{o.respondedAt ? formatDateTime(o.respondedAt) : '—'}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {data.statusHistory && data.statusHistory.length > 0 && (
        <div className="card" style={{ marginTop: 20, padding: 0 }}>
          <h3 className="section-title" style={{ padding: '20px 20px 0' }}>Lịch sử trạng thái</h3>
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr><th>Trạng thái</th><th>Thời điểm</th><th>Ghi chú</th></tr>
              </thead>
              <tbody>
                {data.statusHistory.map((h, i) => (
                  <tr key={i}>
                    <td><Badge type={bookingStatusBadge(h.status)}>{BOOKING_STATUS_LABEL[h.status] || h.status}</Badge></td>
                    <td>{formatDateTime(h.changedAt)}</td>
                    <td>{h.note || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
