/* =========================================================
   005 - Hồ sơ tài xế đầy đủ: cá nhân + CCCD, GPLX, liên hệ khẩn cấp,
         tài khoản nhận tiền, ảnh giấy tờ 2 mặt, cờ "cần duyệt lại".
   Idempotent: safe to run multiple times.
   sqlcmd -S localhost -d DrivoDB -E -C -i drivo-api/sql/005_driver_profile.sql
   ========================================================= */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------- Drivers: thông tin cá nhân ---------- */
IF COL_LENGTH('dbo.Drivers', 'DateOfBirth') IS NULL ALTER TABLE dbo.Drivers ADD DateOfBirth DATE NULL;
GO
IF COL_LENGTH('dbo.Drivers', 'Gender') IS NULL
    ALTER TABLE dbo.Drivers ADD Gender VARCHAR(10) NULL
        CONSTRAINT CK_Drivers_Gender CHECK (Gender IS NULL OR Gender IN ('MALE', 'FEMALE', 'OTHER'));
GO
IF COL_LENGTH('dbo.Drivers', 'Address') IS NULL ALTER TABLE dbo.Drivers ADD Address NVARCHAR(300) NULL;
GO
IF COL_LENGTH('dbo.Drivers', 'IdCardNumber') IS NULL ALTER TABLE dbo.Drivers ADD IdCardNumber VARCHAR(20) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Drivers_IdCardNumber' AND object_id = OBJECT_ID('dbo.Drivers'))
    CREATE UNIQUE INDEX UX_Drivers_IdCardNumber ON dbo.Drivers (IdCardNumber) WHERE IdCardNumber IS NOT NULL;
GO

/* ---------- Drivers: GPLX ---------- */
IF COL_LENGTH('dbo.Drivers', 'LicenseExpiryDate') IS NULL ALTER TABLE dbo.Drivers ADD LicenseExpiryDate DATE NULL;
GO
IF COL_LENGTH('dbo.Drivers', 'DrivingExperienceYears') IS NULL
    ALTER TABLE dbo.Drivers ADD DrivingExperienceYears INT NULL
        CONSTRAINT CK_Drivers_Experience CHECK (DrivingExperienceYears IS NULL OR DrivingExperienceYears BETWEEN 0 AND 70);
GO

/* ---------- Drivers: liên hệ khẩn cấp ---------- */
IF COL_LENGTH('dbo.Drivers', 'EmergencyContactName') IS NULL ALTER TABLE dbo.Drivers ADD EmergencyContactName NVARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.Drivers', 'EmergencyContactPhone') IS NULL ALTER TABLE dbo.Drivers ADD EmergencyContactPhone VARCHAR(20) NULL;
GO
IF COL_LENGTH('dbo.Drivers', 'EmergencyContactRelation') IS NULL ALTER TABLE dbo.Drivers ADD EmergencyContactRelation NVARCHAR(50) NULL;
GO

/* ---------- Drivers: tài khoản nhận tiền ---------- */
IF COL_LENGTH('dbo.Drivers', 'BankName') IS NULL ALTER TABLE dbo.Drivers ADD BankName NVARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.Drivers', 'BankAccountNumber') IS NULL ALTER TABLE dbo.Drivers ADD BankAccountNumber VARCHAR(30) NULL;
GO
IF COL_LENGTH('dbo.Drivers', 'BankAccountHolder') IS NULL ALTER TABLE dbo.Drivers ADD BankAccountHolder NVARCHAR(100) NULL;
GO

/* ---------- Drivers: tài xế đã duyệt sửa thông tin quan trọng -> admin cần xem lại ---------- */
IF COL_LENGTH('dbo.Drivers', 'ProfileReviewPending') IS NULL
    ALTER TABLE dbo.Drivers ADD ProfileReviewPending BIT NOT NULL
        CONSTRAINT DF_Drivers_ProfileReviewPending DEFAULT (0);
GO
IF COL_LENGTH('dbo.Drivers', 'ProfileUpdatedAt') IS NULL ALTER TABLE dbo.Drivers ADD ProfileUpdatedAt DATETIME2(3) NULL;
GO

/* ---------- DriverDocuments: ảnh 2 mặt GPLX / CCCD ---------- */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_DriverDocuments_Type'
           AND definition NOT LIKE '%CCCD_FRONT%')
    ALTER TABLE dbo.DriverDocuments DROP CONSTRAINT CK_DriverDocuments_Type;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_DriverDocuments_Type')
    ALTER TABLE dbo.DriverDocuments ADD CONSTRAINT CK_DriverDocuments_Type CHECK (DocumentType IN (
        'DRIVER_LICENSE_FRONT', 'DRIVER_LICENSE_BACK', 'CCCD_FRONT', 'CCCD_BACK', 'PROFILE_PHOTO',
        'DRIVER_LICENSE', 'CCCD', 'OTHER'));
GO

/* LicenseNumber cũ dạng tạm 'PENDING_<userId>_<ticks>' (tài xế tự đăng ký) -> giữ nguyên để không vỡ UNIQUE,
   API trả về rỗng cho các giá trị này. */

PRINT N'005_driver_profile applied.';
GO
