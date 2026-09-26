/* =========================================================
   006 - Ví tài xế (ký quỹ tối thiểu, nạp/rút qua admin duyệt, tự cấn trừ theo chuyến)
   Idempotent: safe to run multiple times.
   sqlcmd -S localhost -d DrivoDB -E -C -i drivo-api/sql/006_driver_wallet.sql
   ========================================================= */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.Drivers', 'WalletBalance') IS NULL
    ALTER TABLE dbo.Drivers ADD WalletBalance DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_Drivers_WalletBalance DEFAULT (0);
GO

IF OBJECT_ID('dbo.DriverWalletTransactions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DriverWalletTransactions (
        Id              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DriverWalletTransactions PRIMARY KEY,
        DriverId        INT            NOT NULL CONSTRAINT FK_DriverWalletTransactions_Drivers REFERENCES dbo.Drivers(Id),
        /* TOPUP | WITHDRAW | TRIP_CASH | TRIP_APP | ADJUSTMENT */
        [Type]          VARCHAR(20)    NOT NULL,
        /* Có dấu: + cộng vào ví, - trừ khỏi ví */
        Amount          DECIMAL(18,2)  NOT NULL,
        BalanceAfter    DECIMAL(18,2)  NULL,
        /* PENDING | COMPLETED | REJECTED */
        [Status]        VARCHAR(20)    NOT NULL,
        BookingId       BIGINT         NULL CONSTRAINT FK_DriverWalletTransactions_Bookings REFERENCES dbo.Bookings(Id),
        ReferenceCode   VARCHAR(30)    NULL,
        Note            NVARCHAR(500)  NULL,
        CreatedAt       DATETIME2(3)   NOT NULL,
        ProcessedAt     DATETIME2(3)   NULL,
        ProcessedBy     INT            NULL,
        CONSTRAINT CK_DriverWalletTransactions_Type CHECK ([Type] IN ('TOPUP','WITHDRAW','TRIP_CASH','TRIP_APP','ADJUSTMENT')),
        CONSTRAINT CK_DriverWalletTransactions_Status CHECK ([Status] IN ('PENDING','COMPLETED','REJECTED'))
    );
    CREATE INDEX IX_DriverWalletTransactions_Driver_Created ON dbo.DriverWalletTransactions (DriverId, CreatedAt DESC);
    CREATE INDEX IX_DriverWalletTransactions_Status ON dbo.DriverWalletTransactions ([Status]) WHERE [Status] = 'PENDING';
    CREATE UNIQUE INDEX UX_DriverWalletTransactions_Reference ON dbo.DriverWalletTransactions (ReferenceCode) WHERE ReferenceCode IS NOT NULL;
    /* 1 chuyến chỉ cấn trừ 1 lần */
    CREATE UNIQUE INDEX UX_DriverWalletTransactions_Booking ON dbo.DriverWalletTransactions (BookingId) WHERE BookingId IS NOT NULL;
END
GO

PRINT N'006_driver_wallet applied.';
GO
