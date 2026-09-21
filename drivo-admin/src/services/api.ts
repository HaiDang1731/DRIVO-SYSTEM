// API service layer for DRIVO Admin
const BASE_URL = 'http://localhost:5270/api/v1';

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
    const data = await res.json();
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

  getDriver: (id: number) => api.request(`/admin/drivers/${id}`),

  createDriver: (data: object) =>
    api.request('/admin/drivers', { method: 'POST', body: JSON.stringify(data) }),

  verifyDriver: (id: number, status: string, reason?: string) =>
    api.request(`/admin/drivers/${id}/verify`, {
      method: 'PATCH',
      body: JSON.stringify({ status, rejectionReason: reason }),
    }),

  setDriverStatus: (id: number, status: string) =>
    api.request(`/admin/drivers/${id}/status?status=${status}`, { method: 'PATCH' }),

  addDriverDocument: (id: number, docType: string, fileUrl: string) =>
    api.request(`/admin/drivers/${id}/documents`, {
      method: 'POST',
      body: JSON.stringify({ documentType: docType, fileUrl }),
    }),
};

