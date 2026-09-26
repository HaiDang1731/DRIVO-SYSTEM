import { useState } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { api } from './services/api';
import { Sidebar } from './components/Sidebar';
import { LoginPage } from './pages/LoginPage';
import { DashboardPage } from './pages/DashboardPage';
import { DriversPage } from './pages/DriversPage';
import DriverDetailPage from './pages/DriverDetailPage';
import { CustomersPage } from './pages/CustomersPage';
import { BookingsPage } from './pages/BookingsPage';
import { BookingDetailPage } from './pages/BookingDetailPage';
import { LiveMapPage } from './pages/LiveMapPage';
import { PaymentsPage } from './pages/PaymentsPage';
import { WalletsPage } from './pages/WalletsPage';
import { PricingPage } from './pages/PricingPage';
import { VouchersPage } from './pages/VouchersPage';
import { NotificationsPage } from './pages/NotificationsPage';
import { ReportsPage } from './pages/ReportsPage';
import { AdminAccountsPage } from './pages/AdminAccountsPage';
import { SettingsPage } from './pages/SettingsPage';
import './index.css';

export default function App() {
  const [user, setUser] = useState<any | null>(() => {
    const saved = localStorage.getItem('drivo_user');
    return saved ? JSON.parse(saved) : null;
  });

  const handleLogout = () => {
    api.clearToken();
    setUser(null);
  };

  if (!user) return <LoginPage onLogin={setUser} />;

  return (
    <BrowserRouter>
      <div className="layout">
        <Sidebar user={user} onLogout={handleLogout} />
        <main className="main">
          <Routes>
            <Route path="/" element={<Navigate to="/dashboard" replace />} />
            <Route path="/dashboard" element={<DashboardPage />} />
            <Route path="/drivers" element={<DriversPage />} />
            <Route path="/drivers/:id" element={<DriverDetailPage />} />
            <Route path="/customers" element={<CustomersPage />} />
            <Route path="/liveMap" element={<LiveMapPage />} />
            <Route path="/bookings" element={<BookingsPage />} />
            <Route path="/bookings/:id" element={<BookingDetailPage />} />
            <Route path="/payments" element={<PaymentsPage />} />
            <Route path="/wallets" element={<WalletsPage />} />
            <Route path="/pricing" element={<PricingPage />} />
            <Route path="/vouchers" element={<VouchersPage />} />
            <Route path="/notifications" element={<NotificationsPage />} />
            <Route path="/reports" element={<ReportsPage />} />
            <Route path="/adminAccounts" element={<AdminAccountsPage />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="*" element={<Navigate to="/dashboard" replace />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}
