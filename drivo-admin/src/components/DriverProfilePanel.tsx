import { useState } from 'react';
import { api, apiFileUrl, DriverProfileFields } from '../services/api';
import { Badge } from './Badge';
import { VerifyModal } from './VerifyModal';

type Msg = (text: string, type: 'success' | 'error') => void;

type FieldKind = 'text' | 'date' | 'number' | 'gender';
interface FieldDef {
  key: keyof DriverProfileFields;
  label: string;
  kind?: FieldKind;
  /** Hiển thị (chế độ xem) */
  render?: (v: any) => React.ReactNode;
  mono?: boolean;
}

const GENDER: Record<string, string> = { MALE: 'Nam', FEMALE: 'Nữ', OTHER: 'Khác' };

const DOC_TYPES: { type: string; label: string }[] = [
  { type: 'DRIVER_LICENSE_FRONT', label: 'GPLX mặt trước' },
  { type: 'DRIVER_LICENSE_BACK', label: 'GPLX mặt sau' },
  { type: 'CCCD_FRONT', label: 'CCCD mặt trước' },
  { type: 'CCCD_BACK', label: 'CCCD mặt sau' },
  { type: 'PROFILE_PHOTO', label: 'Ảnh chân dung' },
];

function fmtDate(iso?: string | null): string {
  if (!iso) return '—';
  const [y, m, d] = iso.slice(0, 10).split('-');
  return d && m && y ? `${d}/${m}/${y}` : iso;
}

/** API trả DateTime UTC không kèm 'Z' */
function fmtDateTime(s?: string | null): string {
  if (!s) return '—';
  const d = new Date(/(Z|[+-]\d\d:?\d\d)$/.test(s) ? s : `${s}Z`);
  return d.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit', year: 'numeric' });
}

function ageOf(iso?: string | null): number | null {
  if (!iso) return null;
  const b = new Date(`${iso.slice(0, 10)}T00:00:00`);
  const now = new Date();
  let age = now.getFullYear() - b.getFullYear();
  if (now < new Date(now.getFullYear(), b.getMonth(), b.getDate())) age--;
  return age;
}

function ExpiryValue({ iso }: { iso?: string | null }) {
  if (!iso) return <>—</>;
  const days = Math.ceil((new Date(`${iso.slice(0, 10)}T00:00:00`).getTime() - Date.now()) / 86400000);
  if (days < 0) return <span style={{ color: '#FF4757' }}>{fmtDate(iso)} · Đã hết hạn</span>;
  if (days <= 30) return <span style={{ color: '#FFA502' }}>{fmtDate(iso)} · Còn {days} ngày</span>;
  return <>{fmtDate(iso)}</>;
}

const SECTIONS: { title: string; icon: string; note?: string; fields: FieldDef[] }[] = [
  {
    title: 'Cá nhân & CCCD',
    icon: '👤',
    fields: [
      { key: 'fullName', label: 'Họ và tên' },
      { key: 'email', label: 'Email' },
      {
        key: 'dateOfBirth', label: 'Ngày sinh', kind: 'date',
        render: (v) => (v ? `${fmtDate(v)} (${ageOf(v)} tuổi)` : '—'),
      },
      { key: 'gender', label: 'Giới tính', kind: 'gender', render: (v) => GENDER[v] ?? '—' },
      { key: 'idCardNumber', label: 'Số CCCD', mono: true },
      { key: 'address', label: 'Địa chỉ thường trú' },
    ],
  },
  {
    title: 'Giấy phép lái xe',
    icon: '🪪',
    fields: [
      { key: 'licenseNumber', label: 'Số GPLX', mono: true },
      { key: 'licenseClass', label: 'Hạng bằng' },
      { key: 'licenseExpiryDate', label: 'Ngày hết hạn', kind: 'date', render: (v) => <ExpiryValue iso={v} /> },
      { key: 'drivingExperienceYears', label: 'Kinh nghiệm lái', kind: 'number', render: (v) => (v == null ? '—' : `${v} năm`) },
    ],
  },
  {
    title: 'Liên hệ khẩn cấp',
    icon: '🆘',
    fields: [
      { key: 'emergencyContactName', label: 'Người liên hệ' },
      { key: 'emergencyContactRelation', label: 'Quan hệ' },
      { key: 'emergencyContactPhone', label: 'Số điện thoại', mono: true },
    ],
  },
  {
    title: 'Tài khoản nhận tiền',
    icon: '🏦',
    fields: [
      { key: 'bankName', label: 'Ngân hàng' },
      { key: 'bankAccountNumber', label: 'Số tài khoản', mono: true },
      { key: 'bankAccountHolder', label: 'Chủ tài khoản' },
    ],
  },
];

