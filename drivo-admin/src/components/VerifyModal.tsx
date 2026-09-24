import { useState } from 'react';
import { api } from '../services/api';
import { Avatar } from './Avatar';
import { Badge } from './Badge';

export function VerifyModal({ driver, onClose, onDone }: { driver: any; onClose: () => void; onDone: () => void }) {
  const [reason, setReason] = useState('');
  const [loading, setLoading] = useState(false);

  const verify = async (status: string) => {
    setLoading(true);
    await api.verifyDriver(driver.driverId, status, reason);
    setLoading(false);
    onDone(); onClose();
  };

  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <div className="modal-header">
          <div className="modal-title">🛡️ Duyệt Hồ Sơ Tài Xế</div>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>
        <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: 10, padding: 16, marginBottom: 20 }}>
          <div className="user-cell" style={{ marginBottom: 12 }}>
            <Avatar name={driver.fullName} src={driver.avatarUrl} />
            <div>
              <div className="name">{driver.fullName}</div>
              <div className="phone">{driver.phone} • {driver.licenseNumber}</div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <Badge value={driver.verificationStatus} />
            <Badge value={driver.driverStatus} />
          </div>
          {driver.documents && driver.documents.length > 0 && (
            <div style={{ marginTop: 12 }}>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 6 }}>GIẤY TỜ</div>
              {driver.documents.map((d: any) => (
                <div key={d.id} style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 3 }}>
                  📄 {d.documentType} - <Badge value={d.verificationStatus} />
                </div>
              ))}
            </div>
          )}
        </div>
        <div className="form-group">
          <label className="form-label">Lý do từ chối (bắt buộc khi từ chối)</label>
          <textarea className="form-input" rows={3} value={reason} onChange={e => setReason(e.target.value)}
            placeholder="Nhập lý do từ chối hồ sơ..." style={{ resize: 'vertical' }} />
        </div>
        <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button className="btn btn-ghost" onClick={onClose}>Hủy</button>
          <button className="btn btn-danger" disabled={loading} onClick={() => verify('Rejected')}>
            ❌ Từ chối
          </button>
          <button className="btn btn-success" disabled={loading} onClick={() => verify('Approved')}>
            ✅ Duyệt
          </button>
        </div>
      </div>
    </div>
  );
}
