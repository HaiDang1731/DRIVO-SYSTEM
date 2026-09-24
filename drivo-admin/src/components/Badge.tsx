import React from 'react';

interface BadgeProps {
  value?: string;
  type?: 'success' | 'danger' | 'warning' | 'info' | string;
  children?: React.ReactNode;
}

export function Badge({ value, type, children }: BadgeProps) {
  let color = '#3a3a3c', bg = '#1c1c1e';

  if (type) {
    switch (type) {
      case 'success': color = '#00D4AA'; bg = 'rgba(0, 212, 170, 0.15)'; break;
      case 'warning': color = '#FFA502'; bg = 'rgba(255, 165, 2, 0.15)'; break;
      case 'danger': color = '#FF4757'; bg = 'rgba(255, 71, 87, 0.15)'; break;
      case 'info': color = '#00A8FF'; bg = 'rgba(0, 168, 255, 0.15)'; break;
    }
  } else if (value) {
    switch (value) {
      case 'Pending': color = '#FFA502'; bg = 'rgba(255, 165, 2, 0.15)'; break;
      case 'Approved': case 'Active': color = '#00D4AA'; bg = 'rgba(0, 212, 170, 0.15)'; break;
      case 'Rejected': case 'Locked': color = '#FF4757'; bg = 'rgba(255, 71, 87, 0.15)'; break;
    }
  }
  
  return <span className="badge" style={{ color, background: bg }}>{children || value}</span>;
}
