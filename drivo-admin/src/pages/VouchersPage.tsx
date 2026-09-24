import { useState, useEffect } from 'react';
import { api } from '../services/api';
import { Badge } from '../components/Badge';

type VoucherForm = {
  code: string;
  title: string;
  description: string;
  discountType: 'PERCENT' | 'FIXED';
  discountValue: number;
  maxDiscountAmount: number;
  minOrderAmount: number;
  usageLimit: number;
  isActive: boolean;
  /** yyyy-MM-dd theo giờ máy admin */
  startDate: string;
  endDate: string;
};

/** API trả DateTime UTC không kèm 'Z'. */
function parseUtc(s?: string | null): Date | null {
  if (!s) return null;
  return new Date(/(Z|[+-]\d\d:?\d\d)$/.test(s) ? s : `${s}Z`);
}

function toInputDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function addDays(d: Date, n: number): Date {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

const formatDate = (d: Date | null) =>
  d ? d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' }) : '—';

function emptyForm(): VoucherForm {
  const today = new Date();
  return {
    code: '',
    title: '',
    description: '',
    discountType: 'PERCENT',
    discountValue: 20,
    maxDiscountAmount: 50000,
    minOrderAmount: 0,
    usageLimit: 100,
    isActive: true,
    startDate: toInputDate(today),
    endDate: toInputDate(addDays(today, 30)),
  };
}

function formFromVoucher(v: any): VoucherForm {
  const start = parseUtc(v.startDate) ?? new Date();
  const end = parseUtc(v.endDate) ?? addDays(start, 30);
  return {
    code: v.code ?? '',
    title: v.title ?? '',
    description: v.description ?? '',
    discountType: v.discountType === 'FIXED' ? 'FIXED' : 'PERCENT',
    discountValue: Number(v.discountValue) || 0,
    maxDiscountAmount: Number(v.maxDiscountAmount) || 0,
    minOrderAmount: Number(v.minOrderAmount) || 0,
    usageLimit: Number(v.usageLimit) || 1,
    isActive: !!v.isActive,
    startDate: toInputDate(start),
    endDate: toInputDate(end),
  };
}

/** Trạng thái thực tế: bật/tắt + còn hạn + còn lượt */
function voucherState(v: any): { label: string; type: 'success' | 'danger' | 'warning' | 'info' } {
  const now = new Date();
  const start = parseUtc(v.startDate);
  const end = parseUtc(v.endDate);
  if (!v.isActive) return { label: 'Tạm dừng', type: 'danger' };
  if (end && end < now) return { label: 'Hết hạn', type: 'danger' };
  if (start && start > now) return { label: 'Chưa bắt đầu', type: 'info' };
  if (v.usedCount >= v.usageLimit) return { label: 'Hết lượt', type: 'warning' };
  return { label: 'Hoạt động', type: 'success' };
}

export function VouchersPage() {
  const [vouchers, setVouchers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<{ id: number | null; usedCount: number; form: VoucherForm } | null>(null);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ text: string; type: 'success' | 'error' } | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<any | null>(null);

  const load = async () => {
    setLoading(true);
    const res = await api.getVouchers();
    if (res.success) setVouchers(res.data || []);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const openCreate = () => {
    setFormError(null);
    setEditing({ id: null, usedCount: 0, form: emptyForm() });
  };

  const openEdit = (v: any) => {
    setFormError(null);
    setEditing({ id: v.id, usedCount: v.usedCount ?? 0, form: formFromVoucher(v) });
  };

  const setField = <K extends keyof VoucherForm>(k: K, value: VoucherForm[K]) =>
    setEditing((e) => (e ? { ...e, form: { ...e.form, [k]: value } } : e));

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editing) return;
    const f = editing.form;
    if (f.endDate < f.startDate) {
      setFormError('Hạn sử dụng phải từ ngày bắt đầu trở đi');
      return;
    }
    // Bắt đầu lúc 00:00 ngày bắt đầu, hết hạn lúc 23:59:59 ngày hết hạn (giờ máy admin)
    const payload = {
      ...f,
      code: f.code.trim().toUpperCase(),
      maxDiscountAmount: f.discountType === 'PERCENT' && f.maxDiscountAmount > 0 ? f.maxDiscountAmount : null,
      startDate: new Date(`${f.startDate}T00:00:00`).toISOString(),
      endDate: new Date(`${f.endDate}T23:59:59`).toISOString(),
    };
    setSaving(true);
    setFormError(null);
    try {
      const res = editing.id == null ? await api.createVoucher(payload) : await api.updateVoucher(editing.id, payload);
      if (res.success) {
        setMsg({ text: res.message || 'Đã lưu mã giảm giá', type: 'success' });
        setEditing(null);
        load();
      } else {
        setFormError(res.message || 'Lưu thất bại');
      }
    } catch {
      setFormError('Không kết nối được máy chủ API');
    }
    setSaving(false);
  };

  const handleToggle = async (id: number) => {
    await api.toggleVoucher(id);
    load();
  };

  const handleDelete = async () => {
    if (!confirmDelete) return;
    const res = await api.deleteVoucher(confirmDelete.id);
    setConfirmDelete(null);
    setMsg({ text: res.message || (res.success ? 'Đã xóa mã' : 'Xóa thất bại'), type: res.success ? 'success' : 'error' });
    load();
  };

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val || 0);

  const f = editing?.form;
  const codeLocked = editing != null && editing.id != null && editing.usedCount > 0;

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Quản lý Mã Giảm Giá & Khuyến Mãi</h2>
          <p>Tạo chiến dịch chiết khấu linh hoạt, giới hạn lượt dùng, thời hạn và kích hoạt mã ưu đãi cho khách hàng</p>
        </div>
        <div className="topbar-actions">
          <button className="btn btn-primary" onClick={openCreate}>+ Tạo Mã Mới</button>
        </div>
      </div>

      {msg && (
        <div className={msg.type === 'error' ? 'error-msg' : 'success-msg'} onClick={() => setMsg(null)} style={{ cursor: 'pointer' }}>
          {msg.text}
        </div>
      )}

      <div className="card" style={{ padding: 0 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tải mã giảm giá...</div>
        ) : vouchers.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Chưa có mã khuyến mãi nào.</div>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Mã code</th>
                  <th>Chương trình</th>
                  <th>Mức giảm</th>
                  <th>Giảm tối đa</th>
                  <th>Đơn tối thiểu</th>
                  <th>Thời hạn</th>
                  <th>Lượt dùng / Giới hạn</th>
                  <th>Trạng thái</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {vouchers.map((v) => {
                  const state = voucherState(v);
                  const end = parseUtc(v.endDate);
                  const daysLeft = end ? Math.ceil((end.getTime() - Date.now()) / 86400000) : null;
                  return (
                    <tr key={v.id}>
                      <td><strong style={{ color: 'var(--accent)', letterSpacing: 1 }}>{v.code}</strong></td>
                      <td>
                        <div><strong>{v.title}</strong></div>
                        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{v.description}</div>
                      </td>
                      <td>{v.discountType === 'PERCENT' ? `${v.discountValue}%` : formatCurrency(v.discountValue)}</td>
                      <td>{v.maxDiscountAmount ? formatCurrency(v.maxDiscountAmount) : 'Không giới hạn'}</td>
                      <td>{formatCurrency(v.minOrderAmount)}</td>
                      <td style={{ whiteSpace: 'nowrap' }}>
                        <div>{formatDate(parseUtc(v.startDate))} → {formatDate(end)}</div>
                        {daysLeft != null && daysLeft > 0 && daysLeft <= 7 && (
                          <div style={{ fontSize: 12, color: '#FFA502' }}>Còn {daysLeft} ngày</div>
                        )}
                      </td>
                      <td>{v.usedCount} / {v.usageLimit}</td>
                      <td><Badge type={state.type}>{state.label}</Badge></td>
                      <td>
                        <div style={{ display: 'flex', gap: 6 }}>
                          <button className="btn btn-sm btn-ghost" onClick={() => openEdit(v)}>✏️ Sửa</button>
                          <button className={`btn btn-sm ${v.isActive ? 'btn-danger' : 'btn-success'}`} onClick={() => handleToggle(v.id)}>
                            {v.isActive ? 'Tắt' : 'Bật'}
                          </button>
                          <button className="btn btn-sm btn-ghost" onClick={() => setConfirmDelete(v)}>Xóa</button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {editing && f && (
        <div className="modal-backdrop" onClick={() => !saving && setEditing(null)}>
          <div className="modal" style={{ width: 560, maxWidth: '100%' }} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editing.id == null ? 'Thêm Mã Giảm Giá Mới' : `Sửa mã ${f.code}`}</h3>
              <button className="btn-close" onClick={() => setEditing(null)} disabled={saving}>✕</button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                {formError && <div className="error-msg" style={{ marginBottom: 12 }}>{formError}</div>}
                <div className="input-group">
                  <label>Mã Voucher (viết liền không dấu)</label>
                  <input type="text" className="input" required maxLength={50} disabled={codeLocked} value={f.code}
                    onChange={(e) => setField('code', e.target.value.toUpperCase().replace(/\s/g, ''))} placeholder="VD: DRIVO50K" />
                  {codeLocked && (
                    <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>
                      Mã đã có {editing.usedCount} lượt dùng nên không đổi được mã code.
                    </div>
                  )}
                </div>
                <div className="input-group">
                  <label>Tên chương trình</label>
                  <input type="text" className="input" required value={f.title} onChange={(e) => setField('title', e.target.value)} placeholder="VD: Giảm 50K ngày vàng" />
                </div>
                <div className="input-group">
                  <label>Mô tả (không bắt buộc)</label>
                  <input type="text" className="input" value={f.description} onChange={(e) => setField('description', e.target.value)} placeholder="VD: Dành cho khách hàng mới" />
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                  <div className="input-group">
                    <label>Loại giảm giá</label>
                    <select className="input" value={f.discountType} onChange={(e) => setField('discountType', e.target.value as VoucherForm['discountType'])}>
                      <option value="PERCENT">Phần trăm (%)</option>
                      <option value="FIXED">Số tiền cố định (VNĐ)</option>
                    </select>
                  </div>
                  <div className="input-group">
                    <label>Giá trị giảm {f.discountType === 'PERCENT' ? '(%)' : '(VNĐ)'}</label>
                    <input type="number" className="input" required min={1} max={f.discountType === 'PERCENT' ? 100 : undefined}
                      step={f.discountType === 'PERCENT' ? 1 : 1000} value={f.discountValue}
                      onChange={(e) => setField('discountValue', Number(e.target.value))} />
                  </div>
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                  <div className="input-group">
                    <label>Giảm tối đa (VNĐ)</label>
                    <input type="number" className="input" min={0} step={1000} disabled={f.discountType === 'FIXED'}
                      value={f.discountType === 'FIXED' ? f.discountValue : f.maxDiscountAmount}
                      onChange={(e) => setField('maxDiscountAmount', Number(e.target.value))} />
                    <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>
                      {f.discountType === 'FIXED' ? 'Bằng đúng số tiền giảm' : 'Để 0 nếu không giới hạn'}
                    </div>
                  </div>
                  <div className="input-group">
                    <label>Đơn tối thiểu (VNĐ)</label>
                    <input type="number" className="input" min={0} step={1000} value={f.minOrderAmount}
                      onChange={(e) => setField('minOrderAmount', Number(e.target.value))} />
                  </div>
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                  <div className="input-group">
                    <label>Ngày bắt đầu</label>
                    <input type="date" className="input" required value={f.startDate} onChange={(e) => setField('startDate', e.target.value)} />
                  </div>
                  <div className="input-group">
                    <label>Hạn sử dụng (hết ngày)</label>
                    <input type="date" className="input" required min={f.startDate} value={f.endDate} onChange={(e) => setField('endDate', e.target.value)} />
                  </div>
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
                  <div className="input-group">
                    <label>Số lượt phát hành</label>
                    <input type="number" className="input" required min={Math.max(1, editing.usedCount)} value={f.usageLimit}
                      onChange={(e) => setField('usageLimit', Number(e.target.value))} />
                    {editing.usedCount > 0 && (
                      <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>Đã dùng {editing.usedCount} lượt</div>
                    )}
                  </div>
                  <div className="input-group">
                    <label>Trạng thái</label>
                    <label className="switch-row">
                      <input type="checkbox" checked={f.isActive} onChange={(e) => setField('isActive', e.target.checked)} />
                      <span>{f.isActive ? 'Đang bật' : 'Tạm dừng'}</span>
                    </label>
                  </div>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-ghost" onClick={() => setEditing(null)} disabled={saving}>Hủy</button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? 'Đang lưu...' : editing.id == null ? 'Tạo Voucher' : 'Lưu thay đổi'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {confirmDelete && (
        <div className="modal-backdrop" onClick={() => setConfirmDelete(null)}>
          <div className="modal" style={{ width: 420, maxWidth: '100%' }} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Xóa mã {confirmDelete.code}?</h3>
              <button className="btn-close" onClick={() => setConfirmDelete(null)}>✕</button>
            </div>
            <div className="modal-body">
              Mã chưa có người dùng mới xóa được. Mã đã dùng cho chuyến đi chỉ có thể <b>Tắt</b>.
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setConfirmDelete(null)}>Hủy</button>
              <button className="btn btn-danger" onClick={handleDelete}>Xóa</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
