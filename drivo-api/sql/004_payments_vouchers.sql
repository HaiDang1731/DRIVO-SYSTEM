/* =========================================================
   004 - Phương thức thanh toán + voucher trên Bookings,
         tạo Payments cho chuyến đã hoàn thành,
         sửa làm tròn hoa hồng của dữ liệu backfill ở 003.
   Idempotent: safe to run multiple times.
   sqlcmd -S localhost -d DrivoDB -E -C -i drivo-api/sql/004_payments_vouchers.sql
   ========================================================= */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------- Bookings: phương thức thanh toán + voucher đã áp ---------- */
IF COL_LENGTH('dbo.Bookings', 'PaymentMethod') IS NULL
    ALTER TABLE dbo.Bookings ADD PaymentMethod VARCHAR(30) NOT NULL
        CONSTRAINT DF_Bookings_PaymentMethod DEFAULT ('CASH')
        CONSTRAINT CK_Bookings_PaymentMethod CHECK (PaymentMethod IN ('CASH', 'MOCK_BANKING', 'MOCK_EWALLET'));
GO
IF COL_LENGTH('dbo.Bookings', 'VoucherId') IS NULL
    ALTER TABLE dbo.Bookings ADD VoucherId INT NULL
        CONSTRAINT FK_Bookings_Vouchers FOREIGN KEY REFERENCES dbo.Vouchers(Id);
GO
IF COL_LENGTH('dbo.Bookings', 'VoucherCode') IS NULL
    ALTER TABLE dbo.Bookings ADD VoucherCode NVARCHAR(50) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Bookings_Customer_Voucher' AND object_id = OBJECT_ID('dbo.Bookings'))
    CREATE INDEX IX_Bookings_Customer_Voucher ON dbo.Bookings (CustomerId, VoucherId) WHERE VoucherId IS NOT NULL;
GO

/* ---------- Sửa làm tròn hoa hồng (003 làm tròn tới đồng, code làm tròn tới 1.000đ) ---------- */
;WITH Fix AS (
    SELECT b.Id,
           ROUND(b.FinalPrice * COALESCE(pr.CommissionPercent, 15) / 100.0 / 1000.0, 0) * 1000 AS Commission,
           b.FinalPrice
    FROM dbo.Bookings b
    LEFT JOIN dbo.PricingRules pr ON pr.Id = b.PricingRuleId
    WHERE b.Status = 'COMPLETED' AND b.FinalPrice IS NOT NULL
      AND CAST(b.CommissionAmount AS DECIMAL(18,2)) % 1000 <> 0
)
UPDATE b
SET b.CommissionAmount = f.Commission,
    b.DriverPayout = f.FinalPrice - f.Commission
FROM dbo.Bookings b
JOIN Fix f ON f.Id = b.Id;

UPDATE d
SET d.TotalEarnings = COALESCE(p.Total, 0)
FROM dbo.Drivers d
OUTER APPLY (
    SELECT SUM(b.DriverPayout) AS Total
    FROM dbo.Bookings b
    WHERE b.DriverId = d.Id AND b.Status = 'COMPLETED'
) p;
GO

/* ---------- Payments cho các chuyến đã hoàn thành trước khi có bản ghi thanh toán ---------- */
INSERT INTO dbo.Payments (TripId, CustomerId, Amount, Currency, PaymentMethod, PaymentStatus, PaidAt, CreatedAt)
SELECT t.Id, b.CustomerId, b.FinalPrice, 'VND', b.PaymentMethod, 'SUCCESS',
       COALESCE(b.CompletedAt, t.EndTime, t.CreatedAt), COALESCE(b.CompletedAt, t.EndTime, t.CreatedAt)
FROM dbo.Trips t
JOIN dbo.Bookings b ON b.Id = t.BookingId
WHERE b.Status = 'COMPLETED' AND b.FinalPrice IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.Payments p WHERE p.TripId = t.Id);

INSERT INTO dbo.PaymentTransactions (PaymentId, TransactionCode, TransactionType, Amount, Status, Provider, CreatedAt, CompletedAt)
SELECT p.Id, 'PAY-' + b.BookingCode, 'CHARGE', p.Amount, 'SUCCESS',
       CASE WHEN p.PaymentMethod = 'CASH' THEN 'CASH' ELSE 'MOCK' END, p.CreatedAt, p.PaidAt
FROM dbo.Payments p
JOIN dbo.Trips t ON t.Id = p.TripId
JOIN dbo.Bookings b ON b.Id = t.BookingId
WHERE NOT EXISTS (SELECT 1 FROM dbo.PaymentTransactions x WHERE x.PaymentId = p.Id);
GO

PRINT N'004_payments_vouchers applied.';
GO
