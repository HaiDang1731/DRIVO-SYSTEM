// API service layer for DRIVO Admin
export const BASE_URL = 'http://localhost:5270/api/v1';

// ── Typed DTOs (camelCase, see maps-contract.md) ──
export interface ApiResponse<T> {
  success: boolean;
  message?: string;
  data: T;
}

export interface TrackingDriver {
  driverId: number;
  userId: number;
  fullName: string;
  phone: string;
  avatarUrl?: string | null;
  driverStatus: string; // Offline | Online | Busy | Suspended
  verificationStatus: string;
  latitude: number;
  longitude: number;
  lastLocationAt?: string | null;
  activeBookingId?: number | null;
  activeBookingCode?: string | null;
  activeBookingStatus?: string | null;
}

export interface ActiveBooking {
  id: number;
  bookingCode: string;
  status: string;
  pickupAddress: string;
  pickupLatitude: number;
  pickupLongitude: number;
  destinationAddress: string;
  destinationLatitude: number;
  destinationLongitude: number;
  routePolyline?: string | null;
  customerName: string;
  customerPhone: string;
  driverId?: number | null;
  driverName?: string | null;
  driverLatitude?: number | null;
  driverLongitude?: number | null;
  estimatedPrice: number;
  createdAt: string;
}

export interface TrailPoint {
  latitude: number;
  longitude: number;
  recordedAt: string;
}

export interface AdminBookingDetail {
  id: number;
  bookingCode: string;
  status: string;
  pickupAddress: string;
  pickupLatitude: number;
  pickupLongitude: number;
  destinationAddress: string;
  destinationLatitude: number;
  destinationLongitude: number;
  estimatedDistanceKm?: number | null;
  estimatedDurationMin?: number | null;
  baseFare?: number;
  distanceFare?: number;
  timeFare?: number;
  surcharge?: number;
  estimatedPrice?: number;
  finalPrice?: number | null;
  customerNote?: string | null;
  createdAt: string;
  routePolyline?: string | null;
  pickupDistanceKm?: number | null;
  pickupFee?: number;
  waitingFee?: number;
  extraDistanceFee?: number;
  discount?: number;
  actualDistanceKm?: number | null;
  acceptedAt?: string | null;
  arrivedAt?: string | null;
  startedAt?: string | null;
  completedAt?: string | null;
  cancelledAt?: string | null;
  driverLatitude?: number | null;
  driverLongitude?: number | null;
  driverLastLocationAt?: string | null;
  vehicle?: { brand?: string; model?: string; licensePlate?: string; color?: string; vehicleType?: string; transmission?: string } | null;
  driver?: { driverId?: number; id?: number; fullName?: string; phone?: string; avatarUrl?: string | null } | null;
  customer?: { fullName?: string; phone?: string } | null;
  trail?: TrailPoint[];
  statusHistory?: { status: string; changedAt: string; note?: string | null }[];
  // pricing rule snapshot (shape may vary — read defensively)
  pricingRule?: Partial<PricingRuleDto> | null;
  [key: string]: unknown;
}

export interface PricingRuleDto {
  id: number;
  vehicleType: string | number;
  baseFare: number;
  pricePerKm: number;
  pricePerMinute: number;
  nightSurcharge: number;
  waitingPricePerMin: number;
  freePickupKm: number;
  pickupFeePerKm: number;
  freeWaitingMin: number;
  overDistanceTolerancePercent: number;
  isActive: boolean;
  effectiveFrom?: string;
  effectiveTo?: string | null;
  createdAt?: string;
}

export type PricingRuleInput = Omit<PricingRuleDto, 'id' | 'createdAt'>;

let _token = localStorage.getItem('drivo_token') || '';

