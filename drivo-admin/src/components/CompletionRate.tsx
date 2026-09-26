import type { DriverCompletion } from '../services/api';

/** Màu theo mức: ≥90% tốt, ≥75% cần chú ý, thấp hơn là kém. */
export function completionColor(rate?: number | null) {
  if (rate == null) return 'var(--text-muted)';
  if (rate >= 90) return '#2ED573';
  if (rate >= 75) return '#FFA502';
  return '#FF4757';
}

/** Ô tỉ lệ hoàn thành gọn cho bảng danh sách tài xế. */
export function CompletionRateCell({ c }: { c?: DriverCompletion | null }) {
  if (!c) return <span style={{ color: 'var(--text-muted)' }}>-</span>;
  const tip =
    `${c.windowDays} ngày: ${c.completed} hoàn thành · ${c.driverFaultCancelled} hủy do tài xế` +
    ` · ${c.noFaultCancelled} hủy không tính lỗi`;
  return (
    <div title={tip}>
      {c.rate == null ? (
        <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>Chưa đủ dữ liệu</span>
      ) : (
        <b style={{ color: completionColor(c.rate), fontSize: 14 }}>{c.rate}%</b>
      )}
      <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>
        {c.completed} xong · {c.driverFaultCancelled} hủy lỗi
      </div>
    </div>
  );
}
