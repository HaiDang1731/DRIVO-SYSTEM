import { useState } from 'react';
import { apiFileUrl } from '../services/api';

/** Ảnh đại diện; không có ảnh (hoặc ảnh lỗi) thì hiện chữ cái đầu của tên. */
export function Avatar({ name, src, size }: { name: string; src?: string | null; size?: number }) {
  const [broken, setBroken] = useState(false);
  const initial = name ? name.trim().split(' ').pop()!.charAt(0).toUpperCase() : '?';
  const sizeStyle = size ? { width: size, height: size, fontSize: Math.round(size * 0.4) } : undefined;
  if (src && !broken) {
    return (
      <div className="avatar" style={{ ...sizeStyle, padding: 0, overflow: 'hidden' }}>
        <img src={apiFileUrl(src)} alt={name} onError={() => setBroken(true)}
          style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
      </div>
    );
  }
  return <div className="avatar" style={sizeStyle}>{initial}</div>;
}
