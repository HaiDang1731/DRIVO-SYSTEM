using DrivoApi.Application.DTOs.Common;
using DrivoApi.Application.DTOs.Customer;
using DrivoApi.Application.Services;
using DrivoApi.Domain.Entities;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure;

public class CustomerVehicleService(DrivoDbContext db) : ICustomerVehicleService
{
    private async Task<Customer> GetOrCreateCustomerAsync(int userId)
    {
        var customer = await db.Customers.FirstOrDefaultAsync(c => c.UserId == userId);
        if (customer == null)
        {
            customer = new Customer
            {
                UserId = userId,
                CreatedAt = DateTime.UtcNow
            };
            db.Customers.Add(customer);
            await db.SaveChangesAsync();
        }
        return customer;
    }

    public async Task<BaseResponse<List<CustomerVehicleResponse>>> GetVehiclesAsync(int userId)
    {
        var customer = await GetOrCreateCustomerAsync(userId);
        var vehicles = await db.CustomerVehicles
            .Where(v => v.CustomerId == customer.Id && v.IsActive)
            .OrderByDescending(v => v.IsDefault)
            .ThenByDescending(v => v.CreatedAt)
            .Select(v => new CustomerVehicleResponse
            {
                Id = v.Id,
                CustomerId = v.CustomerId,
                Brand = v.Brand,
                Model = v.Model,
                Color = v.Color,
                LicensePlate = v.LicensePlate,
                VehicleType = v.VehicleType.ToString(),
                Transmission = v.Transmission.ToString(),
                ProductionYear = v.ProductionYear,
                IsDefault = v.IsDefault,
                CreatedAt = v.CreatedAt
            })
            .ToListAsync();

        return BaseResponse<List<CustomerVehicleResponse>>.Ok(vehicles);
    }

    public async Task<BaseResponse<CustomerVehicleResponse>> AddVehicleAsync(int userId, CreateCustomerVehicleRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.LicensePlate))
            return BaseResponse<CustomerVehicleResponse>.Fail("Biển số xe không được để trống.");

        var customer = await GetOrCreateCustomerAsync(userId);

        var plateFormatted = request.LicensePlate.Trim().ToUpperInvariant();

        // Kiểm tra xem khách đã có xe nào chưa
        var hasVehicles = await db.CustomerVehicles.AnyAsync(v => v.CustomerId == customer.Id && v.IsActive);
        var isDefault = request.IsDefault || !hasVehicles;

        if (isDefault)
        {
            var existingDefaults = await db.CustomerVehicles
                .Where(v => v.CustomerId == customer.Id && v.IsDefault)
                .ToListAsync();
            foreach (var v in existingDefaults) v.IsDefault = false;
        }

        var vehicle = new CustomerVehicle
        {
            CustomerId = customer.Id,
            Brand = request.Brand?.Trim(),
            Model = request.Model?.Trim(),
            Color = request.Color?.Trim(),
            LicensePlate = plateFormatted,
            VehicleType = request.VehicleType,
            Transmission = request.Transmission,
            ProductionYear = request.ProductionYear,
            IsDefault = isDefault,
            IsActive = true,
            CreatedAt = DateTime.UtcNow
        };

        db.CustomerVehicles.Add(vehicle);
        await db.SaveChangesAsync();

        var res = new CustomerVehicleResponse
        {
            Id = vehicle.Id,
            CustomerId = vehicle.CustomerId,
            Brand = vehicle.Brand,
            Model = vehicle.Model,
            Color = vehicle.Color,
            LicensePlate = vehicle.LicensePlate,
            VehicleType = vehicle.VehicleType.ToString(),
            Transmission = vehicle.Transmission.ToString(),
            ProductionYear = vehicle.ProductionYear,
            IsDefault = vehicle.IsDefault,
            CreatedAt = vehicle.CreatedAt
        };

        return BaseResponse<CustomerVehicleResponse>.Ok(res, "Thêm xe thành công.");
    }

    public async Task<BaseResponse<bool>> DeleteVehicleAsync(int userId, int vehicleId)
    {
        var customer = await GetOrCreateCustomerAsync(userId);
        var vehicle = await db.CustomerVehicles.FirstOrDefaultAsync(v => v.Id == vehicleId && v.CustomerId == customer.Id);

        if (vehicle == null)
            return BaseResponse<bool>.Fail("Không tìm thấy xe.");

        vehicle.IsActive = false;
        vehicle.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        return BaseResponse<bool>.Ok(true, "Xóa xe thành công.");
    }
}