export function DriverProfilePanel({ data, onReload, onMessage }: { data: any; onReload: () => void; onMessage: Msg }) {
  const profile: DriverProfileFields = data.profile ?? {};
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<DriverProfileFields>({});
  const [saving, setSaving] = useState(false);
  const [rejecting, setRejecting] = useState<{ id: number; reason: string } | null>(null);
  const [busyDoc, setBusyDoc] = useState<number | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [showVerify, setShowVerify] = useState(false);

  const docs: any[] = data.documents ?? [];
  const docOf = (type: string) => docs.find((d) => d.documentType === type);

  const missing = [
    ...SECTIONS.flatMap((s) => s.fields)
      .filter((f) => !['email', 'address', 'drivingExperienceYears', 'emergencyContactRelation', 'gender'].includes(f.key))
      .filter((f) => profile[f.key] == null || profile[f.key] === '')
      .map((f) => f.label),
    ...DOC_TYPES.filter((d) => !docOf(d.type)).map((d) => `Ảnh ${d.label}`),
  ];

  const startEdit = () => {
    setForm({ ...profile });
    setEditing(true);
  };

  const save = async () => {
    // Chỉ gửi trường đã đổi; chuỗi rỗng = xóa giá trị
    const changed: Partial<DriverProfileFields> = {};
    (Object.keys(form) as (keyof DriverProfileFields)[]).forEach((k) => {
      const now = form[k] ?? '';
      const before = profile[k] ?? '';
      if (String(now) !== String(before)) (changed as any)[k] = now === '' && k === 'drivingExperienceYears' ? null : now;
    });
    if (Object.keys(changed).length === 0) {
      setEditing(false);
      return;
    }
    setSaving(true);
    const res = await api.updateDriverProfile(data.driverId, changed);
    setSaving(false);
    if (res.success) {
      onMessage(res.message || 'Đã cập nhật hồ sơ', 'success');
      setEditing(false);
      onReload();
    } else {
      onMessage(res.message || 'Lưu thất bại', 'error');
    }
  };

  const review = async (docId: number, status: 'APPROVED' | 'REJECTED', reason?: string) => {
    setBusyDoc(docId);
    const res = await api.reviewDriverDocument(data.driverId, docId, status, reason);
    setBusyDoc(null);
    if (res.success) {
      setRejecting(null);
      onMessage(res.message || 'Đã cập nhật giấy tờ', 'success');
      onReload();
    } else {
      onMessage(res.message || 'Thao tác thất bại', 'error');
    }
  };

  const completeReview = async () => {
    const pendingDocs = docs.filter((d) => d.verificationStatus === 'Pending').length;
    if (pendingDocs > 0) {
      onMessage(`Còn ${pendingDocs} ảnh giấy tờ chưa duyệt/từ chối.`, 'error');
      return;
    }
    const res = await api.completeDriverReview(data.driverId);
    if (res.success) {
      onMessage(res.message || 'Đã xác nhận xem lại', 'success');
      onReload();
    } else onMessage(res.message || 'Thao tác thất bại', 'error');
  };

  const input = (f: FieldDef) => {
    const v = form[f.key] ?? '';
    const set = (val: any) => setForm((s) => ({ ...s, [f.key]: val }));
    if (f.kind === 'gender') {
      return (
        <select className="input" value={String(v)} onChange={(e) => set(e.target.value)}>
          <option value="">— Chưa chọn —</option>
          {Object.entries(GENDER).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
        </select>
      );
    }
    if (f.kind === 'date') {
      return <input type="date" className="input" value={String(v).slice(0, 10)} onChange={(e) => set(e.target.value)} />;
    }
    if (f.kind === 'number') {
      return <input type="number" min={0} max={70} className="input" value={v as any} onChange={(e) => set(e.target.value === '' ? '' : Number(e.target.value))} />;
    }
    return <input type="text" className="input" value={String(v)} onChange={(e) => set(e.target.value)} />;
  };

  return (
    <div>
      {/* ── Cảnh báo cần xử lý ── */}
      {data.verificationStatus === 'Pending' && (
        <div className="profile-alert" style={alertStyle('#FFA502')}>
          <div>
            <strong>Tài xế đang chờ duyệt hồ sơ.</strong> Kiểm tra thông tin và ảnh giấy tờ bên dưới trước khi duyệt.
          </div>
          <button className="btn btn-sm btn-success" onClick={() => setShowVerify(true)}>Duyệt / Từ chối hồ sơ</button>
        </div>
      )}
      {data.profileReviewPending && (
        <div style={alertStyle('#FFA502')}>
          <div>
            <strong>Tài xế vừa cập nhật thông tin quan trọng / giấy tờ</strong>
            {data.profileUpdatedAt ? ` lúc ${fmtDateTime(data.profileUpdatedAt)}` : ''}. Kiểm tra rồi xác nhận đã xem lại.
          </div>
          <button className="btn btn-sm btn-primary" onClick={completeReview}>✓ Đã xem lại</button>
        </div>
      )}
      {missing.length > 0 && (
        <div style={alertStyle('#00A8FF')}>
          <div><strong>Hồ sơ còn thiếu:</strong> {missing.join(', ')}</div>
        </div>
      )}

      {/* ── Thông tin tài khoản ── */}
      <div className="profile-grid">
        <div className="profile-card">
          <div className="profile-card-title">🔐 Tài khoản</div>
          <InfoRow label="Số điện thoại (đăng nhập)" value={<span className="mono">{data.phone}</span>} />
          <InfoRow label="Ngày tạo" value={fmtDateTime(data.createdAt)} />
          <InfoRow label="Đăng nhập lần cuối" value={data.lastLoginAt ? fmtDateTime(data.lastLoginAt) : 'Chưa đăng nhập'} />
          <InfoRow label="Trạng thái hoạt động" value={<Badge value={data.driverStatus} />} />
          <InfoRow label="Đánh giá" value={`⭐ ${Number(data.ratingAverage || 0).toFixed(1)} (${data.ratingCount || 0} lượt) · ${data.totalTrips || 0} chuyến`} />
        </div>

        {SECTIONS.map((s) => (
          <div className="profile-card" key={s.title}>
            <div className="profile-card-title">{s.icon} {s.title}</div>
            {s.fields.map((f) => (
              <InfoRow
                key={f.key}
                label={f.label}
                value={
                  editing ? input(f) : f.render ? f.render(profile[f.key]) : (
                    <span className={f.mono ? 'mono' : undefined}>{profile[f.key] == null || profile[f.key] === '' ? '—' : String(profile[f.key])}</span>
                  )
                }
              />
            ))}
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', margin: '12px 0 28px' }}>
        {editing ? (
          <>
            <button className="btn btn-ghost" onClick={() => setEditing(false)} disabled={saving}>Hủy</button>
            <button className="btn btn-primary" onClick={save} disabled={saving}>{saving ? 'Đang lưu...' : 'Lưu hồ sơ'}</button>
          </>
        ) : (
          <button className="btn btn-primary" onClick={startEdit}>✏️ Sửa hồ sơ</button>
        )}
      </div>

      {/* ── Ảnh giấy tờ ── */}
      <h4 style={{ marginBottom: 12, color: 'var(--text-primary)', borderBottom: '1px solid var(--border)', paddingBottom: 8 }}>
        Ảnh giấy tờ
      </h4>
      <div className="doc-grid">
        {DOC_TYPES.map(({ type, label }) => {
          const doc = docOf(type);
          const status = doc?.verificationStatus as string | undefined;
          return (
            <div className="doc-card" key={type}>
              <div className="doc-thumb" onClick={() => doc && setPreview(apiFileUrl(doc.fileUrl))} style={{ cursor: doc ? 'zoom-in' : 'default' }}>
                {doc ? <img src={apiFileUrl(doc.fileUrl)} alt={label} /> : <span>Chưa tải lên</span>}
              </div>
              <div style={{ padding: 10 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 6 }}>
                  <strong style={{ fontSize: 13, color: 'var(--text-primary)' }}>{label}</strong>
                  {status && (
                    <Badge type={status === 'Approved' ? 'success' : status === 'Rejected' ? 'danger' : 'warning'}>
                      {status === 'Approved' ? 'Đã duyệt' : status === 'Rejected' ? 'Từ chối' : 'Chờ duyệt'}
                    </Badge>
                  )}
                </div>
                {doc && <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>Tải lên {fmtDateTime(doc.createdAt)}</div>}
                {status === 'Rejected' && doc.rejectionReason && (
                  <div style={{ fontSize: 12, color: '#FF4757', marginTop: 4 }}>Lý do: {doc.rejectionReason}</div>
                )}
                {doc && rejecting && rejecting.id === doc.id ? (
                  <div style={{ marginTop: 8 }}>
                    <input className="input" autoFocus placeholder="Lý do từ chối (tài xế sẽ thấy)" value={rejecting.reason}
                      onChange={(e) => setRejecting({ id: doc.id, reason: e.target.value })} />
                    <div style={{ display: 'flex', gap: 6, marginTop: 6 }}>
                      <button className="btn btn-sm btn-ghost" onClick={() => setRejecting(null)}>Hủy</button>
                      <button className="btn btn-sm btn-danger" disabled={!rejecting.reason.trim() || busyDoc === doc.id}
                        onClick={() => review(doc.id, 'REJECTED', rejecting.reason.trim())}>Xác nhận từ chối</button>
                    </div>
                  </div>
                ) : doc && (
                  <div style={{ display: 'flex', gap: 6, marginTop: 8 }}>
                    {status !== 'Approved' && (
                      <button className="btn btn-sm btn-success" disabled={busyDoc === doc.id} onClick={() => review(doc.id, 'APPROVED')}>Duyệt</button>
                    )}
                    {status !== 'Rejected' && (
                      <button className="btn btn-sm btn-ghost" disabled={busyDoc === doc.id} onClick={() => setRejecting({ id: doc.id, reason: '' })}>Từ chối</button>
                    )}
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {preview && (
        <div className="modal-backdrop" onClick={() => setPreview(null)} style={{ cursor: 'zoom-out' }}>
          <img src={preview} alt="Giấy tờ" style={{ maxWidth: '92vw', maxHeight: '88vh', borderRadius: 10, boxShadow: '0 10px 40px rgba(0,0,0,.6)' }} />
        </div>
      )}

      {showVerify && (
        <VerifyModal
          driver={{ ...data, licenseNumber: profile.licenseNumber || 'Chưa khai báo GPLX' }}
          onClose={() => setShowVerify(false)}
          onDone={onReload}
        />
      )}
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="profile-row">
      <div className="profile-row-label">{label}</div>
      <div className="profile-row-value">{value}</div>
    </div>
  );
}

function alertStyle(color: string): React.CSSProperties {
  return {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 12,
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '12px 16px',
    marginBottom: 14,
    borderRadius: 10,
    border: `1px solid ${color}55`,
    background: `${color}14`,
    color,
    fontSize: 13,
  };
}
