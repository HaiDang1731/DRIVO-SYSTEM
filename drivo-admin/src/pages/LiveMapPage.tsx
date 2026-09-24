import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ActiveBooking, TrackingDriver } from '../services/api';
import {
  acquireTracking,
  onBookingStatusChanged,
  onDriverLocation,
  useTrackingStatus,
} from '../services/tracking';
import { DotMarker, FocusOn, MapPopup, MapView, RealtimeIndicator, RouteLine } from '../components/MapKit';
import { Badge } from '../components/Badge';
import {
  BOOKING_STATUS_LABEL,
  DRIVER_STATUS_LABEL,
  HANOI_CENTER,
  LatLng,
  bookingStatusBadge,
  decodePolyline,
  driverStatusColor,
  formatVND,
  isStale,
  timeAgo,
  toLatLng,
} from '../utils/geo';

type Selection = { kind: 'driver'; id: number } | { kind: 'booking'; id: number } | null;

export function LiveMapPage() {
  const navigate = useNavigate();
  const [drivers, setDrivers] = useState<TrackingDriver[]>([]);
  const [bookings, setBookings] = useState<ActiveBooking[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [tab, setTab] = useState<'drivers' | 'bookings'>('drivers');
  const [selected, setSelected] = useState<Selection>(null);
  const [focusKey, setFocusKey] = useState(0);
  const [now, setNow] = useState(Date.now());
  const rtStatus = useTrackingStatus();
  const driverRefetchPending = useRef(false);
  const driversRef = useRef<TrackingDriver[]>([]);
  driversRef.current = drivers;

  const loadDrivers = useCallback(async () => {
    try {
      const res = await api.getTrackingDrivers();
      if (res.success) setDrivers(res.data || []);
      else setError(res.message || 'Không tải được danh sách tài xế');
    } catch {
      setError('Không kết nối được máy chủ API');
    }
  }, []);

  const loadBookings = useCallback(async () => {
    try {
      const res = await api.getActiveBookings();
      if (res.success) setBookings(res.data || []);
      else setError(res.message || 'Không tải được danh sách chuyến');
    } catch {
      setError('Không kết nối được máy chủ API');
    }
  }, []);

  const loadAll = useCallback(async () => {
    setError('');
    await Promise.all([loadDrivers(), loadBookings()]);
    setLoading(false);
  }, [loadDrivers, loadBookings]);

  useEffect(() => { void loadAll(); }, [loadAll]);

  // Realtime subscription
  useEffect(() => {
    const release = acquireTracking();
    const offLoc = onDriverLocation((e) => {
      const known = driversRef.current.some((d) => d.driverId === e.driverId);
      setDrivers((prev) =>
        prev.map((d) =>
          d.driverId !== e.driverId
            ? d
            : {
                ...d,
                latitude: e.latitude,
                longitude: e.longitude,
                driverStatus: e.driverStatus || d.driverStatus,
                lastLocationAt: e.recordedAt || new Date().toISOString(),
              },
        ),
      );
      setBookings((prev) =>
        prev.map((b) => (b.driverId === e.driverId ? { ...b, driverLatitude: e.latitude, driverLongitude: e.longitude } : b)),
      );
      // A driver we don't know yet (first location) → refetch the list once (debounced).
      if (!known && !driverRefetchPending.current) {
        driverRefetchPending.current = true;
        setTimeout(() => {
          driverRefetchPending.current = false;
          void loadDrivers();
        }, 1500);
      }
    });
    const offStatus = onBookingStatusChanged(() => {
      void loadBookings();
      void loadDrivers();
    });
    return () => {
      offLoc();
      offStatus();
      release();
    };
  }, [loadBookings, loadDrivers]);

  // Polling fallback: 15 s when realtime is down, 60 s safety refresh when connected.
  useEffect(() => {
    const ms = rtStatus === 'connected' ? 60000 : 15000;
    const t = setInterval(() => { void loadAll(); }, ms);
    return () => clearInterval(t);
  }, [rtStatus, loadAll]);

  // Tick for "x phút trước" / staleness
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(t);
  }, []);

  const counters = useMemo(() => {
    const fresh = drivers.filter((d) => !isStale(d.lastLocationAt, now));
    return {
      online: fresh.filter((d) => d.driverStatus === 'Online').length,
      busy: drivers.filter((d) => d.driverStatus === 'Busy').length,
      active: bookings.length,
    };
  }, [drivers, bookings, now]);

  const routes = useMemo(
    () => bookings.map((b) => ({ id: b.id, path: decodePolyline(b.routePolyline) })).filter((r) => r.path.length > 1),
    [bookings],
  );

  const selectedDriver = selected?.kind === 'driver' ? drivers.find((d) => d.driverId === selected.id) : undefined;
  const selectedBooking = selected?.kind === 'booking' ? bookings.find((b) => b.id === selected.id) : undefined;
  const selectedPos: LatLng | null = selectedDriver
    ? toLatLng(selectedDriver.latitude, selectedDriver.longitude)
    : selectedBooking
      ? toLatLng(selectedBooking.pickupLatitude, selectedBooking.pickupLongitude)
      : null;

  const select = (s: Selection) => {
    setSelected(s);
    setFocusKey((k) => k + 1);
  };

  const sortedDrivers = useMemo(() => {
    const order: Record<string, number> = { Busy: 0, Online: 1 };
    return [...drivers].sort(
      (a, b) => (order[a.driverStatus] ?? 2) - (order[b.driverStatus] ?? 2) || a.fullName.localeCompare(b.fullName),
    );
  }, [drivers]);

  return (
    <div className="livemap-page">
      <div className="topbar">
        <div className="topbar-title">
          <h2>Bản đồ trực tiếp</h2>
          <p>Vị trí tài xế (xe điện gấp) và các chuyến đang hoạt động theo thời gian thực</p>
        </div>
        <div className="topbar-actions">
          <RealtimeIndicator />
          <button className="btn btn-ghost btn-sm" onClick={() => void loadAll()}>⟳ Làm mới</button>
        </div>
      </div>

      <div className="stats-grid livemap-stats">
        <div className="stat-card" style={{ ['--gradient' as string]: 'linear-gradient(90deg, var(--accent), var(--success))' }}>
          <div className="stat-value">{counters.online}</div>
          <div className="stat-label">🟢 Tài xế online (sẵn sàng)</div>
        </div>
        <div className="stat-card" style={{ ['--gradient' as string]: 'linear-gradient(90deg, var(--warning), #ff7f50)' }}>
          <div className="stat-value">{counters.busy}</div>
          <div className="stat-label">🟠 Tài xế đang chạy chuyến</div>
        </div>
        <div className="stat-card">
          <div className="stat-value">{counters.active}</div>
          <div className="stat-label">📋 Chuyến đang hoạt động</div>
        </div>
      </div>

      {error && <div className="error-msg">{error}</div>}

      <div className="livemap-layout">
        <div className="livemap-map card">
          <div className="livemap-map-canvas">
            <MapView center={HANOI_CENTER} zoom={12} onClick={() => setSelected(null)}>
              <FocusOn target={selectedPos} focusKey={focusKey} />

              {routes.map((r) => (
                <RouteLine
                  key={`route-${r.id}`}
                  path={r.path}
                  color={selected?.kind === 'booking' && selected.id === r.id ? '#00D4AA' : '#6C63FF'}
                  opacity={0.85}
                  weight={selected?.kind === 'booking' && selected.id === r.id ? 6 : 4}
                  onClick={() => select({ kind: 'booking', id: r.id })}
                />
              ))}

              {bookings.map((b) => {
                const pickup = toLatLng(b.pickupLatitude, b.pickupLongitude);
                const dest = toLatLng(b.destinationLatitude, b.destinationLongitude);
                return (
                  <Fragment key={`bk-${b.id}`}>
                    {pickup && (
                      <DotMarker position={pickup} onClick={() => select({ kind: 'booking', id: b.id })} title={`Điểm đón ${b.bookingCode}`}
                        color="#6C63FF" label={`📍 ${b.bookingCode}`} size={14} />
                    )}
                    {dest && (
                      <DotMarker position={dest} onClick={() => select({ kind: 'booking', id: b.id })} title={`Điểm đến ${b.bookingCode}`}
                        color="#FF4757" size={12} />
                    )}
                  </Fragment>
                );
              })}

              {drivers.map((d) => {
                const pos = toLatLng(d.latitude, d.longitude);
                if (!pos) return null;
                const stale = isStale(d.lastLocationAt, now);
                return (
                  <DotMarker
                    key={`drv-${d.driverId}`}
                    position={pos}
                    zIndex={d.driverStatus === 'Busy' ? 30 : d.driverStatus === 'Online' ? 20 : 10}
                    onClick={() => select({ kind: 'driver', id: d.driverId })}
                    title={d.fullName}
                    color={driverStatusColor(d.driverStatus)} label={`🛴 ${d.fullName}`} faded={stale} size={18}
                  />
                );
              })}

              {selectedPos && (selectedDriver || selectedBooking) && (
                <MapPopup position={selectedPos} onClose={() => setSelected(null)}>
                  <div className="map-info">
                    {selectedDriver && (
                      <>
                        <div className="map-info-title">🛴 {selectedDriver.fullName}</div>
                        <div>{selectedDriver.phone}</div>
                        <div>Trạng thái: <b>{DRIVER_STATUS_LABEL[selectedDriver.driverStatus] || selectedDriver.driverStatus}</b></div>
                        <div>Cập nhật: {timeAgo(selectedDriver.lastLocationAt, now)}</div>
                        {selectedDriver.activeBookingCode && (
                          <div>
                            Chuyến: <b>{selectedDriver.activeBookingCode}</b>
                            {selectedDriver.activeBookingStatus ? ` (${BOOKING_STATUS_LABEL[selectedDriver.activeBookingStatus] || selectedDriver.activeBookingStatus})` : ''}
                          </div>
                        )}
                        <div className="map-info-actions">
                          <a onClick={() => navigate(`/drivers/${selectedDriver.driverId}`)}>Hồ sơ tài xế →</a>
                          {selectedDriver.activeBookingId && (
                            <a onClick={() => navigate(`/bookings/${selectedDriver.activeBookingId}`)}>Chi tiết chuyến →</a>
                          )}
                        </div>
                      </>
                    )}
                    {selectedBooking && (
                      <>
                        <div className="map-info-title">📋 {selectedBooking.bookingCode}</div>
                        <div>Trạng thái: <b>{BOOKING_STATUS_LABEL[selectedBooking.status] || selectedBooking.status}</b></div>
                        <div>Khách: {selectedBooking.customerName} · {selectedBooking.customerPhone}</div>
                        <div>Tài xế: {selectedBooking.driverName || 'Chưa có'}</div>
                        <div>🟢 {selectedBooking.pickupAddress}</div>
                        <div>🔴 {selectedBooking.destinationAddress}</div>
                        <div>Giá ước tính: <b>{formatVND(selectedBooking.estimatedPrice)}</b></div>
                        <div className="map-info-actions">
                          <a onClick={() => navigate(`/bookings/${selectedBooking.id}`)}>Chi tiết chuyến →</a>
                        </div>
                      </>
                    )}
                  </div>
                </MapPopup>
              )}
            </MapView>
          </div>
          <div className="map-legend">
            <span><i style={{ background: 'var(--accent)' }} /> Online</span>
            <span><i style={{ background: 'var(--warning)' }} /> Đang chạy</span>
            <span><i style={{ background: '#8888AA' }} /> Khác</span>
            <span><i style={{ background: '#6C63FF' }} /> Điểm đón</span>
            <span><i style={{ background: 'var(--danger)' }} /> Điểm đến</span>
            <span className="map-legend-muted">Mờ = vị trí cũ hơn 10 phút</span>
          </div>
        </div>

        <div className="livemap-panel card">
          <div className="filter-pills livemap-tabs">
            <button className={`filter-pill ${tab === 'drivers' ? 'active' : ''}`} onClick={() => setTab('drivers')}>
              Tài xế ({drivers.length})
            </button>
            <button className={`filter-pill ${tab === 'bookings' ? 'active' : ''}`} onClick={() => setTab('bookings')}>
              Chuyến ({bookings.length})
            </button>
          </div>

          <div className="livemap-list">
            {loading ? (
              <div className="livemap-empty">⏳ Đang tải...</div>
            ) : tab === 'drivers' ? (
              sortedDrivers.length === 0 ? (
                <div className="livemap-empty">Chưa có tài xế nào gửi vị trí.</div>
              ) : (
                sortedDrivers.map((d) => {
                  const stale = isStale(d.lastLocationAt, now);
                  const active = selected?.kind === 'driver' && selected.id === d.driverId;
                  return (
                    <div
                      key={d.driverId}
                      className={`livemap-item ${active ? 'active' : ''} ${stale ? 'stale' : ''}`}
                      onClick={() => select({ kind: 'driver', id: d.driverId })}
                    >
                      <span className="livemap-dot" style={{ background: driverStatusColor(d.driverStatus) }} />
                      <div className="livemap-item-body">
                        <div className="livemap-item-title">{d.fullName}</div>
                        <div className="livemap-item-sub">
                          {DRIVER_STATUS_LABEL[d.driverStatus] || d.driverStatus} · {timeAgo(d.lastLocationAt, now)}
                        </div>
                        {d.activeBookingCode && (
                          <div className="livemap-item-sub">
                            Chuyến <b>{d.activeBookingCode}</b>
                            {d.activeBookingStatus ? ` · ${BOOKING_STATUS_LABEL[d.activeBookingStatus] || d.activeBookingStatus}` : ''}
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })
              )
            ) : bookings.length === 0 ? (
              <div className="livemap-empty">Không có chuyến nào đang hoạt động.</div>
            ) : (
              bookings.map((b) => {
                const active = selected?.kind === 'booking' && selected.id === b.id;
                return (
                  <div
                    key={b.id}
                    className={`livemap-item ${active ? 'active' : ''}`}
                    onClick={() => select({ kind: 'booking', id: b.id })}
                  >
                    <div className="livemap-item-body">
                      <div className="livemap-item-title">
                        {b.bookingCode}{' '}
                        <Badge type={bookingStatusBadge(b.status)}>{BOOKING_STATUS_LABEL[b.status] || b.status}</Badge>
                      </div>
                      <div className="livemap-item-sub">👤 {b.customerName}</div>
                      <div className="livemap-item-sub">🛴 {b.driverName || 'Chưa có tài xế'}</div>
                      <div className="livemap-item-sub livemap-ellipsis" title={b.pickupAddress}>🟢 {b.pickupAddress}</div>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
