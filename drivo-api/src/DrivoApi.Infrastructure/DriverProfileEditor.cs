using System.Text.RegularExpressions;
using DrivoApi.Application.DTOs.Driver;
using DrivoApi.Domain.Entities;
using DrivoApi.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace DrivoApi.Infrastructure;

/// <summary>Đọc/ghi các trường hồ sơ tài xế, dùng chung cho tài xế tự sửa và admin sửa.</summary>
public static partial class DriverProfileEditor
{
    /// <summary>Tài xế tự đăng ký được gán số GPLX tạm 'PENDING_...' (cột NOT NULL + UNIQUE) -> coi như chưa có.</summary>
    public static string DisplayLicense(string licenseNumber) =>
        licenseNumber.StartsWith("PENDING_", StringComparison.Ordinal) ? string.Empty : licenseNumber;

    public static void Fill(DriverProfileFields target, Driver d)
    {
        target.FullName = d.User.FullName;
        target.Email = d.User.Email;
        target.DateOfBirth = d.DateOfBirth;
        target.Gender = d.Gender;
        target.Address = d.Address;
        target.IdCardNumber = d.IdCardNumber;
        target.LicenseNumber = DisplayLicense(d.LicenseNumber);
        target.LicenseClass = d.LicenseClass;
        target.LicenseExpiryDate = d.LicenseExpiryDate;
        target.DrivingExperienceYears = d.DrivingExperienceYears;
        target.EmergencyContactName = d.EmergencyContactName;
        target.EmergencyContactPhone = d.EmergencyContactPhone;
        target.EmergencyContactRelation = d.EmergencyContactRelation;
        target.BankName = d.BankName;
        target.BankAccountNumber = d.BankAccountNumber;
        target.BankAccountHolder = d.BankAccountHolder;
    }

    public static DriverDocumentItem MapDocument(DriverDocument doc) => new()
    {
        Id = doc.Id,
        DocumentType = doc.DocumentType,
        FileUrl = doc.FileUrl,
        VerificationStatus = doc.VerificationStatus.ToString(),
        RejectionReason = doc.RejectionReason,
        CreatedAt = doc.CreatedAt,
        VerifiedAt = doc.VerifiedAt
    };

    [GeneratedRegex(@"^\d{9}$|^\d{12}$")] private static partial Regex IdCardRegex();
    [GeneratedRegex(@"^[A-Za-z0-9]{5,20}$")] private static partial Regex LicenseRegex();
    [GeneratedRegex(@"^\+?\d{9,12}$")] private static partial Regex PhoneRegex();
    [GeneratedRegex(@"^\d{6,20}$")] private static partial Regex BankAccountRegex();
    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$")] private static partial Regex EmailRegex();

    private static string? Norm(string? s) => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    /// <summary>
    /// Áp dụng các trường khác null trong <paramref name="r"/> (chuỗi rỗng = xóa).
    /// Trả về lỗi (null nếu hợp lệ) và việc có đổi thông tin cần duyệt lại hay không
    /// (GPLX, CCCD, ngày sinh, tài khoản nhận tiền).
    /// </summary>
    public static async Task<(string? Error, bool SensitiveChanged)> ApplyAsync(DrivoDbContext db, Driver d, DriverProfileFields r)
    {
        var sensitive = false;
        var today = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(7));

        // ── Họ tên, email (sửa tự do) ──
        if (r.FullName != null)
        {
            var name = Norm(r.FullName);
            if (name == null || name.Length < 2) return ("Vui lòng nhập họ tên.", false);
            if (name.Length > 100) return ("Họ tên tối đa 100 ký tự.", false);
            d.User.FullName = name;
        }
        if (r.Email != null)
        {
            var email = Norm(r.Email)?.ToLowerInvariant();
            if (email != null && !EmailRegex().IsMatch(email)) return ("Email không hợp lệ.", false);
            if (email != null && email != d.User.Email &&
                await db.Users.AnyAsync(u => u.Email == email && u.Id != d.UserId && !u.IsDeleted))
                return ("Email đã được sử dụng.", false);
            d.User.Email = email;
        }

