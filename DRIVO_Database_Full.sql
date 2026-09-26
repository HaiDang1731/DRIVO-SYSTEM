/* =========================================================
   DRIVO - toàn bộ database trong 1 file. Tự sinh bởi: .\setup-db.ps1 -ExportTo <file>
   Đừng sửa tay file này: sửa DRIVO_Database_V2.sql / drivo-api/sql/00x_*.sql rồi xuất lại.
   Gồm: DRIVO_Database_V2.sql, 001_vouchers.sql, 002_maps_tracking_pricing.sql, 003_commission.sql, 004_payments_vouchers.sql, 005_driver_profile.sql, 006_driver_wallet.sql, 007_seed_admin_password.sql, 008_cancel_fault_waiting.sql
   Chạy: mở bằng SQL Server Management Studio rồi bấm Execute, hoặc
         sqlcmd -S localhost -E -C -I -f 65001 -i DRIVO_Database_Full.sql
   Chạy lại nhiều lần vẫn an toàn, không xóa dữ liệu.
   ========================================================= */

/* ======================= DRIVO_Database_V2.sql ======================= */
/*
===========================================================
DRIVO DATABASE V2
SQL Server / ASP.NET Core .NET 9 / EF Core
Product-ready foundation
===========================================================

20 TABLES
01 Users
02 Roles
03 UserRoles
04 RefreshTokens
05 Customers
06 CustomerVehicles
07 Drivers
08 DriverDocuments
09 DriverStatusHistory
10 DriverLocationHistory
11 Bookings
12 BookingDriverOffers
13 BookingStatusHistory
14 Trips
15 Payments
16 PaymentTransactions
17 Ratings
18 PricingRules
19 Notifications
20 AuditLogs

Design principles:
- DRIVO hires a driver to drive the customer's own vehicle.
- All timestamps are UTC and use DATETIME2(3).
- Money uses DECIMAL(18,2).
- GPS coordinates use DECIMAL(10,7).
- Booking stores pricing snapshots so historical prices never change.
- SignalR handles realtime transport; SQL Server persists important GPS data.
- Roles/UserRoles provide extensible RBAC without hard-coding role into Users.
- Payment and PaymentTransactions are separated for future retry/refund/provider flows.
- BookingDriverOffers supports repeated matching rounds through OfferRound.
- AuditLogs is system-level audit; BookingStatusHistory is business-level audit.

NOTE:
- This script is designed to be safe to execute repeatedly.
- EF Core migrations should be the preferred schema-management mechanism
  once the ASP.NET Core project is established.
- Admin password hash is intentionally a placeholder. Never store plaintext.
===========================================================
*/

IF DB_ID(N'DrivoDB') IS NULL
BEGIN
    CREATE DATABASE DrivoDB;
END
GO

USE DrivoDB;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* =========================================================
   01. USERS
   ========================================================= */
IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users
    (
        Id              INT IDENTITY(1,1) NOT NULL,
        FullName        NVARCHAR(150) NOT NULL,
        Phone           VARCHAR(20) NOT NULL,
        Email           VARCHAR(255) NULL,
        PasswordHash    NVARCHAR(500) NOT NULL,
        Status          VARCHAR(20) NOT NULL CONSTRAINT DF_Users_Status DEFAULT ('ACTIVE'),
        AvatarUrl       NVARCHAR(1000) NULL,
        LastLoginAt     DATETIME2(3) NULL,
        CreatedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt       DATETIME2(3) NULL,
        IsDeleted       BIT NOT NULL CONSTRAINT DF_Users_IsDeleted DEFAULT (0),

        CONSTRAINT PK_Users PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Users_Phone UNIQUE (Phone),
        CONSTRAINT CK_Users_Status CHECK (Status IN ('ACTIVE','INACTIVE','LOCKED','PENDING'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'UX_Users_Email' AND object_id=OBJECT_ID(N'dbo.Users'))
BEGIN
    CREATE UNIQUE INDEX UX_Users_Email ON dbo.Users(Email) WHERE Email IS NOT NULL;
END
GO

/* =========================================================
   02. ROLES
   ========================================================= */
IF OBJECT_ID(N'dbo.Roles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Roles
    (
        Id              INT IDENTITY(1,1) NOT NULL,
        Name            VARCHAR(50) NOT NULL,
        Description     NVARCHAR(255) NULL,
        IsActive        BIT NOT NULL CONSTRAINT DF_Roles_IsActive DEFAULT (1),
        CreatedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_Roles_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Roles PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Roles_Name UNIQUE (Name)
    );
END
GO

/* =========================================================
   03. USER ROLES
   ========================================================= */
IF OBJECT_ID(N'dbo.UserRoles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserRoles
    (
        UserId          INT NOT NULL,
        RoleId          INT NOT NULL,
        AssignedAt      DATETIME2(3) NOT NULL CONSTRAINT DF_UserRoles_AssignedAt DEFAULT (SYSUTCDATETIME()),
        AssignedBy      INT NULL,

        CONSTRAINT PK_UserRoles PRIMARY KEY CLUSTERED (UserId, RoleId)
    );
END
GO

/* =========================================================
   04. REFRESH TOKENS
   Store only a hash of the refresh token.
   ========================================================= */
IF OBJECT_ID(N'dbo.RefreshTokens', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RefreshTokens
    (
        Id                  BIGINT IDENTITY(1,1) NOT NULL,
        UserId              INT NOT NULL,
        TokenHash           VARCHAR(500) NOT NULL,
        ExpiresAt           DATETIME2(3) NOT NULL,
        CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_RefreshTokens_CreatedAt DEFAULT (SYSUTCDATETIME()),
        RevokedAt           DATETIME2(3) NULL,
        ReplacedByTokenId   BIGINT NULL,

        CONSTRAINT PK_RefreshTokens PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_RefreshTokens_TokenHash UNIQUE (TokenHash),
        CONSTRAINT CK_RefreshTokens_Expiry CHECK (ExpiresAt > CreatedAt OR RevokedAt IS NOT NULL)
    );
END
GO

/* =========================================================
   05. CUSTOMERS
   ========================================================= */
IF OBJECT_ID(N'dbo.Customers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Customers
    (
        Id              INT IDENTITY(1,1) NOT NULL,
        UserId          INT NOT NULL,
        DateOfBirth     DATE NULL,
        Gender          VARCHAR(20) NULL,
        EmergencyName   NVARCHAR(150) NULL,
        EmergencyPhone  VARCHAR(20) NULL,
        CreatedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt       DATETIME2(3) NULL,

        CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Customers_UserId UNIQUE (UserId),
        CONSTRAINT CK_Customers_Gender CHECK (Gender IS NULL OR Gender IN ('MALE','FEMALE','OTHER'))
    );
END
GO

/* =========================================================
   06. CUSTOMER VEHICLES
   DRIVO's core domain: driver drives this vehicle.
   ========================================================= */
IF OBJECT_ID(N'dbo.CustomerVehicles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CustomerVehicles
    (
        Id              INT IDENTITY(1,1) NOT NULL,
        CustomerId      INT NOT NULL,
        VehicleType     VARCHAR(20) NOT NULL,
        Transmission    VARCHAR(20) NOT NULL,
        Brand           NVARCHAR(100) NULL,
        Model           NVARCHAR(100) NULL,
        Color           NVARCHAR(50) NULL,
        LicensePlate    VARCHAR(20) NOT NULL,
        ProductionYear  SMALLINT NULL,
        IsDefault       BIT NOT NULL CONSTRAINT DF_CustomerVehicles_IsDefault DEFAULT (0),
        IsActive        BIT NOT NULL CONSTRAINT DF_CustomerVehicles_IsActive DEFAULT (1),
        CreatedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_CustomerVehicles_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt       DATETIME2(3) NULL,

        CONSTRAINT PK_CustomerVehicles PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_CustomerVehicles_LicensePlate UNIQUE (LicensePlate),
        CONSTRAINT CK_CustomerVehicles_Type CHECK (VehicleType IN ('MOTORBIKE','CAR','SUV','TRUCK','OTHER')),
        CONSTRAINT CK_CustomerVehicles_Transmission CHECK (Transmission IN ('MANUAL','AUTOMATIC','OTHER')),
        CONSTRAINT CK_CustomerVehicles_ProductionYear CHECK (ProductionYear IS NULL OR ProductionYear BETWEEN 1900 AND 2100)
    );
END
GO

/* =========================================================
   07. DRIVERS
   Current state + current GPS snapshot for fast matching.
   ========================================================= */
IF OBJECT_ID(N'dbo.Drivers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Drivers
    (
        Id                  INT IDENTITY(1,1) NOT NULL,
        UserId              INT NOT NULL,
        LicenseNumber       VARCHAR(50) NOT NULL,
        LicenseClass        VARCHAR(30) NULL,
        VerificationStatus  VARCHAR(20) NOT NULL CONSTRAINT DF_Drivers_VerificationStatus DEFAULT ('PENDING'),
        DriverStatus        VARCHAR(20) NOT NULL CONSTRAINT DF_Drivers_DriverStatus DEFAULT ('OFFLINE'),
        RatingAverage       DECIMAL(3,2) NOT NULL CONSTRAINT DF_Drivers_RatingAverage DEFAULT (0),
        RatingCount         INT NOT NULL CONSTRAINT DF_Drivers_RatingCount DEFAULT (0),
        TotalTrips          INT NOT NULL CONSTRAINT DF_Drivers_TotalTrips DEFAULT (0),
        TotalEarnings       DECIMAL(18,2) NOT NULL CONSTRAINT DF_Drivers_TotalEarnings DEFAULT (0),
        CurrentLatitude     DECIMAL(10,7) NULL,
        CurrentLongitude    DECIMAL(10,7) NULL,
        LastLocationAt      DATETIME2(3) NULL,
        CreatedAt            DATETIME2(3) NOT NULL CONSTRAINT DF_Drivers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2(3) NULL,

        CONSTRAINT PK_Drivers PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Drivers_UserId UNIQUE (UserId),
        CONSTRAINT UQ_Drivers_LicenseNumber UNIQUE (LicenseNumber),
        CONSTRAINT CK_Drivers_VerificationStatus CHECK (VerificationStatus IN ('PENDING','APPROVED','REJECTED','SUSPENDED')),
        CONSTRAINT CK_Drivers_DriverStatus CHECK (DriverStatus IN ('OFFLINE','ONLINE','BUSY','SUSPENDED')),
        CONSTRAINT CK_Drivers_RatingAverage CHECK (RatingAverage >= 0 AND RatingAverage <= 5),
        CONSTRAINT CK_Drivers_RatingCount CHECK (RatingCount >= 0),
        CONSTRAINT CK_Drivers_TotalTrips CHECK (TotalTrips >= 0),
        CONSTRAINT CK_Drivers_TotalEarnings CHECK (TotalEarnings >= 0),
        CONSTRAINT CK_Drivers_Latitude CHECK (CurrentLatitude IS NULL OR CurrentLatitude BETWEEN -90 AND 90),
        CONSTRAINT CK_Drivers_Longitude CHECK (CurrentLongitude IS NULL OR CurrentLongitude BETWEEN -180 AND 180)
    );
END
GO

/* =========================================================
   08. DRIVER DOCUMENTS
   ========================================================= */
IF OBJECT_ID(N'dbo.DriverDocuments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DriverDocuments
    (
        Id                  INT IDENTITY(1,1) NOT NULL,
        DriverId            INT NOT NULL,
        DocumentType        VARCHAR(30) NOT NULL,
        FileUrl             NVARCHAR(1000) NOT NULL,
        VerificationStatus  VARCHAR(20) NOT NULL CONSTRAINT DF_DriverDocuments_Status DEFAULT ('PENDING'),
        RejectionReason     NVARCHAR(500) NULL,
        VerifiedBy          INT NULL,
        VerifiedAt          DATETIME2(3) NULL,
        CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_DriverDocuments_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_DriverDocuments PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_DriverDocuments_Type CHECK (DocumentType IN ('CCCD','DRIVER_LICENSE','PROFILE_PHOTO','OTHER')),
        CONSTRAINT CK_DriverDocuments_Status CHECK (VerificationStatus IN ('PENDING','APPROVED','REJECTED'))
    );
END
GO

/* =========================================================
   09. DRIVER STATUS HISTORY
   ========================================================= */
IF OBJECT_ID(N'dbo.DriverStatusHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DriverStatusHistory
    (
        Id              BIGINT IDENTITY(1,1) NOT NULL,
        DriverId        INT NOT NULL,
        OldStatus       VARCHAR(20) NULL,
        NewStatus       VARCHAR(20) NOT NULL,
        ChangedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_DriverStatusHistory_ChangedAt DEFAULT (SYSUTCDATETIME()),
        Reason          NVARCHAR(500) NULL,

        CONSTRAINT PK_DriverStatusHistory PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_DriverStatusHistory_NewStatus CHECK (NewStatus IN ('OFFLINE','ONLINE','BUSY','SUSPENDED')),
        CONSTRAINT CK_DriverStatusHistory_OldStatus CHECK (OldStatus IS NULL OR OldStatus IN ('OFFLINE','ONLINE','BUSY','SUSPENDED'))
    );
END
GO

/* =========================================================
   10. DRIVER LOCATION HISTORY
   ========================================================= */
IF OBJECT_ID(N'dbo.DriverLocationHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DriverLocationHistory
    (
        Id              BIGINT IDENTITY(1,1) NOT NULL,
        DriverId        INT NOT NULL,
        BookingId       BIGINT NULL,
        Latitude        DECIMAL(10,7) NOT NULL,
        Longitude       DECIMAL(10,7) NOT NULL,
        AccuracyMeters  DECIMAL(8,2) NULL,
        SpeedKmh        DECIMAL(8,2) NULL,
        Heading         DECIMAL(6,2) NULL,
        RecordedAt      DATETIME2(3) NOT NULL CONSTRAINT DF_DriverLocationHistory_RecordedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_DriverLocationHistory PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_DriverLocationHistory_Latitude CHECK (Latitude BETWEEN -90 AND 90),
        CONSTRAINT CK_DriverLocationHistory_Longitude CHECK (Longitude BETWEEN -180 AND 180),
        CONSTRAINT CK_DriverLocationHistory_Accuracy CHECK (AccuracyMeters IS NULL OR AccuracyMeters >= 0),
        CONSTRAINT CK_DriverLocationHistory_Speed CHECK (SpeedKmh IS NULL OR SpeedKmh >= 0),
        CONSTRAINT CK_DriverLocationHistory_Heading CHECK (Heading IS NULL OR Heading BETWEEN 0 AND 360)
    );
END
GO

/* =========================================================
   11. BOOKINGS
   PricingRuleId + price components are a historical snapshot.
   ========================================================= */
IF OBJECT_ID(N'dbo.Bookings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Bookings
    (
        Id                      BIGINT IDENTITY(1,1) NOT NULL,
        BookingCode             VARCHAR(30) NOT NULL,
        CustomerId              INT NOT NULL,
        DriverId                INT NULL,
        CustomerVehicleId       INT NOT NULL,
        PricingRuleId           INT NULL,

        PickupAddress            NVARCHAR(500) NOT NULL,
        PickupLatitude           DECIMAL(10,7) NOT NULL,
        PickupLongitude          DECIMAL(10,7) NOT NULL,
        DestinationAddress       NVARCHAR(500) NOT NULL,
        DestinationLatitude      DECIMAL(10,7) NOT NULL,
        DestinationLongitude     DECIMAL(10,7) NOT NULL,

        VehicleType              VARCHAR(20) NOT NULL,
        Transmission             VARCHAR(20) NOT NULL,

        EstimatedDistanceKm      DECIMAL(10,2) NULL,
        EstimatedDurationMin     INT NULL,

        BaseFare                 DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_BaseFare DEFAULT (0),
        DistanceFare             DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_DistanceFare DEFAULT (0),
        TimeFare                 DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_TimeFare DEFAULT (0),
        Surcharge                DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_Surcharge DEFAULT (0),
        Discount                 DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_Discount DEFAULT (0),
        EstimatedPrice           DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_EstimatedPrice DEFAULT (0),
        FinalPrice               DECIMAL(18,2) NULL,

        PickupDistanceKm         DECIMAL(8,2) NULL,
        PickupFee                DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_PickupFee DEFAULT (0),
        WaitingFee               DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_WaitingFee DEFAULT (0),
        ExtraDistanceFee         DECIMAL(18,2) NOT NULL CONSTRAINT DF_Bookings_ExtraDistanceFee DEFAULT (0),
        ActualDistanceKm         DECIMAL(8,2) NULL,
        RoutePolyline            NVARCHAR(MAX) NULL,
        AcceptedAt               DATETIME2(3) NULL,
        ArrivedAt                DATETIME2(3) NULL,
        StartedAt                DATETIME2(3) NULL,
        CompletedAt              DATETIME2(3) NULL,

        Status                   VARCHAR(30) NOT NULL CONSTRAINT DF_Bookings_Status DEFAULT ('PENDING'),
        CancelledBy              VARCHAR(20) NULL,
        CancellationReason       NVARCHAR(500) NULL,
        CancelledAt              DATETIME2(3) NULL,
        CustomerNote             NVARCHAR(500) NULL,

        CreatedAt                DATETIME2(3) NOT NULL CONSTRAINT DF_Bookings_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                DATETIME2(3) NULL,

        CONSTRAINT PK_Bookings PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Bookings_BookingCode UNIQUE (BookingCode),
        CONSTRAINT CK_Bookings_Status CHECK (Status IN ('PENDING','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ACCEPTED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','CANCELLED')),
        CONSTRAINT CK_Bookings_CancelledBy CHECK (CancelledBy IS NULL OR CancelledBy IN ('CUSTOMER','DRIVER','ADMIN','SYSTEM')),
        CONSTRAINT CK_Bookings_VehicleType CHECK (VehicleType IN ('MOTORBIKE','CAR','SUV','TRUCK','OTHER')),
        CONSTRAINT CK_Bookings_Transmission CHECK (Transmission IN ('MANUAL','AUTOMATIC','OTHER')),
        CONSTRAINT CK_Bookings_PickupLatitude CHECK (PickupLatitude BETWEEN -90 AND 90),
        CONSTRAINT CK_Bookings_PickupLongitude CHECK (PickupLongitude BETWEEN -180 AND 180),
        CONSTRAINT CK_Bookings_DestinationLatitude CHECK (DestinationLatitude BETWEEN -90 AND 90),
        CONSTRAINT CK_Bookings_DestinationLongitude CHECK (DestinationLongitude BETWEEN -180 AND 180),
        CONSTRAINT CK_Bookings_Prices CHECK (BaseFare >= 0 AND DistanceFare >= 0 AND TimeFare >= 0 AND Surcharge >= 0 AND Discount >= 0 AND EstimatedPrice >= 0 AND (FinalPrice IS NULL OR FinalPrice >= 0)),
        CONSTRAINT CK_Bookings_Distance CHECK (EstimatedDistanceKm IS NULL OR EstimatedDistanceKm >= 0),
        CONSTRAINT CK_Bookings_Duration CHECK (EstimatedDurationMin IS NULL OR EstimatedDurationMin >= 0)
    );
END
GO

/* =========================================================
   12. BOOKING DRIVER OFFERS
   OfferRound permits a driver to be offered again in a later round.
   ========================================================= */
IF OBJECT_ID(N'dbo.BookingDriverOffers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BookingDriverOffers
    (
        Id                  BIGINT IDENTITY(1,1) NOT NULL,
        BookingId           BIGINT NOT NULL,
        DriverId            INT NOT NULL,
        OfferRound          INT NOT NULL CONSTRAINT DF_BookingDriverOffers_OfferRound DEFAULT (1),
        DistanceToPickupKm  DECIMAL(10,2) NULL,
        EstimatedArrivalMin INT NULL,
        OfferStatus         VARCHAR(20) NOT NULL CONSTRAINT DF_BookingDriverOffers_Status DEFAULT ('SENT'),
        SentAt              DATETIME2(3) NOT NULL CONSTRAINT DF_BookingDriverOffers_SentAt DEFAULT (SYSUTCDATETIME()),
        RespondedAt         DATETIME2(3) NULL,

        CONSTRAINT PK_BookingDriverOffers PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_BookingDriverOffers_Booking_Driver_Round UNIQUE (BookingId, DriverId, OfferRound),
        CONSTRAINT CK_BookingDriverOffers_Round CHECK (OfferRound >= 1),
        CONSTRAINT CK_BookingDriverOffers_Status CHECK (OfferStatus IN ('SENT','ACCEPTED','REJECTED','EXPIRED','CANCELLED')),
        CONSTRAINT CK_BookingDriverOffers_Distance CHECK (DistanceToPickupKm IS NULL OR DistanceToPickupKm >= 0),
        CONSTRAINT CK_BookingDriverOffers_ETA CHECK (EstimatedArrivalMin IS NULL OR EstimatedArrivalMin >= 0)
    );
END
GO

/* =========================================================
   13. BOOKING STATUS HISTORY
   ========================================================= */
IF OBJECT_ID(N'dbo.BookingStatusHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BookingStatusHistory
    (
        Id              BIGINT IDENTITY(1,1) NOT NULL,
        BookingId       BIGINT NOT NULL,
        OldStatus       VARCHAR(30) NULL,
        NewStatus       VARCHAR(30) NOT NULL,
        ChangedByUserId INT NULL,
        ChangedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_BookingStatusHistory_ChangedAt DEFAULT (SYSUTCDATETIME()),
        Reason          NVARCHAR(500) NULL,

        CONSTRAINT PK_BookingStatusHistory PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_BookingStatusHistory_NewStatus CHECK (NewStatus IN ('PENDING','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ACCEPTED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','CANCELLED')),
        CONSTRAINT CK_BookingStatusHistory_OldStatus CHECK (OldStatus IS NULL OR OldStatus IN ('PENDING','SEARCHING_DRIVER','DRIVER_ASSIGNED','DRIVER_ACCEPTED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS','COMPLETED','CANCELLED'))
    );
END
GO

/* =========================================================
   14. TRIPS
   One Booking can produce at most one actual Trip.
   ========================================================= */
IF OBJECT_ID(N'dbo.Trips', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Trips
    (
        Id                  BIGINT IDENTITY(1,1) NOT NULL,
        BookingId           BIGINT NOT NULL,
        DriverId            INT NOT NULL,
        StartTime            DATETIME2(3) NULL,
        EndTime              DATETIME2(3) NULL,
        StartLatitude       DECIMAL(10,7) NULL,
        StartLongitude      DECIMAL(10,7) NULL,
        EndLatitude         DECIMAL(10,7) NULL,
        EndLongitude        DECIMAL(10,7) NULL,
        ActualDistanceKm    DECIMAL(10,2) NULL,
        ActualDurationMin   INT NULL,
        Status               VARCHAR(20) NOT NULL CONSTRAINT DF_Trips_Status DEFAULT ('NOT_STARTED'),
        CreatedAt            DATETIME2(3) NOT NULL CONSTRAINT DF_Trips_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2(3) NULL,

        CONSTRAINT PK_Trips PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Trips_BookingId UNIQUE (BookingId),
        CONSTRAINT CK_Trips_Status CHECK (Status IN ('NOT_STARTED','IN_PROGRESS','COMPLETED','CANCELLED')),
        CONSTRAINT CK_Trips_Distance CHECK (ActualDistanceKm IS NULL OR ActualDistanceKm >= 0),
        CONSTRAINT CK_Trips_Duration CHECK (ActualDurationMin IS NULL OR ActualDurationMin >= 0),
        CONSTRAINT CK_Trips_StartLatitude CHECK (StartLatitude IS NULL OR StartLatitude BETWEEN -90 AND 90),
        CONSTRAINT CK_Trips_StartLongitude CHECK (StartLongitude IS NULL OR StartLongitude BETWEEN -180 AND 180),
        CONSTRAINT CK_Trips_EndLatitude CHECK (EndLatitude IS NULL OR EndLatitude BETWEEN -90 AND 90),
        CONSTRAINT CK_Trips_EndLongitude CHECK (EndLongitude IS NULL OR EndLongitude BETWEEN -180 AND 180)
    );
END
GO

/* =========================================================
   15. PAYMENTS
   Business-level payment object.
   ========================================================= */
IF OBJECT_ID(N'dbo.Payments', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Payments
    (
        Id              BIGINT IDENTITY(1,1) NOT NULL,
        TripId          BIGINT NOT NULL,
        CustomerId      INT NOT NULL,
        Amount          DECIMAL(18,2) NOT NULL,
        Currency        CHAR(3) NOT NULL CONSTRAINT DF_Payments_Currency DEFAULT ('VND'),
        PaymentMethod   VARCHAR(30) NOT NULL,
        PaymentStatus   VARCHAR(20) NOT NULL CONSTRAINT DF_Payments_Status DEFAULT ('PENDING'),
        PaidAt          DATETIME2(3) NULL,
        CreatedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_Payments_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt       DATETIME2(3) NULL,

        CONSTRAINT PK_Payments PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Payments_TripId UNIQUE (TripId),
        CONSTRAINT CK_Payments_Amount CHECK (Amount >= 0),
        CONSTRAINT CK_Payments_Method CHECK (PaymentMethod IN ('CASH','MOCK_BANKING','MOCK_EWALLET')),
        CONSTRAINT CK_Payments_Status CHECK (PaymentStatus IN ('PENDING','SUCCESS','FAILED','REFUNDED')),
        CONSTRAINT CK_Payments_Currency CHECK (Currency = 'VND')
    );
END
GO

/* =========================================================
   16. PAYMENT TRANSACTIONS
   Supports retry/provider transaction history.
   ========================================================= */
IF OBJECT_ID(N'dbo.PaymentTransactions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PaymentTransactions
    (
        Id                      BIGINT IDENTITY(1,1) NOT NULL,
        PaymentId               BIGINT NOT NULL,
        TransactionCode         VARCHAR(100) NOT NULL,
        TransactionType         VARCHAR(20) NOT NULL CONSTRAINT DF_PaymentTransactions_Type DEFAULT ('CHARGE'),
        Amount                  DECIMAL(18,2) NOT NULL,
        Status                  VARCHAR(20) NOT NULL CONSTRAINT DF_PaymentTransactions_Status DEFAULT ('PENDING'),
        Provider                VARCHAR(50) NULL,
        ProviderTransactionId   VARCHAR(150) NULL,
        FailureReason           NVARCHAR(500) NULL,
        CreatedAt               DATETIME2(3) NOT NULL CONSTRAINT DF_PaymentTransactions_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CompletedAt             DATETIME2(3) NULL,

        CONSTRAINT PK_PaymentTransactions PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_PaymentTransactions_Code UNIQUE (TransactionCode),
        CONSTRAINT CK_PaymentTransactions_Type CHECK (TransactionType IN ('CHARGE','REFUND','ADJUSTMENT')),
        CONSTRAINT CK_PaymentTransactions_Status CHECK (Status IN ('PENDING','SUCCESS','FAILED','CANCELLED')),
        CONSTRAINT CK_PaymentTransactions_Amount CHECK (Amount >= 0)
    );
END
GO

/* =========================================================
   17. RATINGS
   One rating per completed Trip.
   ========================================================= */
IF OBJECT_ID(N'dbo.Ratings', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Ratings
    (
        Id              BIGINT IDENTITY(1,1) NOT NULL,
        TripId          BIGINT NOT NULL,
        CustomerId      INT NOT NULL,
        DriverId        INT NOT NULL,
        Score           TINYINT NOT NULL,
        Comment         NVARCHAR(1000) NULL,
        CreatedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_Ratings_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt       DATETIME2(3) NULL,

        CONSTRAINT PK_Ratings PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Ratings_TripId UNIQUE (TripId),
        CONSTRAINT CK_Ratings_Score CHECK (Score BETWEEN 1 AND 5)
    );
END
GO

/* =========================================================
   18. PRICING RULES
   Admin-configurable pricing.
   ========================================================= */
IF OBJECT_ID(N'dbo.PricingRules', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.PricingRules
    (
        Id                  INT IDENTITY(1,1) NOT NULL,
        VehicleType         VARCHAR(20) NOT NULL,
        BaseFare            DECIMAL(18,2) NOT NULL,
        PricePerKm          DECIMAL(18,2) NOT NULL,
        PricePerMinute      DECIMAL(18,2) NOT NULL CONSTRAINT DF_PricingRules_PricePerMinute DEFAULT (0),
        NightSurcharge      DECIMAL(18,2) NOT NULL CONSTRAINT DF_PricingRules_NightSurcharge DEFAULT (0),
        WaitingPricePerMin  DECIMAL(18,2) NOT NULL CONSTRAINT DF_PricingRules_WaitingPricePerMin DEFAULT (0),
        FreePickupKm        DECIMAL(6,2) NOT NULL CONSTRAINT DF_PricingRules_FreePickupKm DEFAULT (3),
        PickupFeePerKm      DECIMAL(18,2) NOT NULL CONSTRAINT DF_PricingRules_PickupFeePerKm DEFAULT (5000),
        FreeWaitingMin      INT NOT NULL CONSTRAINT DF_PricingRules_FreeWaitingMin DEFAULT (10),
        OverDistanceTolerancePercent DECIMAL(5,2) NOT NULL CONSTRAINT DF_PricingRules_OverDistanceTolerancePercent DEFAULT (10),
        IsActive           BIT NOT NULL CONSTRAINT DF_PricingRules_IsActive DEFAULT (1),
        EffectiveFrom       DATETIME2(3) NOT NULL CONSTRAINT DF_PricingRules_EffectiveFrom DEFAULT (SYSUTCDATETIME()),
        EffectiveTo         DATETIME2(3) NULL,
        CreatedAt            DATETIME2(3) NOT NULL CONSTRAINT DF_PricingRules_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PricingRules PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_PricingRules_VehicleType CHECK (VehicleType IN ('MOTORBIKE','CAR','SUV','TRUCK','OTHER')),
        CONSTRAINT CK_PricingRules_Values CHECK (BaseFare >= 0 AND PricePerKm >= 0 AND PricePerMinute >= 0 AND NightSurcharge >= 0 AND WaitingPricePerMin >= 0),
        CONSTRAINT CK_PricingRules_Effective CHECK (EffectiveTo IS NULL OR EffectiveTo > EffectiveFrom)
    );
END
GO

/* =========================================================
   19. NOTIFICATIONS
   ========================================================= */
IF OBJECT_ID(N'dbo.Notifications', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Notifications
    (
        Id              BIGINT IDENTITY(1,1) NOT NULL,
        UserId          INT NOT NULL,
        Type            VARCHAR(50) NOT NULL,
        Title           NVARCHAR(200) NOT NULL,
        Message         NVARCHAR(1000) NOT NULL,
        DataJson        NVARCHAR(MAX) NULL,
        IsRead          BIT NOT NULL CONSTRAINT DF_Notifications_IsRead DEFAULT (0),
        ReadAt          DATETIME2(3) NULL,
        CreatedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_Notifications_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Notifications PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_Notifications_DataJson CHECK (DataJson IS NULL OR ISJSON(DataJson) = 1)
    );
END
GO

/* =========================================================
   20. AUDIT LOGS
   System-level audit. Separate from business histories.
   ========================================================= */
IF OBJECT_ID(N'dbo.AuditLogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AuditLogs
    (
        Id              BIGINT IDENTITY(1,1) NOT NULL,
        UserId          INT NULL,
        Action          VARCHAR(100) NOT NULL,
        EntityType      VARCHAR(100) NULL,
        EntityId        VARCHAR(100) NULL,
        OldValue        NVARCHAR(MAX) NULL,
        NewValue        NVARCHAR(MAX) NULL,
        IpAddress       VARCHAR(45) NULL,
        UserAgent       NVARCHAR(1000) NULL,
        CreatedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_AuditLogs_CreatedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_AuditLogs PRIMARY KEY CLUSTERED (Id)
    );
END
GO

/* =========================================================
   FOREIGN KEYS
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_UserRoles_Users')
ALTER TABLE dbo.UserRoles ADD CONSTRAINT FK_UserRoles_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_UserRoles_Roles')
ALTER TABLE dbo.UserRoles ADD CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleId) REFERENCES dbo.Roles(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_UserRoles_AssignedBy')
ALTER TABLE dbo.UserRoles ADD CONSTRAINT FK_UserRoles_AssignedBy FOREIGN KEY (AssignedBy) REFERENCES dbo.Users(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_RefreshTokens_Users')
ALTER TABLE dbo.RefreshTokens ADD CONSTRAINT FK_RefreshTokens_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_RefreshTokens_ReplacedBy')
ALTER TABLE dbo.RefreshTokens ADD CONSTRAINT FK_RefreshTokens_ReplacedBy FOREIGN KEY (ReplacedByTokenId) REFERENCES dbo.RefreshTokens(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Customers_Users')
ALTER TABLE dbo.Customers ADD CONSTRAINT FK_Customers_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_CustomerVehicles_Customers')
ALTER TABLE dbo.CustomerVehicles ADD CONSTRAINT FK_CustomerVehicles_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Drivers_Users')
ALTER TABLE dbo.Drivers ADD CONSTRAINT FK_Drivers_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_DriverDocuments_Drivers')
ALTER TABLE dbo.DriverDocuments ADD CONSTRAINT FK_DriverDocuments_Drivers FOREIGN KEY (DriverId) REFERENCES dbo.Drivers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_DriverDocuments_VerifiedBy')
ALTER TABLE dbo.DriverDocuments ADD CONSTRAINT FK_DriverDocuments_VerifiedBy FOREIGN KEY (VerifiedBy) REFERENCES dbo.Users(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_DriverStatusHistory_Drivers')
ALTER TABLE dbo.DriverStatusHistory ADD CONSTRAINT FK_DriverStatusHistory_Drivers FOREIGN KEY (DriverId) REFERENCES dbo.Drivers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_DriverLocationHistory_Drivers')
ALTER TABLE dbo.DriverLocationHistory ADD CONSTRAINT FK_DriverLocationHistory_Drivers FOREIGN KEY (DriverId) REFERENCES dbo.Drivers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_DriverLocationHistory_Bookings')
ALTER TABLE dbo.DriverLocationHistory ADD CONSTRAINT FK_DriverLocationHistory_Bookings FOREIGN KEY (BookingId) REFERENCES dbo.Bookings(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Bookings_Customers')
ALTER TABLE dbo.Bookings ADD CONSTRAINT FK_Bookings_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Bookings_Drivers')
ALTER TABLE dbo.Bookings ADD CONSTRAINT FK_Bookings_Drivers FOREIGN KEY (DriverId) REFERENCES dbo.Drivers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Bookings_CustomerVehicles')
ALTER TABLE dbo.Bookings ADD CONSTRAINT FK_Bookings_CustomerVehicles FOREIGN KEY (CustomerVehicleId) REFERENCES dbo.CustomerVehicles(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Bookings_PricingRules')
ALTER TABLE dbo.Bookings ADD CONSTRAINT FK_Bookings_PricingRules FOREIGN KEY (PricingRuleId) REFERENCES dbo.PricingRules(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_BookingDriverOffers_Bookings')
ALTER TABLE dbo.BookingDriverOffers ADD CONSTRAINT FK_BookingDriverOffers_Bookings FOREIGN KEY (BookingId) REFERENCES dbo.Bookings(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_BookingDriverOffers_Drivers')
ALTER TABLE dbo.BookingDriverOffers ADD CONSTRAINT FK_BookingDriverOffers_Drivers FOREIGN KEY (DriverId) REFERENCES dbo.Drivers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_BookingStatusHistory_Bookings')
ALTER TABLE dbo.BookingStatusHistory ADD CONSTRAINT FK_BookingStatusHistory_Bookings FOREIGN KEY (BookingId) REFERENCES dbo.Bookings(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_BookingStatusHistory_Users')
ALTER TABLE dbo.BookingStatusHistory ADD CONSTRAINT FK_BookingStatusHistory_Users FOREIGN KEY (ChangedByUserId) REFERENCES dbo.Users(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Trips_Bookings')
ALTER TABLE dbo.Trips ADD CONSTRAINT FK_Trips_Bookings FOREIGN KEY (BookingId) REFERENCES dbo.Bookings(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Trips_Drivers')
ALTER TABLE dbo.Trips ADD CONSTRAINT FK_Trips_Drivers FOREIGN KEY (DriverId) REFERENCES dbo.Drivers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Payments_Trips')
ALTER TABLE dbo.Payments ADD CONSTRAINT FK_Payments_Trips FOREIGN KEY (TripId) REFERENCES dbo.Trips(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Payments_Customers')
ALTER TABLE dbo.Payments ADD CONSTRAINT FK_Payments_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_PaymentTransactions_Payments')
ALTER TABLE dbo.PaymentTransactions ADD CONSTRAINT FK_PaymentTransactions_Payments FOREIGN KEY (PaymentId) REFERENCES dbo.Payments(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Ratings_Trips')
ALTER TABLE dbo.Ratings ADD CONSTRAINT FK_Ratings_Trips FOREIGN KEY (TripId) REFERENCES dbo.Trips(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Ratings_Customers')
ALTER TABLE dbo.Ratings ADD CONSTRAINT FK_Ratings_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Ratings_Drivers')
ALTER TABLE dbo.Ratings ADD CONSTRAINT FK_Ratings_Drivers FOREIGN KEY (DriverId) REFERENCES dbo.Drivers(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_Notifications_Users')
ALTER TABLE dbo.Notifications ADD CONSTRAINT FK_Notifications_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_AuditLogs_Users')
ALTER TABLE dbo.AuditLogs ADD CONSTRAINT FK_AuditLogs_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(Id);
GO

/* =========================================================
   INDEXES
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Drivers_Matching' AND object_id=OBJECT_ID(N'dbo.Drivers'))
CREATE INDEX IX_Drivers_Matching ON dbo.Drivers(DriverStatus, VerificationStatus, RatingAverage) INCLUDE(CurrentLatitude, CurrentLongitude, UserId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_DriverDocuments_DriverId' AND object_id=OBJECT_ID(N'dbo.DriverDocuments'))
CREATE INDEX IX_DriverDocuments_DriverId ON dbo.DriverDocuments(DriverId, DocumentType, VerificationStatus);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_CustomerVehicles_CustomerId' AND object_id=OBJECT_ID(N'dbo.CustomerVehicles'))
CREATE INDEX IX_CustomerVehicles_CustomerId ON dbo.CustomerVehicles(CustomerId, IsActive) INCLUDE(VehicleType, Transmission, LicensePlate);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Bookings_Customer_Status_Created' AND object_id=OBJECT_ID(N'dbo.Bookings'))
CREATE INDEX IX_Bookings_Customer_Status_Created ON dbo.Bookings(CustomerId, Status, CreatedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Bookings_Driver_Status_Created' AND object_id=OBJECT_ID(N'dbo.Bookings'))
CREATE INDEX IX_Bookings_Driver_Status_Created ON dbo.Bookings(DriverId, Status, CreatedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Bookings_Searching' AND object_id=OBJECT_ID(N'dbo.Bookings'))
CREATE INDEX IX_Bookings_Searching ON dbo.Bookings(Status, CreatedAt);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Bookings_PricingRule' AND object_id=OBJECT_ID(N'dbo.Bookings'))
CREATE INDEX IX_Bookings_PricingRule ON dbo.Bookings(PricingRuleId, CreatedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_BookingDriverOffers_Driver' AND object_id=OBJECT_ID(N'dbo.BookingDriverOffers'))
CREATE INDEX IX_BookingDriverOffers_Driver ON dbo.BookingDriverOffers(DriverId, OfferStatus, SentAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_BookingDriverOffers_Booking' AND object_id=OBJECT_ID(N'dbo.BookingDriverOffers'))
CREATE INDEX IX_BookingDriverOffers_Booking ON dbo.BookingDriverOffers(BookingId, OfferStatus, SentAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_BookingStatusHistory_Booking_Time' AND object_id=OBJECT_ID(N'dbo.BookingStatusHistory'))
CREATE INDEX IX_BookingStatusHistory_Booking_Time ON dbo.BookingStatusHistory(BookingId, ChangedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Trips_Driver_Status' AND object_id=OBJECT_ID(N'dbo.Trips'))
CREATE INDEX IX_Trips_Driver_Status ON dbo.Trips(DriverId, Status, StartTime DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_DriverLocationHistory_Driver_Time' AND object_id=OBJECT_ID(N'dbo.DriverLocationHistory'))
CREATE INDEX IX_DriverLocationHistory_Driver_Time ON dbo.DriverLocationHistory(DriverId, RecordedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_DriverLocationHistory_Booking_Time' AND object_id=OBJECT_ID(N'dbo.DriverLocationHistory'))
CREATE INDEX IX_DriverLocationHistory_Booking_Time ON dbo.DriverLocationHistory(BookingId, RecordedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Payments_Customer_Status' AND object_id=OBJECT_ID(N'dbo.Payments'))
CREATE INDEX IX_Payments_Customer_Status ON dbo.Payments(CustomerId, PaymentStatus, CreatedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_PaymentTransactions_Payment_Created' AND object_id=OBJECT_ID(N'dbo.PaymentTransactions'))
CREATE INDEX IX_PaymentTransactions_Payment_Created ON dbo.PaymentTransactions(PaymentId, CreatedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'UX_PaymentTransactions_ProviderTransactionId' AND object_id=OBJECT_ID(N'dbo.PaymentTransactions'))
CREATE UNIQUE INDEX UX_PaymentTransactions_ProviderTransactionId ON dbo.PaymentTransactions(ProviderTransactionId) WHERE ProviderTransactionId IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Ratings_Driver' AND object_id=OBJECT_ID(N'dbo.Ratings'))
CREATE INDEX IX_Ratings_Driver ON dbo.Ratings(DriverId, CreatedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_PricingRules_Active' AND object_id=OBJECT_ID(N'dbo.PricingRules'))
CREATE INDEX IX_PricingRules_Active ON dbo.PricingRules(VehicleType, IsActive, EffectiveFrom DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_Notifications_User_Read_Created' AND object_id=OBJECT_ID(N'dbo.Notifications'))
CREATE INDEX IX_Notifications_User_Read_Created ON dbo.Notifications(UserId, IsRead, CreatedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_RefreshTokens_User_Expires' AND object_id=OBJECT_ID(N'dbo.RefreshTokens'))
CREATE INDEX IX_RefreshTokens_User_Expires ON dbo.RefreshTokens(UserId, ExpiresAt);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_DriverStatusHistory_Driver_Time' AND object_id=OBJECT_ID(N'dbo.DriverStatusHistory'))
CREATE INDEX IX_DriverStatusHistory_Driver_Time ON dbo.DriverStatusHistory(DriverId, ChangedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_AuditLogs_User_Created' AND object_id=OBJECT_ID(N'dbo.AuditLogs'))
CREATE INDEX IX_AuditLogs_User_Created ON dbo.AuditLogs(UserId, CreatedAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name=N'IX_AuditLogs_Entity_Created' AND object_id=OBJECT_ID(N'dbo.AuditLogs'))
CREATE INDEX IX_AuditLogs_Entity_Created ON dbo.AuditLogs(EntityType, EntityId, CreatedAt DESC);
GO

/* =========================================================
   VIEWS FOR ADMIN DASHBOARD
   ========================================================= */
CREATE OR ALTER VIEW dbo.vw_DriverSummary
AS
SELECT
    d.Id AS DriverId,
    u.FullName,
    u.Phone,
    u.Email,
    d.LicenseNumber,
    d.LicenseClass,
    d.VerificationStatus,
    d.DriverStatus,
    d.RatingAverage,
    d.RatingCount,
    d.TotalTrips,
    d.TotalEarnings,
    d.CurrentLatitude,
    d.CurrentLongitude,
    d.LastLocationAt,
    d.CreatedAt
FROM dbo.Drivers d
INNER JOIN dbo.Users u ON u.Id = d.UserId
WHERE u.IsDeleted = 0;
GO

CREATE OR ALTER VIEW dbo.vw_BookingSummary
AS
SELECT
    b.Id AS BookingId,
    b.BookingCode,
    b.Status,
    b.CreatedAt,
    c.Id AS CustomerId,
    cu.FullName AS CustomerName,
    cu.Phone AS CustomerPhone,
    d.Id AS DriverId,
    du.FullName AS DriverName,
    du.Phone AS DriverPhone,
    cv.Id AS CustomerVehicleId,
    cv.VehicleType,
    cv.Transmission,
    cv.LicensePlate,
    b.PickupAddress,
    b.DestinationAddress,
    b.EstimatedDistanceKm,
    b.EstimatedDurationMin,
    b.EstimatedPrice,
    b.FinalPrice,
    p.PaymentStatus
FROM dbo.Bookings b
INNER JOIN dbo.Customers c ON c.Id = b.CustomerId
INNER JOIN dbo.Users cu ON cu.Id = c.UserId
INNER JOIN dbo.CustomerVehicles cv ON cv.Id = b.CustomerVehicleId
LEFT JOIN dbo.Drivers d ON d.Id = b.DriverId
LEFT JOIN dbo.Users du ON du.Id = d.UserId
LEFT JOIN dbo.Trips t ON t.BookingId = b.Id
LEFT JOIN dbo.Payments p ON p.TripId = t.Id;
GO

/* =========================================================
   SEED ROLES
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE Name='CUSTOMER')
INSERT INTO dbo.Roles(Name, Description) VALUES ('CUSTOMER', N'Customer who books a driver');

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE Name='DRIVER')
INSERT INTO dbo.Roles(Name, Description) VALUES ('DRIVER', N'Driver who drives the customer vehicle');

IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE Name='ADMIN')
INSERT INTO dbo.Roles(Name, Description) VALUES ('ADMIN', N'System administrator');
GO

/* =========================================================
   SEED ADMIN
   PasswordHash is intentionally NOT plaintext.
   Replace with a real ASP.NET Core PasswordHasher result.
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Phone='0900000000')
BEGIN
    INSERT INTO dbo.Users
    (
        FullName, Phone, Email, PasswordHash, Status
    )
    VALUES
    (
        N'DRIVO Administrator',
        '0900000000',
        'admin@drivo.local',
        N'REPLACE_WITH_ASPNET_PASSWORD_HASH',
        'ACTIVE'
    );
END
GO

DECLARE @AdminUserId INT = (SELECT Id FROM dbo.Users WHERE Phone='0900000000');
DECLARE @AdminRoleId INT = (SELECT Id FROM dbo.Roles WHERE Name='ADMIN');

IF @AdminUserId IS NOT NULL AND @AdminRoleId IS NOT NULL
AND NOT EXISTS (SELECT 1 FROM dbo.UserRoles WHERE UserId=@AdminUserId AND RoleId=@AdminRoleId)
BEGIN
    INSERT INTO dbo.UserRoles(UserId, RoleId, AssignedAt)
    VALUES (@AdminUserId, @AdminRoleId, SYSUTCDATETIME());
END
GO

/* =========================================================
   SEED BASIC PRICING
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM dbo.PricingRules WHERE VehicleType='MOTORBIKE' AND IsActive=1)
BEGIN
    INSERT INTO dbo.PricingRules
    (
        VehicleType, BaseFare, PricePerKm, PricePerMinute,
        NightSurcharge, WaitingPricePerMin
    )
    VALUES
    ('MOTORBIKE', 30000, 10000, 0, 10000, 1000);
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.PricingRules WHERE VehicleType='CAR' AND IsActive=1)
BEGIN
    INSERT INTO dbo.PricingRules
    (
        VehicleType, BaseFare, PricePerKm, PricePerMinute,
        NightSurcharge, WaitingPricePerMin
    )
    VALUES
    ('CAR', 50000, 15000, 0, 20000, 1500);
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.PricingRules WHERE VehicleType='SUV' AND IsActive=1)
BEGIN
    INSERT INTO dbo.PricingRules
    (
        VehicleType, BaseFare, PricePerKm, PricePerMinute,
        NightSurcharge, WaitingPricePerMin
    )
    VALUES
    ('SUV', 60000, 18000, 0, 20000, 1500);
END
GO

/* =========================================================
   FINAL CHECK
   ========================================================= */
SELECT
    COUNT(*) AS TableCount
FROM sys.tables
WHERE schema_id = SCHEMA_ID('dbo')
  AND name IN
  (
      'Users','Roles','UserRoles','RefreshTokens',
      'Customers','CustomerVehicles',
      'Drivers','DriverDocuments','DriverStatusHistory','DriverLocationHistory',
      'Bookings','BookingDriverOffers','BookingStatusHistory','Trips',
      'Payments','PaymentTransactions','Ratings','PricingRules','Notifications','AuditLogs'
  );
GO

PRINT 'DRIVO Database V2 setup completed.';
GO
GO

/* ======================= 001_vouchers.sql ======================= */
USE [DrivoDB];
GO
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
GO

/* ======================= 002_maps_tracking_pricing.sql ======================= */
USE [DrivoDB];
GO
/* =========================================================
   002 - Google Maps + Live Tracking + Pricing (pickup/waiting/extra-distance fees)
   Idempotent: safe to run multiple times.
   sqlcmd -S localhost -d DrivoDB -E -C -i drivo-api/sql/002_maps_tracking_pricing.sql
   ========================================================= */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------- PricingRules ---------- */
IF COL_LENGTH('dbo.PricingRules', 'FreePickupKm') IS NULL
    ALTER TABLE dbo.PricingRules ADD FreePickupKm DECIMAL(6,2) NOT NULL
        CONSTRAINT DF_PricingRules_FreePickupKm DEFAULT (3);
GO
IF COL_LENGTH('dbo.PricingRules', 'PickupFeePerKm') IS NULL
    ALTER TABLE dbo.PricingRules ADD PickupFeePerKm DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_PricingRules_PickupFeePerKm DEFAULT (5000);
GO
IF COL_LENGTH('dbo.PricingRules', 'FreeWaitingMin') IS NULL
    ALTER TABLE dbo.PricingRules ADD FreeWaitingMin INT NOT NULL
        CONSTRAINT DF_PricingRules_FreeWaitingMin DEFAULT (10);
GO
IF COL_LENGTH('dbo.PricingRules', 'OverDistanceTolerancePercent') IS NULL
    ALTER TABLE dbo.PricingRules ADD OverDistanceTolerancePercent DECIMAL(5,2) NOT NULL
        CONSTRAINT DF_PricingRules_OverDistanceTolerancePercent DEFAULT (10);
GO

/* ---------- Bookings ---------- */
IF COL_LENGTH('dbo.Bookings', 'PickupDistanceKm') IS NULL
    ALTER TABLE dbo.Bookings ADD PickupDistanceKm DECIMAL(8,2) NULL;
GO
IF COL_LENGTH('dbo.Bookings', 'PickupFee') IS NULL
    ALTER TABLE dbo.Bookings ADD PickupFee DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_Bookings_PickupFee DEFAULT (0);
GO
IF COL_LENGTH('dbo.Bookings', 'WaitingFee') IS NULL
    ALTER TABLE dbo.Bookings ADD WaitingFee DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_Bookings_WaitingFee DEFAULT (0);
GO
IF COL_LENGTH('dbo.Bookings', 'ExtraDistanceFee') IS NULL
    ALTER TABLE dbo.Bookings ADD ExtraDistanceFee DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_Bookings_ExtraDistanceFee DEFAULT (0);
GO
IF COL_LENGTH('dbo.Bookings', 'ActualDistanceKm') IS NULL
    ALTER TABLE dbo.Bookings ADD ActualDistanceKm DECIMAL(8,2) NULL;
GO
IF COL_LENGTH('dbo.Bookings', 'RoutePolyline') IS NULL
    ALTER TABLE dbo.Bookings ADD RoutePolyline NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH('dbo.Bookings', 'AcceptedAt') IS NULL
    ALTER TABLE dbo.Bookings ADD AcceptedAt DATETIME2(3) NULL;
GO
IF COL_LENGTH('dbo.Bookings', 'ArrivedAt') IS NULL
    ALTER TABLE dbo.Bookings ADD ArrivedAt DATETIME2(3) NULL;
GO
IF COL_LENGTH('dbo.Bookings', 'StartedAt') IS NULL
    ALTER TABLE dbo.Bookings ADD StartedAt DATETIME2(3) NULL;
GO
IF COL_LENGTH('dbo.Bookings', 'CompletedAt') IS NULL
    ALTER TABLE dbo.Bookings ADD CompletedAt DATETIME2(3) NULL;
GO

/* DriverLocationHistory indexes (Driver_Time, Booking_Time) already exist in DRIVO_Database_V2.sql. */

PRINT N'002_maps_tracking_pricing applied.';
GO
GO

/* ======================= 003_commission.sql ======================= */
USE [DrivoDB];
GO
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
GO

/* ======================= 004_payments_vouchers.sql ======================= */
USE [DrivoDB];
GO
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
GO

/* ======================= 005_driver_profile.sql ======================= */
USE [DrivoDB];
GO
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
GO

/* ======================= 006_driver_wallet.sql ======================= */
USE [DrivoDB];
GO
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
GO

/* ======================= 007_seed_admin_password.sql ======================= */
USE [DrivoDB];
GO
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
GO

/* ======================= 008_cancel_fault_waiting.sql ======================= */
USE [DrivoDB];
GO
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
GO
