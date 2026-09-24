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
