/* =========================================================
   008 - Hủy chuyến có lý do + lỗi thuộc về ai, tài xế xác nhận tiếp tục chờ khách
   Idempotent: safe to run multiple times.
   sqlcmd -S localhost -d DrivoDB -E -C -i drivo-api/sql/008_cancel_fault_waiting.sql
   ========================================================= */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* 1 = lần hủy tính lỗi tài xế (trừ tỉ lệ hoàn thành). Khách vắng mặt / khách tự hủy = 0. */
IF COL_LENGTH('dbo.Bookings', 'DriverAtFault') IS NULL
BEGIN
    ALTER TABLE dbo.Bookings ADD DriverAtFault BIT NOT NULL
        CONSTRAINT DF_Bookings_DriverAtFault DEFAULT (0);
    EXEC('UPDATE dbo.Bookings SET DriverAtFault = 1 WHERE Status = ''CANCELLED'' AND CancelledBy = ''DRIVER''');
END
GO

/* Thời điểm tài xế xác nhận "khách vẫn đi, tiếp tục chờ" (sau thời gian chờ miễn phí). */
IF COL_LENGTH('dbo.Bookings', 'WaitExtendedAt') IS NULL
    ALTER TABLE dbo.Bookings ADD WaitExtendedAt DATETIME2 NULL;
GO
