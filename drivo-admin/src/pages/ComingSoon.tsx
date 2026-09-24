
export function ComingSoon({ title }: { title: string }) {
  return (
    <div>
      <div className="topbar">
        <div className="topbar-title"><h2>{title}</h2><p>Đang phát triển</p></div>
      </div>
      <div className="card" style={{ textAlign: 'center', padding: '80px 20px' }}>
        <div style={{ fontSize: 64, marginBottom: 20 }}>🚧</div>
        <h2 style={{ color: 'var(--text-primary)', marginBottom: 12 }}>{title} đang được xây dựng</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: 14 }}>Tính năng này sẽ ra mắt trong phiên bản tiếp theo</p>
      </div>
    </div>
  );
}
