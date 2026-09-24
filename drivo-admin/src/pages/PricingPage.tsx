import { useState, useEffect, useMemo } from 'react';
import { api, PricingRuleDto, PricingRuleInput } from '../services/api';
import { Badge } from '../components/Badge';
import { formatVND, round1000, vehicleTypeLabel } from '../utils/geo';

type NumField = Exclude<keyof PricingRuleInput, 'vehicleType' | 'isActive' | 'effectiveFrom' | 'effectiveTo'>;

const FIELDS: { key: NumField; label: string; unit: string; step?: number; group: 'trip' | 'pickup' | 'wait' | 'commission' }[] = [
  { key: 'baseFare', label: 'Cước mở cửa', unit: 'đ', group: 'trip' },
  { key: 'pricePerKm', label: 'Giá mỗi km (sau 2 km đầu)', unit: 'đ/km', group: 'trip' },
  { key: 'pricePerMinute', label: 'Giá mỗi phút', unit: 'đ/phút', step: 100, group: 'trip' },
  { key: 'nightSurcharge', label: 'Phụ phí đêm (22h–6h)', unit: 'đ', group: 'trip' },
  { key: 'overDistanceTolerancePercent', label: 'Dung sai vượt quãng đường', unit: '%', step: 0.5, group: 'trip' },
  { key: 'freePickupKm', label: 'Km đón miễn phí (xe điện)', unit: 'km', step: 0.1, group: 'pickup' },
  { key: 'pickupFeePerKm', label: 'Phí đón mỗi km vượt', unit: 'đ/km', group: 'pickup' },
  { key: 'freeWaitingMin', label: 'Phút chờ miễn phí', unit: 'phút', step: 1, group: 'wait' },
  { key: 'waitingPricePerMin', label: 'Phí chờ mỗi phút vượt', unit: 'đ/phút', group: 'wait' },
  { key: 'commissionPercent', label: 'Hoa hồng nền tảng DRIVO', unit: '%', step: 0.5, group: 'commission' },
];

const GROUP_TITLES = {
  trip: '🚗 Chặng chính (lái xe của khách)',
  pickup: '🛴 Chặng đón (xe điện gấp)',
  wait: '⏱️ Thời gian chờ',
  commission: '💼 Hoa hồng nền tảng',
};

const VEHICLE_OPTIONS = ['Car', 'Suv', 'Truck', 'Motorbike', 'Other'];

const DEFAULTS: PricingRuleInput = {
  vehicleType: 'Car',
  baseFare: 150000,
  pricePerKm: 16000,
  pricePerMinute: 1000,
  nightSurcharge: 30000,
  waitingPricePerMin: 2000,
  freePickupKm: 3,
  pickupFeePerKm: 5000,
  freeWaitingMin: 10,
  overDistanceTolerancePercent: 10,
  commissionPercent: 15,
  isActive: true,
};

function num(v: unknown, fallback = 0): number {
  const n = Number(v);
  return isFinite(n) ? n : fallback;
}

/** Normalize a rule from the API, filling contract defaults for fields an older backend may not return yet. */
function normalize(r: Partial<PricingRuleDto>): PricingRuleDto {
  return {
    id: num(r.id),
    vehicleType: r.vehicleType ?? 'Car',
    baseFare: num(r.baseFare),
    pricePerKm: num(r.pricePerKm),
    pricePerMinute: num(r.pricePerMinute),
    nightSurcharge: num(r.nightSurcharge),
    waitingPricePerMin: num(r.waitingPricePerMin),
    freePickupKm: num(r.freePickupKm, DEFAULTS.freePickupKm),
    pickupFeePerKm: num(r.pickupFeePerKm, DEFAULTS.pickupFeePerKm),
    freeWaitingMin: num(r.freeWaitingMin, DEFAULTS.freeWaitingMin),
    overDistanceTolerancePercent: num(r.overDistanceTolerancePercent, DEFAULTS.overDistanceTolerancePercent),
    commissionPercent: num(r.commissionPercent, DEFAULTS.commissionPercent),
    isActive: !!r.isActive,
    effectiveFrom: r.effectiveFrom,
    effectiveTo: r.effectiveTo,
    createdAt: r.createdAt,
  };
}