        // ── Cá nhân + CCCD ──
        if (r.DateOfBirth is { } dob && dob != d.DateOfBirth)
        {
            var age = today.Year - dob.Year - (today < dob.AddYears(today.Year - dob.Year) ? 1 : 0);
            if (age < 18 || age > 75) return ("Tài xế phải từ 18 đến 75 tuổi.", false);
            d.DateOfBirth = dob;
            sensitive = true;
        }
        if (r.Gender != null)
        {
            var g = Norm(r.Gender)?.ToUpperInvariant();
            if (g != null && g is not ("MALE" or "FEMALE" or "OTHER")) return ("Giới tính không hợp lệ.", false);
            d.Gender = g;
        }
        if (r.Address != null)
        {
            var a = Norm(r.Address);
            if (a is { Length: > 300 }) return ("Địa chỉ tối đa 300 ký tự.", false);
            d.Address = a;
        }
        if (r.IdCardNumber != null)
        {
            var id = Norm(r.IdCardNumber);
            if (id != null && !IdCardRegex().IsMatch(id)) return ("Số CCCD/CMND phải gồm 12 (hoặc 9) chữ số.", false);
            if (id != d.IdCardNumber)
            {
                if (id != null && await db.Drivers.AnyAsync(x => x.IdCardNumber == id && x.Id != d.Id))
                    return ("Số CCCD đã được đăng ký cho tài xế khác.", false);
                d.IdCardNumber = id;
                sensitive = true;
            }
        }

        // ── GPLX ──
        if (r.LicenseNumber != null)
        {
            var ln = Norm(r.LicenseNumber)?.ToUpperInvariant();
            if (ln != null && ln != DisplayLicense(d.LicenseNumber))
            {
                if (!LicenseRegex().IsMatch(ln)) return ("Số GPLX gồm 5–20 chữ/số, không dấu cách.", false);
                if (await db.Drivers.AnyAsync(x => x.LicenseNumber == ln && x.Id != d.Id))
                    return ("Số GPLX đã tồn tại trong hệ thống.", false);
                d.LicenseNumber = ln;
                sensitive = true;
            }
        }
        if (r.LicenseClass != null)
        {
            var lc = Norm(r.LicenseClass)?.ToUpperInvariant();
            if (lc is { Length: > 10 }) return ("Hạng bằng không hợp lệ.", false);
            if (lc != d.LicenseClass) { d.LicenseClass = lc; sensitive = true; }
        }
        if (r.LicenseExpiryDate is { } exp && exp != d.LicenseExpiryDate)
        {
            if (exp < today.AddYears(-1) || exp > today.AddYears(40)) return ("Ngày hết hạn GPLX không hợp lệ.", false);
            d.LicenseExpiryDate = exp;
            sensitive = true;
        }
        if (r.DrivingExperienceYears is { } years)
        {
            if (years is < 0 or > 70) return ("Số năm kinh nghiệm không hợp lệ.", false);
            d.DrivingExperienceYears = years;
        }

        // ── Liên hệ khẩn cấp (sửa tự do) ──
        if (r.EmergencyContactName != null) d.EmergencyContactName = Norm(r.EmergencyContactName);
        if (r.EmergencyContactRelation != null) d.EmergencyContactRelation = Norm(r.EmergencyContactRelation);
        if (r.EmergencyContactPhone != null)
        {
            var p = Norm(r.EmergencyContactPhone)?.Replace(" ", "").Replace(".", "");
            if (p != null && !PhoneRegex().IsMatch(p)) return ("SĐT người liên hệ khẩn cấp không hợp lệ.", false);
            if (p != null && p == d.User.Phone) return ("SĐT liên hệ khẩn cấp phải khác SĐT của tài xế.", false);
            d.EmergencyContactPhone = p;
        }

        // ── Tài khoản nhận tiền ──
        if (r.BankName != null)
        {
            var b = Norm(r.BankName);
            if (b != d.BankName) { d.BankName = b; sensitive = true; }
        }
        if (r.BankAccountNumber != null)
        {
            var acc = Norm(r.BankAccountNumber)?.Replace(" ", "");
            if (acc != null && !BankAccountRegex().IsMatch(acc)) return ("Số tài khoản gồm 6–20 chữ số.", false);
            if (acc != d.BankAccountNumber) { d.BankAccountNumber = acc; sensitive = true; }
        }
        if (r.BankAccountHolder != null)
        {
            var h = Norm(r.BankAccountHolder)?.ToUpperInvariant();
            if (h != d.BankAccountHolder) { d.BankAccountHolder = h; sensitive = true; }
        }

        var now = DateTime.UtcNow;
        d.User.UpdatedAt = now;
        d.UpdatedAt = now;
        d.ProfileUpdatedAt = now;
        return (null, sensitive);
    }
}
