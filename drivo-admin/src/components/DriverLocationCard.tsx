import { useEffect, useState } from 'react';
import { api, TrackingDriver } from '../services/api';
import { DotMarker, MapView } from './MapKit';
import { DRIVER_STATUS_LABEL, driverStatusColor, formatDateTime, isStale, timeAgo, toLatLng } from '../utils/geo';

/** Small map with the driver's last known location (from /admin/tracking/drivers). */
export function DriverLocationCard({ driverId }: { driverId: number }) {
  const [loc, setLoc] = useState<TrackingDriver | null>(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const res = await api.getTrackingDrivers();
        if (alive && res.success) setLoc((res.data || []).find((d) => Number(d.driverId) === Number(driverId)) ?? null);
      } catch {
        // API down → keep showing the empty state
      }
      if (alive) setLoaded(true);
    };
    void load();
    const t = setInterval(load, 30000);
    return () => { alive = false; clearInterval(t); };
  }, [driverId]);

  const pos = loc ? toLatLng(loc.latitude, loc.longitude) : null;

  return (
    <div className="driver-location">
      <div className="driver-location-meta">
        {!loaded ? (
          <span>Đang tải vị trí...</span>
        ) : pos && loc ? (
          <>
            <span className="livemap-dot" style={{ background: driverStatusColor(loc.driverStatus) }} />
            <span>{DRIVER_STATUS_LABEL[loc.driverStatus] || loc.driverStatus}</span>
            <span>· Cập nhật {timeAgo(loc.lastLocationAt)} ({formatDateTime(loc.lastLocationAt)})</span>
            {isStale(loc.lastLocationAt) && <span className="text-warning">· vị trí đã cũ</span>}
            {loc.activeBookingCode && <span>· Chuyến {loc.activeBookingCode}</span>}
          </>
        ) : (
          <span>Tài xế chưa gửi vị trí nào.</span>
        )}
      </div>
      {pos && loc && (
        <div className="driver-location-map">
          <MapView center={pos} zoom={15} scrollWheelZoom={false}>
            <DotMarker position={pos} title={loc.fullName} color={driverStatusColor(loc.driverStatus)} label={`🛴 ${loc.fullName}`} faded={isStale(loc.lastLocationAt)} />
          </MapView>
        </div>
      )}
    </div>
  );
}
