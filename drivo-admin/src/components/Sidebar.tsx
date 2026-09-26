import { useLocation, useNavigate } from 'react-router-dom';
import { Avatar } from './Avatar';

interface SidebarProps {
  user: any;
  onLogout: () => void;
}

export function Sidebar({ user, onLogout }: SidebarProps) {
  const location = useLocation();
  const navigate = useNavigate();
  // We extract the current page from the pathname, e.g. "/drivers" -> "drivers", "/" -> "dashboard"
  const page = location.pathname === '/' ? 'dashboard' : location.pathname.split('/')[1] || 'dashboard';
  const menuSections = [
    {
      title: 'VẬN HÀNH',
      items: [
        { id: 'dashboard', label: 'Dashboard', icon: '📊' },
        { id: 'liveMap', label: 'Bản đồ trực tiếp', icon: '🗺️' },
        { id: 'drivers', label: 'Tài xế', icon: '🚗' },
        { id: 'customers', label: 'Khách hàng', icon: '👥' },
        { id: 'bookings', label: 'Chuyến đi', icon: '📋' },
        { id: 'payments', label: 'Thanh toán', icon: '💳' },
        { id: 'wallets', label: 'Ví tài xế', icon: '👛' },
      ]
    },
    {
      title: 'CHIẾN LƯỢC & ƯU ĐÃI',
      items: [
        { id: 'pricing', label: 'Bảng giá cước', icon: '💰' },
        { id: 'vouchers', label: 'Khuyến mãi', icon: '🎟️' },
        { id: 'notifications', label: 'Thông báo', icon: '🔔' },
      ]
    },
    {
      title: 'HỆ THỐNG',
      items: [
        { id: 'reports', label: 'Báo cáo', icon: '📈' },
        { id: 'adminAccounts', label: 'Tài khoản Admin', icon: '🛡️' },
        { id: 'settings', label: 'Cài đặt', icon: '⚙️' },
      ]
    }
  ];

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <span className="brand-icon">🚗</span>
        <div className="brand-text">
          <h1>DRIVO</h1>
          <span>ADMIN DASHBOARD</span>
        </div>
      </div>

      <nav className="sidebar-nav" style={{ overflowY: 'auto', flex: 1, paddingBottom: 20 }}>
        {menuSections.map((section, idx) => (
          <div key={idx} style={{ marginBottom: 14 }}>
            <div className="nav-label" style={{ fontSize: 11, padding: '8px 16px 4px 16px', color: 'var(--text-muted)', letterSpacing: 0.5 }}>
              {section.title}
            </div>
            {section.items.map((item) => {
              const active = page === item.id;
              return (
                <div
                  key={item.id}
                  className={`nav-item ${active ? 'active' : ''}`}
                  onClick={() => navigate(`/${item.id}`)}
                  style={{ cursor: 'pointer' }}
                >
                  <span className="nav-icon">{item.icon}</span>
                  <span className="nav-text">{item.label}</span>
                </div>
              );
            })}
          </div>
        ))}
      </nav>

      <div className="sidebar-footer">
        <div className="user-profile">
          <Avatar name={user?.fullName || 'Admin'} />
          <div className="user-info">
            <span className="user-name">{user?.fullName || 'Admin'}</span>
            <span className="user-role">{user?.roles?.[0] || 'Administrator'}</span>
          </div>
        </div>
        <button className="btn-logout" onClick={onLogout} title="Đăng xuất">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path>
            <polyline points="16 17 21 12 16 7"></polyline>
            <line x1="21" y1="12" x2="9" y2="12"></line>
          </svg>
        </button>
      </div>
    </aside>
  );
}
