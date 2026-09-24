// Map / formatting helpers shared by the tracking & booking pages.

export const HANOI_CENTER = { lat: 21.0285, lng: 105.8542 };
export const STALE_LOCATION_MS = 10 * 60 * 1000;

export type LatLng = { lat: number; lng: number };

/** Decode an encoded polyline (precision 5, as returned by OSRM). */
export function decodePolyline(encoded?: string | null): LatLng[] {
  if (!encoded) return [];
  const points: LatLng[] = [];
  let index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    let result = 0, shift = 0, b: number;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lat += result & 1 ? ~(result >> 1) : result >> 1;
    result = 0; shift = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lng += result & 1 ? ~(result >> 1) : result >> 1;
    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return points;
}

export function toLatLng(lat?: number | null, lng?: number | null): LatLng | null {
  if (lat == null || lng == null) return null;
  const a = Number(lat), b = Number(lng);
  if (!isFinite(a) || !isFinite(b) || (a === 0 && b === 0)) return null;
  return { lat: a, lng: b };
}

export function formatVND(val?: number | null): string {
  return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(Number(val) || 0);
}

export function formatDateTime(d?: string | null): string {
  if (!d) return '—';
  const date = new Date(d);
  return isNaN(date.getTime()) ? String(d) : date.toLocaleString('vi-VN');
}

export function formatKm(km?: number | null): string {
  return km == null ? '—' : `${Number(km).toLocaleString('vi-VN', { maximumFractionDigits: 2 })} km`;
}

export function timeAgo(d?: string | null, now = Date.now()): string {
  if (!d) return 'chưa có';
  const t = new Date(d).getTime();
  if (isNaN(t)) return '—';
  const sec = Math.max(0, Math.round((now - t) / 1000));
  if (sec < 60) return 'vừa xong';
  const min = Math.round(sec / 60);
  if (min < 60) return `${min} phút trước`;
  const h = Math.round(min / 60);
  if (h < 24) return `${h} giờ trước`;
  return `${Math.round(h / 24)} ngày trước`;
}

export function isStale(d?: string | null, now = Date.now()): boolean {
  if (!d) return true;
  const t = new Date(d).getTime();
  return isNaN(t) || now - t > STALE_LOCATION_MS;
}

export const BOOKING_STATUS_LABEL: Record<string, string> = {
  Pending: 'Chờ xử lý',
  SearchingDriver: 'Đang tìm tài xế',
  DriverAssigned: 'Đã gán tài xế',
  DriverAccepted: 'Tài xế đã nhận',
  DriverArriving: 'Tài xế đang đến',
  DriverArrived: 'Tài xế đã đến',
  InProgress: 'Đang chạy',
  Completed: 'Hoàn thành',
  Cancelled: 'Đã hủy',
};

export function bookingStatusBadge(status?: string): 'success' | 'danger' | 'warning' | 'info' {
  if (status === 'Completed') return 'success';
  if (status === 'Cancelled') return 'danger';
  if (status === 'InProgress') return 'info';
  return 'warning';
}

export const DRIVER_STATUS_LABEL: Record<string, string> = {
  Online: 'Sẵn sàng',
  Busy: 'Đang chạy chuyến',
  Offline: 'Ngoại tuyến',
  Suspended: 'Tạm khóa',
};

export function driverStatusColor(status?: string): string {
  if (status === 'Online') return 'var(--accent)';
  if (status === 'Busy') return 'var(--warning)';
  return '#8888AA';
}

const VEHICLE_LABELS = ['Xe máy', 'Ô tô (4-5 chỗ)', 'SUV / 7 chỗ', 'Xe tải', 'Khác'];
const VEHICLE_KEYS = ['Motorbike', 'Car', 'Suv', 'Truck', 'Other'];
export function vehicleTypeLabel(v: string | number | undefined | null): string {
  if (v == null) return '—';
  if (typeof v === 'number') return VEHICLE_LABELS[v] ?? String(v);
  const i = VEHICLE_KEYS.findIndex((k) => k.toLowerCase() === v.toLowerCase());
  return i >= 0 ? VEHICLE_LABELS[i] : v;
}

export const round1000 = (v: number) => Math.round(v / 1000) * 1000;
