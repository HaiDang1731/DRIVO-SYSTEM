import { useState, useEffect } from 'react';
import { api } from '../services/api';

export function SettingsPage() {
  const [settings, setSettings] = useState<any>(null);

  useEffect(() => {
    api.getSettings().then((res: any) => {
      if (res.success) setSettings(res.data);
    });
  }, []);

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Cấu Hình & Tham số Hệ thống</h2>
          <p>Xem thông tin hệ thống, chính sách chiết khấu, hoa hồng và tham số vận hành</p>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24 }}>
        <div className="card">
          <h3 style={{ marginBottom: 16, color: 'var(--text-primary)' }}>Thông tin Chung</h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div className="input-group">
              <label>Tên hệ thống</label>
              <input type="text" className="input" readOnly value={settings?.systemName || 'DRIVO System'} />
            </div>
            <div className="input-group">
              <label>Phiên bản ứng dụng</label>
              <input type="text" className="input" readOnly value={settings?.version || '1.2.0'} />
            </div>
            <div className="input-group">
              <label>Hotline hỗ trợ</label>
              <input type="text" className="input" readOnly value={settings?.hotline || '1900 8888'} />
            </div>
            <div className="input-group">
              <label>Email hỗ trợ</label>
              <input type="text" className="input" readOnly value={settings?.supportEmail || 'support@drivo.vn'} />
            </div>
          </div>
        </div>

        <div className="card">
          <h3 style={{ marginBottom: 16, color: 'var(--text-primary)' }}>Tham số Vận hành & Tài chính</h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div className="input-group">
              <label>Tỷ lệ hoa hồng tài xế (%)</label>
              <input type="text" className="input" readOnly value={`${settings?.driverCommissionRate || 15}%`} />
            </div>
            <div className="input-group">
              <label>Bán kính quét tìm tài xế (km)</label>
              <input type="text" className="input" readOnly value={`${settings?.maxSearchRadiusKm || 10} km`} />
            </div>
            <div className="input-group">
              <label>Thời gian chờ tài xế nhận cuốc (giây)</label>
              <input type="text" className="input" readOnly value={`${settings?.autoMatchTimeoutSeconds || 30} giây`} />
            </div>
            <div className="input-group">
              <label>Thuế VAT (%)</label>
              <input type="text" className="input" readOnly value={`${settings?.vatPercent || 8}%`} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
