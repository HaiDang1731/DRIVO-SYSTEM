import { useEffect } from 'react';

export function Toast({ msg, type, onClose }: { msg: string; type: 'success' | 'error'; onClose: () => void }) {
  useEffect(() => { const timer = setTimeout(onClose, 3000); return () => clearTimeout(timer); }, [onClose]);
  const isSuccess = type === 'success';
  return (
    <div className={`toast ${isSuccess ? 'toast-success' : 'toast-error'}`}>
      <span style={{ fontSize: 18 }}>{isSuccess ? '✅' : '❌'}</span>
      <span style={{ fontWeight: 500 }}>{msg}</span>
    </div>
  );
}
