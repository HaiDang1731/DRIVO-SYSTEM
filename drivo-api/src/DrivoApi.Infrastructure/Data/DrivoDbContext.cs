using DrivoApi.Domain.Entities;
using DrivoApi.Domain.Enums;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure.Data;

public class DrivoDbContext(DbContextOptions<DrivoDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Role> Roles => Set<Role>();
    public DbSet<UserRole> UserRoles => Set<UserRole>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<CustomerVehicle> CustomerVehicles => Set<CustomerVehicle>();
    public DbSet<Driver> Drivers => Set<Driver>();
    public DbSet<DriverDocument> DriverDocuments => Set<DriverDocument>();
    public DbSet<DriverStatusHistory> DriverStatusHistories => Set<DriverStatusHistory>();
    public DbSet<DriverLocationHistory> DriverLocationHistories => Set<DriverLocationHistory>();
    public DbSet<Booking> Bookings => Set<Booking>();
    public DbSet<BookingDriverOffer> BookingDriverOffers => Set<BookingDriverOffer>();
    public DbSet<BookingStatusHistory> BookingStatusHistories => Set<BookingStatusHistory>();
    public DbSet<Trip> Trips => Set<Trip>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<PaymentTransaction> PaymentTransactions => Set<PaymentTransaction>();
    public DbSet<Rating> Ratings => Set<Rating>();
    public DbSet<PricingRule> PricingRules => Set<PricingRule>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<Voucher> Vouchers => Set<Voucher>();

    public static string ToSnakeUpper(string val) =>
        string.Concat(val.Select((x, i) => i > 0 && char.IsUpper(x) ? "_" + x : x.ToString())).ToUpperInvariant();

    public static T FromSnakeUpper<T>(string val) where T : struct, Enum
    {
        if (string.IsNullOrWhiteSpace(val)) return default;
        var parts = val.Split('_');
        var pascal = string.Concat(parts.Select(s => s.Length > 0 ? char.ToUpperInvariant(s[0]) + s.Substring(1).ToLowerInvariant() : ""));
        if (Enum.TryParse<T>(pascal, true, out var result)) return result;
        if (Enum.TryParse<T>(val, true, out var r2)) return r2;
        return default;
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(DrivoDbContext).Assembly);

        // Composite PK for UserRole
        modelBuilder.Entity<UserRole>()
            .HasKey(ur => new { ur.UserId, ur.RoleId });

        modelBuilder.Entity<UserRole>()
            .HasOne(ur => ur.User)
            .WithMany(u => u.UserRoles)
            .HasForeignKey(ur => ur.UserId);

        modelBuilder.Entity<UserRole>()
            .HasOne(ur => ur.Role)
            .WithMany(r => r.UserRoles)
            .HasForeignKey(ur => ur.RoleId);

        // One-to-one User <-> Customer
        modelBuilder.Entity<Customer>()
            .HasOne(c => c.User)
            .WithOne(u => u.Customer)
            .HasForeignKey<Customer>(c => c.UserId);

        // One-to-one User <-> Driver
        modelBuilder.Entity<Driver>()
            .HasOne(d => d.User)
            .WithOne(u => u.Driver)
            .HasForeignKey<Driver>(d => d.UserId);

        // RefreshToken self-referencing relationship mapping
        modelBuilder.Entity<RefreshToken>()
            .HasOne(rt => rt.ReplacedBy)
            .WithMany()
            .HasForeignKey(rt => rt.ReplacedByTokenId);

        // Enum conversions
        modelBuilder.Entity<User>()
            .Property(u => u.Status)
            .HasConversion<string>();

        modelBuilder.Entity<Driver>()
            .Property(d => d.VerificationStatus)
            .HasConversion<string>();

        modelBuilder.Entity<Driver>()
            .Property(d => d.DriverStatus)
            .HasConversion<string>();

        modelBuilder.Entity<Booking>()
            .Property(b => b.Status)
            .HasConversion(
                v => ToSnakeUpper(v.ToString()),
                v => FromSnakeUpper<BookingStatus>(v)
            );

        modelBuilder.Entity<Booking>()
            .Property(b => b.VehicleType)
            .HasConversion<string>();

        modelBuilder.Entity<Booking>()
            .Property(b => b.Transmission)
            .HasConversion<string>();

        modelBuilder.Entity<CustomerVehicle>()
            .Property(cv => cv.VehicleType)
            .HasConversion<string>();

        modelBuilder.Entity<CustomerVehicle>()
            .Property(cv => cv.Transmission)
            .HasConversion<string>();

        // CK_Payments_* yêu cầu 'CASH' | 'MOCK_BANKING' | 'SUCCESS'... (snake upper)
        modelBuilder.Entity<Payment>()
            .Property(p => p.PaymentStatus)
            .HasConversion(v => ToSnakeUpper(v.ToString()), v => FromSnakeUpper<PaymentStatus>(v));

        modelBuilder.Entity<Payment>()
            .Property(p => p.PaymentMethod)
            .HasConversion(v => ToSnakeUpper(v.ToString()), v => FromSnakeUpper<PaymentMethod>(v));

        modelBuilder.Entity<Booking>()
            .Property(b => b.PaymentMethod)
            .HasConversion(v => ToSnakeUpper(v.ToString()), v => FromSnakeUpper<PaymentMethod>(v));

        modelBuilder.Entity<PricingRule>()
            .Property(pr => pr.VehicleType)
            .HasConversion<string>();

        modelBuilder.Entity<BookingDriverOffer>()
            .Property(o => o.OfferStatus)
            .HasConversion<string>();

        // Decimal precision (match SQL schema; default decimal(18,2) would truncate coordinates)
        modelBuilder.Entity<Driver>(e =>
        {
            e.Property(d => d.CurrentLatitude).HasPrecision(10, 7);
            e.Property(d => d.CurrentLongitude).HasPrecision(10, 7);
        });

        modelBuilder.Entity<DriverLocationHistory>(e =>
        {
            e.Property(h => h.Latitude).HasPrecision(10, 7);
            e.Property(h => h.Longitude).HasPrecision(10, 7);
            e.Property(h => h.AccuracyMeters).HasPrecision(8, 2);
            e.Property(h => h.SpeedKmh).HasPrecision(8, 2);
            e.Property(h => h.Heading).HasPrecision(6, 2);
        });

        modelBuilder.Entity<Booking>(e =>
        {
            e.Property(b => b.PickupLatitude).HasPrecision(10, 7);
            e.Property(b => b.PickupLongitude).HasPrecision(10, 7);
            e.Property(b => b.DestinationLatitude).HasPrecision(10, 7);
            e.Property(b => b.DestinationLongitude).HasPrecision(10, 7);
            e.Property(b => b.EstimatedDistanceKm).HasPrecision(10, 2);
            e.Property(b => b.PickupDistanceKm).HasPrecision(8, 2);
            e.Property(b => b.ActualDistanceKm).HasPrecision(8, 2);
        });

        modelBuilder.Entity<Trip>(e =>
        {
            e.Property(t => t.StartLatitude).HasPrecision(10, 7);
            e.Property(t => t.StartLongitude).HasPrecision(10, 7);
            e.Property(t => t.EndLatitude).HasPrecision(10, 7);
            e.Property(t => t.EndLongitude).HasPrecision(10, 7);
            e.Property(t => t.ActualDistanceKm).HasPrecision(10, 2);
        });

        modelBuilder.Entity<PricingRule>(e =>
        {
            e.Property(p => p.FreePickupKm).HasPrecision(6, 2);
            e.Property(p => p.OverDistanceTolerancePercent).HasPrecision(5, 2);
            e.Property(p => p.CommissionPercent).HasPrecision(5, 2);
        });

        // Table name mappings (matching exact database tables)
        modelBuilder.Entity<BookingStatusHistory>().ToTable("BookingStatusHistory");
        modelBuilder.Entity<DriverStatusHistory>().ToTable("DriverStatusHistory");
        modelBuilder.Entity<DriverLocationHistory>().ToTable("DriverLocationHistory");
    }
}
