import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, WalletOverview, WalletTx } from '../services/api';
import { Badge } from '../components/Badge';
import { formatVND } from '../utils/geo';

const TYPE_LABEL: Record<string, string> = {
  TOPUP: 'Nạp tiền',
  WITHDRAW: 'Rút tiền',
  TRIP_CASH: 'Chuyến tiền mặt (trừ hoa hồng)',
  TRIP_APP: 'Chuyến trả qua app (cộng thu nhập)',
  ADJUSTMENT: 'Điều chỉnh',
};

/** API trả DateTime UTC không kèm 'Z' */
function fmtTime(s?: string | null): string {
  if (!s) return '—';
  const d = new Date(/(Z|[+-]\d\d:?\d\d)$/.test(s) ? s : `${s}Z`);
  return d.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit', year: 'numeric' });
}

function Signed({ v }: { v: number }) {
  return <span style={{ color: v >= 0 ? '#00D4AA' : '#FF4757', fontWeight: 700 }}>{v > 0 ? '+' : ''}{formatVND(v)}</span>;
}

export function WalletsPage() {
  const navigate = useNavigate();
  const [data, setData] = useState<WalletOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [msg, setMsg] = useState<{ text: string; type: 'success' | 'error' } | null>(null);
  const [busy, setBusy] = useState<number | null>(null);
  const [rejecting, setRejecting] = useState<{ tx: WalletTx; reason: string } | null>(null);
  const [history, setHistory] = useState<{ driverId: number; name: string; items: WalletTx[] | null } | null>(null);
  const [adjusting, setAdjusting] = useState<{ driverId: number; name: string; amount: string; note: string } | null>(null);
  const [filter, setFilter] = useState<'all' | 'below' | 'pending'>('all');

  const load = async () => {
    const res = await api.getWalletOverview();
    if (res.success && res.data) setData(res.data);
    else setMsg({ text: res.message || 'Không tải được ví tài xế', type: 'error' });
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const approve = async (tx: WalletTx) => {
    setBusy(tx.id);
    const res = await api.approveWalletTx(tx.id);
    setBusy(null);
    setMsg({ text: res.message || (res.success ? 'Đã duyệt' : 'Duyệt thất bại'), type: res.success ? 'success' : 'error' });
    load();
  };

  const reject = async () => {
    if (!rejecting) return;
    setBusy(rejecting.tx.id);
    const res = await api.rejectWalletTx(rejecting.tx.id, rejecting.reason.trim());
    setBusy(null);
    setMsg({ text: res.message || (res.success ? 'Đã từ chối' : 'Thất bại'), type: res.success ? 'success' : 'error' });
    if (res.success) setRejecting(null);
    load();
  };

  const openHistory = async (driverId: number, name: string) => {
    setHistory({ driverId, name, items: null });
    const res = await api.getDriverWalletTransactions(driverId);
    setHistory({ driverId, name, items: res.success ? res.data ?? [] : [] });
  };

  const adjust = async () => {
    if (!adjusting) return;
    const amount = Number(adjusting.amount);
    if (!amount || !adjusting.note.trim()) return;
    const res = await api.adjustWallet(adjusting.driverId, amount, adjusting.note.trim());
    setMsg({ text: res.message || (res.success ? 'Đã điều chỉnh' : 'Thất bại'), type: res.success ? 'success' : 'error' });
    if (res.success) setAdjusting(null);
    load();
  };

  const drivers = (data?.drivers ?? []).filter((d) =>
    filter === 'below' ? d.belowMinimum : filter === 'pending' ? d.pendingRequests > 0 : true);

  const cards = data ? [
    { label: 'Tổng số dư ví tài xế', value: formatVND(data.totalBalance), note: 'DRIVO đang giữ hộ tài xế', icon: '👛', color: '#6C63FF' },
    { label: 'Tài xế dưới mức ký quỹ', value: String(data.driversBelowMinimum), note: `Tối thiểu ${formatVND(data.minBalance)} · không nhận được cuốc`, icon: '⚠️', color: '#FFA502' },
    { label: 'Lệnh nạp chờ duyệt', value: `${data.pendingTopups}`, note: formatVND(data.pendingTopupAmount), icon: '⬇️', color: '#00D4AA' },
    { label: 'Lệnh rút chờ chi trả', value: `${data.pendingWithdrawals}`, note: formatVND(data.pendingWithdrawAmount), icon: '⬆️', color: '#FF4757' },
  ] : [];

  return (
    <div>
      <div className="topbar">
        <div className="topbar-title">
          <h2>Ví tài xế</h2>
          <p>Ký quỹ tối thiểu {formatVND(data?.minBalance ?? 500000)} · duyệt nạp/rút · cấn trừ tự động theo chuyến</p>
        </div>
      </div>

      {msg && (
        <div className={msg.type === 'error' ? 'error-msg' : 'success-msg'} onClick={() => setMsg(null)} style={{ cursor: 'pointer' }}>
          {msg.text}
        </div>
      )}

      {loading ? (
        <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tải...</div>
      ) : (
        <>
          <div className="stats-grid" style={{ marginBottom: 20 }}>
            {cards.map((c) => (
              <div className="stat-card" key={c.label}>
                <div className="stat-icon" style={{ backgroundColor: `${c.color}22`, color: c.color }}>{c.icon}</div>
                <div className="stat-label">{c.label}</div>
                <div className="stat-value">{c.value}</div>
                <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>{c.note}</div>
              </div>
            ))}
          </div>

          {/* ── Yêu cầu chờ duyệt ── */}
          <div className="card" style={{ padding: 0, marginBottom: 20 }}>
            <h3 className="section-title" style={{ padding: '20px 20px 0' }}>Yêu cầu nạp / rút chờ duyệt</h3>
            <p style={{ padding: '0 20px', margin: '6px 0 0', fontSize: 12, color: 'var(--text-muted)' }}>
              Nạp: đối chiếu sao kê ngân hàng theo <b>nội dung chuyển khoản</b> rồi bấm Duyệt. Rút: chuyển khoản cho tài xế theo
              tài khoản trong ghi chú rồi bấm Đã chi trả. (Bản demo: tài khoản DRIVO là thông tin giả.)
            </p>
            <div className="table-responsive">
              <table className="table">
                <thead>
                  <tr><th>Thời gian</th><th>Tài xế</th><th>Loại</th><th>Số tiền</th><th>Nội dung CK / Ghi chú</th><th>Thao tác</th></tr>
                </thead>
                <tbody>
                  {(data?.pendingRequests ?? []).length === 0 ? (
                    <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-muted)' }}>Không có yêu cầu nào đang chờ</td></tr>
                  ) : data!.pendingRequests.map((t) => (
                    <tr key={t.id}>
                      <td style={{ fontSize: 12 }}>{fmtTime(t.createdAt)}</td>
                      <td>
                        <div style={{ fontWeight: 600, cursor: 'pointer', color: 'var(--accent)' }} onClick={() => navigate(`/drivers/${t.driverId}`)}>{t.driverName}</div>
                        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{t.driverPhone}</div>
                      </td>
                      <td><Badge type={t.type === 'TOPUP' ? 'success' : 'danger'}>{TYPE_LABEL[t.type] ?? t.type}</Badge></td>
                      <td><Signed v={t.amount} /></td>
                      <td style={{ fontSize: 12 }}>
                        {t.referenceCode && <div className="mono" style={{ color: '#00D4AA', fontWeight: 700 }}>{t.referenceCode}</div>}
                        <div style={{ color: 'var(--text-muted)' }}>{t.note}</div>
                      </td>
                      <td>
                        {rejecting?.tx.id === t.id ? (
                          <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                            <input className="input" style={{ width: 180 }} autoFocus placeholder="Lý do từ chối" value={rejecting.reason}
                              onChange={(e) => setRejecting({ tx: t, reason: e.target.value })} />
                            <button className="btn btn-sm btn-danger" disabled={!rejecting.reason.trim() || busy === t.id} onClick={reject}>Từ chối</button>
                            <button className="btn btn-sm btn-ghost" onClick={() => setRejecting(null)}>Hủy</button>
                          </div>
                        ) : (
                          <div style={{ display: 'flex', gap: 6 }}>
                            <button className="btn btn-sm btn-success" disabled={busy === t.id} onClick={() => approve(t)}>
                              {t.type === 'TOPUP' ? 'Đã nhận tiền · Duyệt' : 'Đã chi trả'}
                            </button>
                            <button className="btn btn-sm btn-ghost" onClick={() => setRejecting({ tx: t, reason: '' })}>Từ chối</button>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* ── Số dư từng tài xế ── */}
          <div className="card" style={{ padding: 0 }}>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center', justifyContent: 'space-between', padding: '20px 20px 0' }}>
              <h3 className="section-title" style={{ margin: 0 }}>Số dư ví từng tài xế</h3>
              <div style={{ display: 'flex', gap: 6 }}>
                {([['all', 'Tất cả'], ['below', 'Dưới mức ký quỹ'], ['pending', 'Có yêu cầu chờ']] as const).map(([k, l]) => (
                  <button key={k} className={`btn btn-sm ${filter === k ? 'btn-primary' : 'btn-ghost'}`} onClick={() => setFilter(k)}>{l}</button>
                ))}
              </div>
            </div>
            <div className="table-responsive">
              <table className="table">
                <thead>
                  <tr><th>Tài xế</th><th>Số dư</th><th>Trạng thái ví</th><th>Hoạt động</th><th>Yêu cầu chờ</th><th>Thao tác</th></tr>
                </thead>
                <tbody>
                  {drivers.map((d) => (
                    <tr key={d.driverId}>
                      <td>
                        <div style={{ fontWeight: 600, cursor: 'pointer', color: 'var(--accent)' }} onClick={() => navigate(`/drivers/${d.driverId}`)}>{d.fullName}</div>
                        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>{d.phone}</div>
                      </td>
                      <td><strong style={{ color: d.belowMinimum ? '#FFA502' : '#00D4AA' }}>{formatVND(d.balance)}</strong></td>
                      <td>
                        {d.belowMinimum
                          ? <Badge type="warning">Thiếu {formatVND((data?.minBalance ?? 0) - d.balance)}</Badge>
                          : <Badge type="success">Đủ ký quỹ</Badge>}
                      </td>
                      <td><Badge value={d.driverStatus} /></td>
                      <td>{d.pendingRequests || '—'}</td>
                      <td>
                        <div style={{ display: 'flex', gap: 6 }}>
                          <button className="btn btn-sm btn-ghost" onClick={() => openHistory(d.driverId, d.fullName)}>Lịch sử</button>
                          <button className="btn btn-sm btn-ghost" onClick={() => setAdjusting({ driverId: d.driverId, name: d.fullName, amount: '', note: '' })}>Điều chỉnh</button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}

      {history && (
        <div className="modal-backdrop" onClick={() => setHistory(null)}>
          <div className="modal modal-wide" style={{ width: 860 }} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Lịch sử ví · {history.name}</h3>
              <button className="btn-close" onClick={() => setHistory(null)}>✕</button>
            </div>
            <div className="modal-body" style={{ padding: 0 }}>
              {history.items == null ? (
                <div style={{ padding: 30, textAlign: 'center', color: 'var(--text-muted)' }}>Đang tải...</div>
              ) : history.items.length === 0 ? (
                <div style={{ padding: 30, textAlign: 'center', color: 'var(--text-muted)' }}>Chưa có giao dịch</div>
              ) : (
                <div className="table-responsive">
                  <table className="table">
                    <thead><tr><th>Thời gian</th><th>Loại</th><th>Số tiền</th><th>Số dư sau</th><th>Trạng thái</th><th>Ghi chú</th></tr></thead>
                    <tbody>
                      {history.items.map((t) => (
                        <tr key={t.id}>
                          <td style={{ fontSize: 12 }}>{fmtTime(t.createdAt)}</td>
                          <td style={{ fontSize: 12 }}>{TYPE_LABEL[t.type] ?? t.type}{t.bookingCode ? <div className="mono" style={{ color: 'var(--accent)' }}>{t.bookingCode}</div> : null}</td>
                          <td><Signed v={t.amount} /></td>
                          <td>{t.balanceAfter != null ? formatVND(t.balanceAfter) : '—'}</td>
                          <td>
                            <Badge type={t.status === 'COMPLETED' ? 'success' : t.status === 'PENDING' ? 'warning' : 'danger'}>
                              {t.status === 'COMPLETED' ? 'Hoàn tất' : t.status === 'PENDING' ? 'Chờ duyệt' : 'Từ chối/Hủy'}
                            </Badge>
                          </td>
                          <td style={{ fontSize: 12, color: 'var(--text-muted)' }}>{t.referenceCode ? `${t.referenceCode} · ` : ''}{t.note}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {adjusting && (
        <div className="modal-backdrop" onClick={() => setAdjusting(null)}>
          <div className="modal" style={{ width: 440, maxWidth: '100%' }} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">Điều chỉnh ví · {adjusting.name}</h3>
              <button className="btn-close" onClick={() => setAdjusting(null)}>✕</button>
            </div>
            <div className="modal-body">
              <div className="input-group">
                <label>Số tiền (âm để trừ, ví dụ -50000)</label>
                <input type="number" step={1000} className="input" value={adjusting.amount}
                  onChange={(e) => setAdjusting({ ...adjusting, amount: e.target.value })} />
              </div>
              <div className="input-group">
                <label>Lý do (bắt buộc, tài xế sẽ thấy)</label>
                <input className="input" value={adjusting.note} placeholder="VD: Hoàn phí chờ bị tính sai chuyến DRV..."
                  onChange={(e) => setAdjusting({ ...adjusting, note: e.target.value })} />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={() => setAdjusting(null)}>Hủy</button>
              <button className="btn btn-primary" disabled={!Number(adjusting.amount) || !adjusting.note.trim()} onClick={adjust}>Xác nhận</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