export function PricingPage() {
  const [rules, setRules] = useState<PricingRuleDto[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<{ id: number | null; form: PricingRuleInput } | null>(null);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ text: string; type: 'success' | 'error' } | null>(null);
  const [calcRuleId, setCalcRuleId] = useState<number | null>(null);
  const [calc, setCalc] = useState({ km: 10, minutes: 25, pickupKm: 4, waitingMin: 12, actualKm: 10, night: false });

  const load = async () => {
    setLoading(true);
    try {
      const res = await api.getPricingRules();
      if (res.success) {
        const list = (res.data || []).map(normalize);
        setRules(list);
        setCalcRuleId((cur) => (cur != null && list.some((r) => r.id === cur) ? cur : (list.find((r) => r.isActive) ?? list[0])?.id ?? null));
      } else setMsg({ text: res.message || 'Không tải được bảng giá', type: 'error' });
    } catch {
      setMsg({ text: 'Không kết nối được máy chủ API', type: 'error' });
    }
    setLoading(false);
  };

  useEffect(() => { void load(); }, []);

  const handleToggle = async (id: number) => {
    await api.togglePricingRule(id);
    void load();
  };

  const openEdit = (r: PricingRuleDto) => {
    const { id, createdAt: _c, ...rest } = r;
    void _c;
    setEditing({ id, form: { ...rest } });
  };

  const openCreate = () => setEditing({ id: null, form: { ...DEFAULTS } });

  const save = async () => {
    if (!editing) return;
    setSaving(true);
    try {
      const res = editing.id == null
        ? await api.createPricingRule(editing.form)
        : await api.updatePricingRule(editing.id, editing.form);
      if (res.success) {
        setMsg({ text: res.message || 'Đã lưu bảng giá', type: 'success' });
        setEditing(null);
        void load();
      } else setMsg({ text: res.message || 'Lưu thất bại', type: 'error' });
    } catch {
      setMsg({ text: 'Không kết nối được máy chủ API', type: 'error' });
    }
    setSaving(false);
  };

  const calcRule = rules.find((r) => r.id === calcRuleId) ?? null;
  const result = useMemo(() => {
    if (!calcRule) return null;
    const r = calcRule;
    const km = Math.max(0, calc.km);
    const baseFare = r.baseFare;
    const distanceFare = Math.max(0, km - 2) * r.pricePerKm;
    const timeFare = Math.max(0, calc.minutes) * r.pricePerMinute;
    const night = calc.night ? r.nightSurcharge : 0;
    const estimated = round1000(baseFare + distanceFare + timeFare + night);
    const pickupFee = round1000(Math.max(0, calc.pickupKm - r.freePickupKm) * r.pickupFeePerKm);
    const waitingFee = round1000(Math.max(0, calc.waitingMin - r.freeWaitingMin) * r.waitingPricePerMin);
    const threshold = km * (1 + r.overDistanceTolerancePercent / 100);
    const extraFee = calc.actualKm > threshold ? round1000((calc.actualKm - km) * r.pricePerKm) : 0;
    const final = estimated + pickupFee + waitingFee + extraFee;
    const commission = round1000(final * r.commissionPercent / 100);
    const driverPayout = final - commission;
    return { baseFare, distanceFare, timeFare, night, estimated, pickupFee, waitingFee, extraFee, threshold, final, commission, driverPayout };
  }, [calcRule, calc]);

  const setCalcField = (k: keyof typeof calc, v: string | boolean) =>
    setCalc((c) => ({ ...c, [k]: typeof v === 'boolean' ? v : num(v) }));

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Bảng giá cước</h2>
          <p>Thiết lập cước chặng chính, phí đón bằng xe điện, phí chờ và dung sai quãng đường cho từng loại xe</p>
        </div>
        <div className="topbar-actions">
          <button className="btn btn-primary" onClick={openCreate}>+ Thêm bảng giá</button>
        </div>
      </div>

      {msg && (
        <div className={msg.type === 'error' ? 'error-msg' : 'success-msg'} onClick={() => setMsg(null)} style={{ cursor: 'pointer' }}>
          {msg.text}
        </div>
      )}

      <div className="card" style={{ padding: 0, marginBottom: 20 }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tải bảng giá...</div>
        ) : rules.length === 0 ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Chưa có bảng giá nào.</div>
        ) : (
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Loại xe</th>
                  <th>Mở cửa</th>
                  <th>Giá / km</th>
                  <th>Giá / phút</th>
                  <th>Phụ phí đêm</th>
                  <th>Đón miễn phí</th>
                  <th>Phí đón / km</th>
                  <th>Chờ miễn phí</th>
                  <th>Phí chờ / phút</th>
                  <th>Dung sai km</th>
                  <th>Hoa hồng DRIVO</th>
                  <th>Trạng thái</th>
                  <th>Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {rules.map((r) => (
                  <tr key={r.id}>
                    <td><strong>{vehicleTypeLabel(r.vehicleType)}</strong></td>
                    <td>{formatVND(r.baseFare)}</td>
                    <td>{formatVND(r.pricePerKm)}</td>
                    <td>{formatVND(r.pricePerMinute)}</td>
                    <td>{formatVND(r.nightSurcharge)}</td>
                    <td>{r.freePickupKm} km</td>
                    <td>{formatVND(r.pickupFeePerKm)}</td>
                    <td>{r.freeWaitingMin} phút</td>
                    <td>{formatVND(r.waitingPricePerMin)}</td>
                    <td>{r.overDistanceTolerancePercent}%</td>
                    <td><strong style={{ color: 'var(--accent)' }}>{r.commissionPercent}%</strong></td>
                    <td><Badge type={r.isActive ? 'success' : 'danger'}>{r.isActive ? 'Đang áp dụng' : 'Tạm dừng'}</Badge></td>
                    <td>
                      <div className="btn-row">
                        <button className="btn btn-sm btn-ghost" onClick={() => openEdit(r)}>✏️ Sửa</button>
                        <button className={`btn btn-sm ${r.isActive ? 'btn-danger' : 'btn-success'}`} onClick={() => handleToggle(r.id)}>
                          {r.isActive ? 'Tắt' : 'Bật'}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="detail-grid detail-grid-even">
        <div className="card formula-card">
          <h3 className="section-title">📐 Công thức tính giá</h3>
          <p className="formula-intro">
            Khách thuê tài xế lái <b>chính xe của khách</b>. Tài xế di chuyển tới điểm đón bằng <b>xe điện gấp</b> của công ty,
            gấp xe bỏ cốp rồi lái xe khách tới điểm đến. Giá gồm các phần:
          </p>
          <ol className="formula-list">
            <li>
              <b>Cước chặng chính</b> (ước tính lúc đặt, km theo OSRM):
              <code>Mở cửa + max(0, km − 2) × Giá/km + phút × Giá/phút + Phụ phí đêm (22h–6h)</code>, làm tròn 1.000đ.
            </li>
            <li>
              <b>Phí đón (xe điện)</b>: tính khi tài xế nhận chuyến từ vị trí tài xế tới điểm đón —
              <code>max(0, km đón − Km đón miễn phí) × Phí đón/km</code>, làm tròn 1.000đ.
            </li>
            <li>
              <b>Phí chờ</b>: từ lúc tài xế tới nơi đến lúc bắt đầu chuyến —
              <code>max(0, phút chờ − Phút chờ miễn phí) × Phí chờ/phút</code>, làm tròn 1.000đ.
            </li>
            <li>
              <b>Phí vượt quãng đường</b>: km thực tế đo bằng GPS; nếu
              <code>km thực tế &gt; km dự kiến × (1 + Dung sai%)</code> thì
              <code>(km thực tế − km dự kiến) × Giá/km</code>, làm tròn 1.000đ; ngược lại 0.
            </li>
            <li>
              <b>Giá cuối</b> = <code>Giá ước tính + Phí đón + Phí chờ + Phí vượt quãng đường − Giảm giá</code>.
            </li>
            <li>
              <b>Chia doanh thu</b> (chốt khi hoàn thành chuyến), tính trên <b>giá trước khuyến mãi</b>
              (<code>Giá cuối + Giảm giá</code>): nền tảng giữ <code>× Hoa hồng%</code> (theo loại xe), phần còn lại là thu nhập
              của tài xế. Tiền khuyến mãi do <b>DRIVO chịu toàn bộ</b>: <code>DRIVO thực thu = Hoa hồng − Giảm giá</code>.
            </li>
          </ol>
        </div>

        <div className="card">
          <h3 className="section-title">🧮 Máy tính thử giá</h3>
          {!calcRule ? (
            <div style={{ color: 'var(--text-muted)' }}>Chưa có bảng giá để tính.</div>
          ) : (
            <>
              <div className="calc-grid">
                <div className="input-group calc-span-2">
                  <label>Bảng giá áp dụng</label>
                  <select className="input" value={calcRuleId ?? ''} onChange={(e) => setCalcRuleId(Number(e.target.value))}>
                    {rules.map((r) => (
                      <option key={r.id} value={r.id}>
                        #{r.id} — {vehicleTypeLabel(r.vehicleType)} {r.isActive ? '' : '(tạm dừng)'}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="input-group">
                  <label>Km dự kiến</label>
                  <input type="number" min={0} step={0.1} className="input" value={calc.km} onChange={(e) => setCalcField('km', e.target.value)} />
                </div>
                <div className="input-group">
                  <label>Số phút dự kiến</label>
                  <input type="number" min={0} className="input" value={calc.minutes} onChange={(e) => setCalcField('minutes', e.target.value)} />
                </div>
                <div className="input-group">
                  <label>Km chặng đón (xe điện)</label>
                  <input type="number" min={0} step={0.1} className="input" value={calc.pickupKm} onChange={(e) => setCalcField('pickupKm', e.target.value)} />
                </div>
                <div className="input-group">
                  <label>Phút chờ</label>
                  <input type="number" min={0} className="input" value={calc.waitingMin} onChange={(e) => setCalcField('waitingMin', e.target.value)} />
                </div>
                <div className="input-group">
                  <label>Km thực tế (GPS)</label>
                  <input type="number" min={0} step={0.1} className="input" value={calc.actualKm} onChange={(e) => setCalcField('actualKm', e.target.value)} />
                </div>
                <div className="input-group">
                  <label>Giờ đêm (22h–6h)</label>
                  <label className="switch-row">
                    <input type="checkbox" checked={calc.night} onChange={(e) => setCalcField('night', e.target.checked)} />
                    <span>{calc.night ? 'Có áp phụ phí đêm' : 'Không'}</span>
                  </label>
                </div>
              </div>

              {result && (
                <table className="table fee-table">
                  <tbody>
                    <tr><td>Cước mở cửa</td><td className="fee-value">{formatVND(result.baseFare)}</td></tr>
                    <tr><td>Cước quãng đường <div className="fee-note">max(0, {calc.km} − 2) × {formatVND(calcRule.pricePerKm)}</div></td><td className="fee-value">{formatVND(result.distanceFare)}</td></tr>
                    <tr><td>Cước thời gian <div className="fee-note">{calc.minutes} × {formatVND(calcRule.pricePerMinute)}</div></td><td className="fee-value">{formatVND(result.timeFare)}</td></tr>
                    <tr><td>Phụ phí đêm</td><td className="fee-value">{formatVND(result.night)}</td></tr>
                    <tr className="fee-strong"><td>Giá ước tính (làm tròn)</td><td className="fee-value">{formatVND(result.estimated)}</td></tr>
                    <tr><td>Phí đón xe điện <div className="fee-note">max(0, {calc.pickupKm} − {calcRule.freePickupKm}) × {formatVND(calcRule.pickupFeePerKm)}</div></td><td className="fee-value">{formatVND(result.pickupFee)}</td></tr>
                    <tr><td>Phí chờ <div className="fee-note">max(0, {calc.waitingMin} − {calcRule.freeWaitingMin}) × {formatVND(calcRule.waitingPricePerMin)}</div></td><td className="fee-value">{formatVND(result.waitingFee)}</td></tr>
                    <tr>
                      <td>
                        Phí vượt quãng đường
                        <div className="fee-note">
                          ngưỡng {result.threshold.toLocaleString('vi-VN', { maximumFractionDigits: 2 })} km
                          {result.extraFee > 0 ? ` → (${calc.actualKm} − ${calc.km}) × ${formatVND(calcRule.pricePerKm)}` : ' → không vượt'}
                        </div>
                      </td>
                      <td className="fee-value">{formatVND(result.extraFee)}</td>
                    </tr>
                    <tr className="fee-strong"><td>Giá cuối (chưa trừ giảm giá)</td><td className="fee-value">{formatVND(result.final)}</td></tr>
                    <tr>
                      <td>Hoa hồng nền tảng DRIVO <div className="fee-note">Giá cuối × {calcRule.commissionPercent}%</div></td>
                      <td className="fee-value" style={{ color: 'var(--danger, #FF4757)' }}>− {formatVND(result.commission)}</td>
                    </tr>
                    <tr className="fee-strong"><td>Tài xế thực nhận</td><td className="fee-value" style={{ color: '#00D4AA' }}>{formatVND(result.driverPayout)}</td></tr>
                  </tbody>
                </table>
              )}
            </>
          )}
        </div>
      </div>

      {editing && (
        <div className="modal-backdrop" onClick={() => !saving && setEditing(null)}>
          <div className="modal modal-wide" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editing.id == null ? 'Thêm bảng giá' : `Sửa bảng giá #${editing.id}`}</h3>
              <button className="btn-close" onClick={() => setEditing(null)} disabled={saving}>✕</button>
            </div>
            <div className="modal-body">
              <div className="calc-grid">
                <div className="input-group">
                  <label>Loại xe</label>
                  {editing.id == null ? (
                    <select
                      className="input"
                      value={String(editing.form.vehicleType)}
                      onChange={(e) => setEditing({ ...editing, form: { ...editing.form, vehicleType: e.target.value } })}
                    >
                      {VEHICLE_OPTIONS.map((v) => <option key={v} value={v}>{vehicleTypeLabel(v)}</option>)}
                    </select>
                  ) : (
                    <input className="input" readOnly value={vehicleTypeLabel(editing.form.vehicleType)} />
                  )}
                </div>
                <div className="input-group">
                  <label>Trạng thái</label>
                  <label className="switch-row">
                    <input
                      type="checkbox"
                      checked={editing.form.isActive}
                      onChange={(e) => setEditing({ ...editing, form: { ...editing.form, isActive: e.target.checked } })}
                    />
                    <span>{editing.form.isActive ? 'Đang áp dụng' : 'Tạm dừng'}</span>
                  </label>
                </div>
              </div>
              {(['trip', 'pickup', 'wait', 'commission'] as const).map((g) => (
                <div key={g}>
                  <div className="form-group-title">{GROUP_TITLES[g]}</div>
                  <div className="calc-grid">
                    {FIELDS.filter((f) => f.group === g).map((f) => (
                      <div className="input-group" key={f.key}>
                        <label>{f.label} ({f.unit})</label>
                        <input
                          type="number"
                          min={0}
                          step={f.step ?? 1000}
                          className="input"
                          value={editing.form[f.key]}
                          onChange={(e) => setEditing({ ...editing, form: { ...editing.form, [f.key]: num(e.target.value) } })}
                        />
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setEditing(null)} disabled={saving}>Hủy</button>
              <button className="btn btn-primary" onClick={save} disabled={saving}>{saving ? 'Đang lưu...' : 'Lưu bảng giá'}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
