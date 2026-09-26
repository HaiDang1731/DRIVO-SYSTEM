/* =========================================================
   001 - Bảng mã khuyến mãi (Vouchers) + 3 mã mẫu cho demo.
   Chạy SAU DRIVO_Database_V2.sql và TRƯỚC 004 (004 tham chiếu Vouchers).
   Idempotent: safe to run multiple times.
   sqlcmd -S localhost -d DrivoDB -E -C -i drivo-api/sql/001_vouchers.sql
   ========================================================= */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.Vouchers', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Vouchers (
        Id                INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Vouchers PRIMARY KEY,
        Code              NVARCHAR(50)   NOT NULL CONSTRAINT UQ_Vouchers_Code UNIQUE,
        Title             NVARCHAR(200)  NOT NULL,
        Description       NVARCHAR(500)  NULL,
        /* PERCENT | FIXED */
        DiscountType      NVARCHAR(20)   NOT NULL CONSTRAINT DF_Vouchers_DiscountType DEFAULT ('PERCENT'),
        DiscountValue     DECIMAL(18,2)  NOT NULL,
        MaxDiscountAmount DECIMAL(18,2)  NULL,
        MinOrderAmount    DECIMAL(18,2)  NOT NULL CONSTRAINT DF_Vouchers_MinOrderAmount DEFAULT (0),
        UsageLimit        INT            NOT NULL CONSTRAINT DF_Vouchers_UsageLimit DEFAULT (100),
        UsedCount         INT            NOT NULL CONSTRAINT DF_Vouchers_UsedCount DEFAULT (0),
        IsActive          BIT            NOT NULL CONSTRAINT DF_Vouchers_IsActive DEFAULT (1),
        StartDate         DATETIME2      NOT NULL,
        EndDate           DATETIME2      NOT NULL,
        CreatedAt         DATETIME2      NOT NULL CONSTRAINT DF_Vouchers_CreatedAt DEFAULT (GETUTCDATE())
    );
END
GO

/* Mã mẫu để demo (chỉ thêm khi bảng còn trống) */
IF NOT EXISTS (SELECT 1 FROM dbo.Vouchers)
BEGIN
    INSERT INTO dbo.Vouchers (Code, Title, Description, DiscountType, DiscountValue, MaxDiscountAmount, MinOrderAmount, UsageLimit, StartDate, EndDate)
    VALUES
        (N'DRIVOXINCHAO', N'Giảm 20% chuyến đi đầu tiên', N'Khuyến mãi chào đón khách hàng mới của DRIVO',
         N'PERCENT', 20, 50000, 50000, 500, SYSUTCDATETIME(), DATEADD(MONTH, 3, SYSUTCDATETIME())),
        (N'DRIVOVIP', N'Giảm trực tiếp 30.000đ', N'Tri ân khách hàng thân thiết',
         N'FIXED', 30000, 30000, 100000, 200, SYSUTCDATETIME(), DATEADD(MONTH, 3, SYSUTCDATETIME())),
        (N'DRIVO102', N'Giảm 10k tất cả các chuyến', NULL,
         N'FIXED', 10000, 10000, 0, 100, SYSUTCDATETIME(), DATEADD(MONTH, 3, SYSUTCDATETIME()));
END
GO

PRINT N'001_vouchers applied.';
GO
