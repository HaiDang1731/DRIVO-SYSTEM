/* =========================================================
   007 - Đặt mật khẩu mặc định cho tài khoản admin do DRIVO_Database_V2.sql tạo sẵn.
   V2 chỉ ghi chuỗi giữ chỗ 'REPLACE_WITH_ASPNET_PASSWORD_HASH' nên không đăng nhập được.
   Chỉ cập nhật khi vẫn là chuỗi giữ chỗ (không đè mật khẩu đã đổi).

   Tài khoản: admin@drivo.local  /  Admin@123   (ĐỔI NGAY sau khi đăng nhập lần đầu)
   Hash: PBKDF2-SHA256, 350.000 vòng, định dạng "vòng.salt.hash" như AuthService.
   Idempotent: safe to run multiple times.
   ========================================================= */
SET NOCOUNT ON;
GO

UPDATE dbo.Users
SET PasswordHash = N'350000.sWVe1J+/d6BlrOPdpFJK7A==.Gq/425o4HoIJPMyiFE9Pj+yI/eTkkienzsvMm2vnFaw=',
    UpdatedAt = SYSUTCDATETIME()
WHERE Email = 'admin@drivo.local'
  AND PasswordHash = N'REPLACE_WITH_ASPNET_PASSWORD_HASH';
GO

PRINT N'007_seed_admin_password applied.';
GO
