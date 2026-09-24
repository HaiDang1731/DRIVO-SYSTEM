/* =========================================================
   003 - Chia doanh thu nền tảng / tài xế (hoa hồng theo loại xe)
   Idempotent: safe to run multiple times.
   sqlcmd -S localhost -d DrivoDB -E -C -i drivo-api/sql/003_commission.sql
   ========================================================= */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------- PricingRules: % nền tảng giữ lại, cấu hình riêng theo từng loại xe ---------- */
IF COL_LENGTH('dbo.PricingRules', 'CommissionPercent') IS NULL
    ALTER TABLE dbo.PricingRules ADD CommissionPercent DECIMAL(5,2) NOT NULL
        CONSTRAINT DF_PricingRules_CommissionPercent DEFAULT (15);
GO

/* ---------- Bookings: chốt số tiền hoa hồng + thu nhập tài xế cùng lúc với FinalPrice ---------- */
IF COL_LENGTH('dbo.Bookings', 'CommissionAmount') IS NULL
    ALTER TABLE dbo.Bookings ADD CommissionAmount DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_Bookings_CommissionAmount DEFAULT (0);
GO
IF COL_LENGTH('dbo.Bookings', 'DriverPayout') IS NULL
    ALTER TABLE dbo.Bookings ADD DriverPayout DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_Bookings_DriverPayout DEFAULT (0);
GO

/* ---------- Backfill các chuyến đã Completed trước khi có cột này ----------
   Trước đây driver.TotalEarnings được cộng dồn = 100% FinalPrice (không trừ hoa hồng).
   Ở đây: tính lại CommissionAmount/DriverPayout cho từng booking theo % của bảng giá
   đã áp dụng cho booking đó (PricingRuleId), mặc định 15% nếu không xác định được,
   rồi đưa Driver.TotalEarnings về đúng tổng DriverPayout (không cộng dồn thêm 1 lần nữa). */
IF EXISTS (SELECT 1 FROM dbo.Bookings WHERE Status = 'COMPLETED' AND FinalPrice IS NOT NULL AND CommissionAmount = 0 AND DriverPayout = 0)
BEGIN
    ;WITH BookingCommission AS (
        SELECT b.Id,
               b.FinalPrice,
               COALESCE(pr.CommissionPercent, 15) AS CommissionPercent
        FROM dbo.Bookings b
        LEFT JOIN dbo.PricingRules pr ON pr.Id = b.PricingRuleId
        WHERE b.Status = 'COMPLETED' AND b.FinalPrice IS NOT NULL
          AND b.CommissionAmount = 0 AND b.DriverPayout = 0
    )
    UPDATE b
    SET b.CommissionAmount = ROUND(bc.FinalPrice * bc.CommissionPercent / 100.0, 0),
        b.DriverPayout = bc.FinalPrice - ROUND(bc.FinalPrice * bc.CommissionPercent / 100.0, 0)
    FROM dbo.Bookings b
    JOIN BookingCommission bc ON bc.Id = b.Id;

    UPDATE d
    SET d.TotalEarnings = COALESCE(payout.Total, 0)
    FROM dbo.Drivers d
    OUTER APPLY (
        SELECT SUM(b.DriverPayout) AS Total
        FROM dbo.Bookings b
        WHERE b.DriverId = d.Id AND b.Status = 'COMPLETED'
    ) payout;
END
GO

PRINT N'003_commission applied.';
GO
