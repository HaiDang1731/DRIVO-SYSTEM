import { CSSProperties, ReactNode, useEffect, useMemo } from 'react';
import L from 'leaflet';
import { MapContainer, Marker, Polyline, Popup, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { LatLng } from '../utils/geo';
import { useTrackingStatus } from '../services/tracking';

// Mirror OpenStreetMap Đức (miễn phí, không cần key). tile.openstreetmap.org bị chặn ở một số mạng VN,
// CARTO basemaps giờ trả tile có watermark "API KEY REQUIRED".
const OSM_TILES = 'https://tile.openstreetmap.de/{z}/{x}/{y}.png';
const OSM_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a> contributors';

function MapClick({ onClick }: { onClick?: () => void }) {
  useMapEvents({ click: () => onClick?.() });
  return null;
}

/** Leaflet map with free OpenStreetMap tiles. Parent must give it a height (defaults to 100%). */
export function MapView({
  center,
  zoom = 13,
  children,
  style,
  scrollWheelZoom = true,
  onClick,
}: {
  center: LatLng;
  zoom?: number;
  children?: ReactNode;
  style?: CSSProperties;
  scrollWheelZoom?: boolean;
  onClick?: () => void;
}) {
  return (
    <MapContainer
      center={center}
      zoom={zoom}
      scrollWheelZoom={scrollWheelZoom}
      style={{ width: '100%', height: '100%', minHeight: 200, ...style }}
      className="drivo-map"
    >
      <TileLayer url={OSM_TILES} attribution={OSM_ATTRIBUTION} maxZoom={19} />
      <MapClick onClick={onClick} />
      {children}
    </MapContainer>
  );
}

/** Fits the map viewport to the given points once they change (by key). */
export function FitBounds({ points, fitKey }: { points: LatLng[]; fitKey: string }) {
  const map = useMap();
  useEffect(() => {
    if (points.length === 0) return;
    if (points.length === 1) {
      map.setView(points[0], 15);
      return;
    }
    map.fitBounds(L.latLngBounds(points.map((p) => [p.lat, p.lng] as [number, number])), { padding: [60, 60] });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, fitKey]);
  return null;
}

/** Pans/zooms the map to a target whenever focusKey changes. */
export function FocusOn({ target, focusKey }: { target: LatLng | null; focusKey: number }) {
  const map = useMap();
  useEffect(() => {
    if (!target) return;
    map.setView(target, Math.max(map.getZoom(), 15));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, focusKey]);
  return null;
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

/** Colored circular dot marker (L.divIcon — no default image assets needed), optional label above. */
export function DotMarker({
  position,
  color,
  label,
  faded,
  size = 16,
  title,
  zIndex,
  onClick,
}: {
  position: LatLng;
  color: string;
  label?: string;
  faded?: boolean;
  size?: number;
  title?: string;
  zIndex?: number;
  onClick?: () => void;
}) {
  const icon = useMemo(
    () =>
      L.divIcon({
        className: 'map-dot-icon',
        html:
          `<div class="map-dot ${faded ? 'map-dot-faded' : ''}" style="transform:translate(-50%, calc(-100% + ${size / 2 + 3}px))">` +
          (label ? `<span class="map-dot-label">${esc(label)}</span>` : '') +
          `<span class="map-dot-core" style="background:${color};width:${size}px;height:${size}px"></span></div>`,
        iconSize: [0, 0],
        iconAnchor: [0, 0],
      }),
    [color, label, faded, size],
  );
  return (
    <Marker
      position={position}
      icon={icon}
      title={title}
      zIndexOffset={(zIndex ?? 0) * 100}
      eventHandlers={onClick ? { click: (e) => { L.DomEvent.stopPropagation(e); onClick(); } } : undefined}
    />
  );
}

/** Route line. Planned route = purple (#6C63FF), GPS trail = teal (#00D4AA). */
export function RouteLine({
  path,
  color,
  opacity = 0.9,
  weight = 4,
  onClick,
}: {
  path: LatLng[];
  color: string;
  opacity?: number;
  weight?: number;
  onClick?: () => void;
}) {
  return (
    <Polyline
      positions={path}
      pathOptions={{ color, opacity, weight }}
      eventHandlers={onClick ? { click: (e) => { L.DomEvent.stopPropagation(e); onClick(); } } : undefined}
    />
  );
}

/** Info popup anchored at a position; calls onClose when dismissed. */
export function MapPopup({ position, onClose, children }: { position: LatLng; onClose?: () => void; children: ReactNode }) {
  return (
    // Visibility is controlled by React state: Leaflet's own close/auto-close is disabled.
    <Popup position={position} offset={[0, -14]} closeButton={false} autoClose={false} closeOnClick={false} closeOnEscapeKey={false}>
      {onClose && (
        <button type="button" className="map-popup-close" onClick={onClose} aria-label="Đóng">×</button>
      )}
      {children}
    </Popup>
  );
}

/** Small "Mất kết nối realtime" indicator; shows live state otherwise. */
export function RealtimeIndicator() {
  const s = useTrackingStatus();
  if (s === 'connected') return <span className="rt-indicator rt-live">● Realtime</span>;
  if (s === 'connecting' || s === 'reconnecting')
    return <span className="rt-indicator rt-pending">● Đang kết nối realtime…</span>;
  return (
    <span className="rt-indicator rt-offline" title="Không kết nối được hub realtime — tự động làm mới mỗi 15 giây">
      ● Mất kết nối realtime
    </span>
  );
}
