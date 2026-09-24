// Realtime tracking client (SignalR hub /hubs/tracking) for DRIVO Admin.
import * as signalR from '@microsoft/signalr';
import { useEffect, useState } from 'react';
import { api, BASE_URL } from './api';

export const HUB_URL = BASE_URL.replace(/\/api\/v1\/?$/, '') + '/hubs/tracking';

export interface DriverLocationEvent {
  driverId: number;
  bookingId?: number | null;
  latitude: number;
  longitude: number;
  heading?: number | null;
  speedKmh?: number | null;
  driverStatus: string;
  recordedAt: string;
}

export interface BookingStatusChangedEvent {
  bookingId: number;
  bookingCode: string;
  status: string;
  finalPrice?: number | null;
  pickupFee: number;
  waitingFee: number;
  extraDistanceFee: number;
}

export type TrackingStatus = 'connecting' | 'connected' | 'reconnecting' | 'disconnected';

let connection: signalR.HubConnection | null = null;
let status: TrackingStatus = 'disconnected';
let refCount = 0;
let retryTimer: ReturnType<typeof setTimeout> | null = null;
const statusListeners = new Set<(s: TrackingStatus) => void>();

function setStatus(s: TrackingStatus) {
  status = s;
  statusListeners.forEach((l) => l(s));
}

async function joinAdmin() {
  try {
    await connection?.invoke('JoinAdmin');
  } catch (e) {
    console.warn('[tracking] JoinAdmin failed', e);
  }
}

function build(): signalR.HubConnection {
  const conn = new signalR.HubConnectionBuilder()
    .withUrl(HUB_URL, { accessTokenFactory: () => api.getToken() })
    .withAutomaticReconnect([0, 2000, 5000, 10000, 15000, 30000])
    .configureLogging(signalR.LogLevel.Warning)
    .build();
  // Ignore events from a connection that has since been replaced (e.g. StrictMode remount).
  conn.onreconnecting(() => { if (conn === connection) setStatus('reconnecting'); });
  conn.onreconnected(async () => {
    if (conn !== connection) return;
    setStatus('connected');
    await joinAdmin();
  });
  conn.onclose(() => {
    if (conn !== connection) return;
    setStatus('disconnected');
    scheduleRetry();
  });
  return conn;
}

function scheduleRetry() {
  if (refCount <= 0 || retryTimer) return;
  retryTimer = setTimeout(() => {
    retryTimer = null;
    void start();
  }, 15000);
}

async function start() {
  if (!connection) connection = build();
  const conn = connection;
  if (conn.state !== signalR.HubConnectionState.Disconnected) return;
  setStatus('connecting');
  try {
    await conn.start();
    if (conn !== connection) return;
    setStatus('connected');
    await joinAdmin();
  } catch (e) {
    if (conn !== connection) return;
    console.warn('[tracking] connect failed', e);
    setStatus('disconnected');
    scheduleRetry();
  }
}

/** Acquire the shared connection (ref-counted). Returns a release function. */
export function acquireTracking(): () => void {
  refCount++;
  void start();
  return () => {
    refCount--;
    if (refCount <= 0) {
      refCount = 0;
      if (retryTimer) { clearTimeout(retryTimer); retryTimer = null; }
      const c = connection;
      connection = null;
      if (c) void c.stop().catch(() => undefined);
      setStatus('disconnected');
    }
  };
}

function subscribe<T>(event: string, handler: (payload: T) => void): () => void {
  // Handlers are attached to the current connection instance; acquireTracking() must be called first.
  if (!connection) connection = build();
  const conn = connection;
  conn.on(event, handler);
  return () => conn.off(event, handler);
}

export const onDriverLocation = (h: (e: DriverLocationEvent) => void) => subscribe('DriverLocation', h);
export const onBookingStatusChanged = (h: (e: BookingStatusChangedEvent) => void) =>
  subscribe('BookingStatusChanged', h);

export function getTrackingStatus(): TrackingStatus {
  return status;
}

export function onTrackingStatus(l: (s: TrackingStatus) => void): () => void {
  statusListeners.add(l);
  return () => { statusListeners.delete(l); };
}

/** React hook: current realtime connection status. */
export function useTrackingStatus(): TrackingStatus {
  const [s, setS] = useState<TrackingStatus>(status);
  useEffect(() => onTrackingStatus(setS), []);
  return s;
}
