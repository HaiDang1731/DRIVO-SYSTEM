export function Avatar({ name }: { name: string }) {
  const initial = name ? name.charAt(0).toUpperCase() : '?';
  return <div className="avatar">{initial}</div>;
}