export const api = {
  setToken: (t: string) => { _token = t; localStorage.setItem('drivo_token', t); },
  clearToken: () => { _token = ''; localStorage.removeItem('drivo_token'); localStorage.removeItem('drivo_user'); },
  getToken: () => _token,

  request: async (path: string, opts: RequestInit = {}) => {
    const res = await fetch(`${BASE_URL}${path}`, {
      ...opts,
      headers: {
        'Content-Type': 'application/json',
        ...((_token) ? { Authorization: `Bearer ${_token}` } : {}),
        ...opts.headers,
      },
    });
    const text = await res.text(); const data = text ? JSON.parse(text) : { success: false, message: res.statusText };
    return data;
  },

  // Auth
  login: (email: string, password: string) =>
    api.request('/auth/login', { method: 'POST', body: JSON.stringify({ email, password }) }),

  logout: (refreshToken: string) =>
    api.request('/auth/logout', { method: 'POST', body: JSON.stringify({ refreshToken }) }),

  // Admin Drivers
  getDrivers: (status?: string, page = 1, pageSize = 20) =>
    api.request(`/admin/drivers?${status ? `verificationStatus=${status}&` : ''}page=${page}&pageSize=${pageSize}`),

  getDriver: (id: string | number) => api.request(`/admin/drivers/${id}`),

  createDriver: (data: object) =>
    api.request('/admin/drivers', { method: 'POST', body: JSON.stringify(data) }),

  verifyDriver: (id: string | number, status: string, reason?: string) =>
    api.request(`/admin/drivers/${id}/verify`, {
      method: 'PATCH',
      body: JSON.stringify({ status, rejectionReason: reason }),
    }),

  setDriverStatus: (id: string | number, status: string) =>
    api.request(`/admin/drivers/${id}/status?status=${status}`, { method: 'PATCH' }),

  resetDriverPassword: (id: string | number, newPassword?: string) =>
    api.request(`/admin/drivers/${id}/reset-password`, {
      method: 'POST',
      body: JSON.stringify({ newPassword }),
    }),

  addDriverDocument: (id: string | number, docType: string, fileUrl: string) =>
    api.request(`/admin/drivers/${id}/documents`, {
      method: 'POST',
      body: JSON.stringify({ documentType: docType, fileUrl }),
    }),

  // Admin Dashboard
  getDashboardOverview: () => api.request('/admin/dashboard/overview'),
  getDashboardChart: (days = 7) => api.request(`/admin/dashboard/chart-revenue?days=${days}`),

  // Admin Customers
  getCustomers: (search?: string, page = 1, pageSize = 50) =>
    api.request(`/admin/customers?search=${search || ''}&page=${page}&pageSize=${pageSize}`),
  getCustomer: (id: string | number) => api.request(`/admin/customers/${id}`),
  setCustomerStatus: (id: string | number, status: string) =>
    api.request(`/admin/customers/${id}/status?status=${status}`, { method: 'PATCH' }),

  // Admin Bookings
  getBookings: (status?: string, search?: string, page = 1, pageSize = 50) =>
    api.request(`/admin/bookings?status=${status || ''}&search=${search || ''}&page=${page}&pageSize=${pageSize}`),
  cancelBooking: (id: string | number, reason: string) =>
    api.request(`/admin/bookings/${id}/cancel`, { method: 'PATCH', body: JSON.stringify({ reason }) }),
  getBookingDetail: (id: string | number): Promise<ApiResponse<AdminBookingDetail>> =>
    api.request(`/admin/bookings/${id}`),

  // Admin Live Tracking
  getTrackingDrivers: (): Promise<ApiResponse<TrackingDriver[]>> => api.request('/admin/tracking/drivers'),
  getActiveBookings: (): Promise<ApiResponse<ActiveBooking[]>> => api.request('/admin/tracking/bookings/active'),

  // Admin Payments
  getPayments: (page = 1, pageSize = 50) =>
    api.request(`/admin/payments?page=${page}&pageSize=${pageSize}`),

  // Admin Pricing
  getPricingRules: (): Promise<ApiResponse<PricingRuleDto[]>> => api.request('/admin/pricing'),
  createPricingRule: (data: PricingRuleInput): Promise<ApiResponse<PricingRuleDto>> =>
    api.request('/admin/pricing', { method: 'POST', body: JSON.stringify(data) }),
  updatePricingRule: (id: string | number, data: PricingRuleInput): Promise<ApiResponse<PricingRuleDto>> => api.request(`/admin/pricing/${id}`, { method: 'PUT', body: JSON.stringify(data) }),
  togglePricingRule: (id: string | number) => api.request(`/admin/pricing/${id}/toggle`, { method: 'PATCH' }),

  // Admin Vouchers
  getVouchers: () => api.request('/admin/vouchers'),
  createVoucher: (data: any) => api.request('/admin/vouchers', { method: 'POST', body: JSON.stringify(data) }),
  toggleVoucher: (id: string | number) => api.request(`/admin/vouchers/${id}/toggle`, { method: 'PATCH' }),
  deleteVoucher: (id: string | number) => api.request(`/admin/vouchers/${id}`, { method: 'DELETE' }),

  // Admin Notifications
  getNotifications: (take = 50) => api.request(`/admin/notifications?take=${take}`),
  broadcastNotification: (data: any) =>
    api.request('/admin/notifications/broadcast', { method: 'POST', body: JSON.stringify(data) }),

  // Admin Accounts
  getAdmins: () => api.request('/admin/accounts'),
  createAdmin: (data: any) => api.request('/admin/accounts', { method: 'POST', body: JSON.stringify(data) }),
  toggleAdminStatus: (id: string | number) => api.request(`/admin/accounts/${id}/status`, { method: 'PATCH' }),

  // Admin Reports
  getReportSummary: () => api.request('/admin/reports/summary'),

  // Admin Settings
  getSettings: () => api.request('/admin/settings'),
};
