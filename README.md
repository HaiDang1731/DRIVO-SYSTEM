# DRIVO: dịch vụ thuê tài xế lái hộ

Hệ thống gồm 3 phần, chạy trên máy Windows:

| Thư mục | Là gì | Công nghệ | Địa chỉ khi chạy |
|---|---|---|---|
| `drivo-api` | Máy chủ API + realtime | ASP.NET Core 9, SQL Server | http://localhost:5270 |
| `drivo-admin` | Trang quản trị | React + Vite | http://localhost:5173 |
| `drivo-mobile` | App khách hàng & tài xế | Flutter | http://localhost:5001 (bản web) hoặc cài lên điện thoại Android |

## 1. Cài phần mềm (một lần)

| Phần mềm | Phiên bản | Ghi chú |
|---|---|---|
| [SQL Server](https://www.microsoft.com/sql-server/sql-server-downloads) | 2019 trở lên (bản Developer hoặc Express đều được) | Nên cài kèm SQL Server Management Studio để xem dữ liệu |
| [.NET SDK](https://dotnet.microsoft.com/download/dotnet/9.0) | 9.0 | Kiểm tra: `dotnet --version` |
| [Node.js](https://nodejs.org) | 20 trở lên | Kiểm tra: `node --version` |
| [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) | 3.41 trở lên (Dart 3.11) | Kiểm tra: `flutter doctor` |
| Android Studio | Bất kỳ | Chỉ cần nếu chạy app trên điện thoại Android |

Lần đầu chạy file `.ps1`, nếu PowerShell báo *"running scripts is disabled"*, mở PowerShell và chạy:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 2. Lấy code và tạo database

```powershell
git clone https://github.com/HaiDang1731/DRIVO-SYSTEM.git
cd DRIVO-SYSTEM
git checkout haidang174

.\setup-db.ps1
```

`setup-db.ps1` tạo database `DrivoDB`, gồm các bảng, bảng giá cước, 3 mã khuyến mãi mẫu và tài khoản admin. Mặc định script kết nối SQL Server ở `localhost` và đăng nhập bằng tài khoản Windows.

- Nếu cài **SQL Server Express**: `.\setup-db.ps1 -Server "localhost\SQLEXPRESS"`
- Nếu đăng nhập bằng **tài khoản SQL**: `.\setup-db.ps1 -User sa -Password "MatKhau"`
- Không chạy được PowerShell? Mở file **`DRIVO_Database_Full.sql`** bằng SQL Server Management Studio rồi bấm *Execute*. File này gộp sẵn `DRIVO_Database_V2.sql` và toàn bộ `drivo-api/sql/00x_*.sql`, có kết quả giống hệt `setup-db.ps1`. Mỗi khi thêm file `00x` mới, tạo lại file này bằng lệnh `.\setup-db.ps1 -ExportTo DRIVO_Database_Full.sql`.

Trong hai trường hợp này, sửa thêm chuỗi kết nối trong `drivo-api/src/DrivoApi.WebApi/appsettings.json` cho khớp:

```json
"DefaultConnection": "Server=localhost\\SQLEXPRESS;Database=DrivoDB;Trusted_Connection=True;TrustServerCertificate=True;"
```

## 3. Chạy hệ thống

Mở **3 cửa sổ PowerShell** ở thư mục gốc dự án, mỗi cửa sổ chạy một phần:

**Cửa sổ 1: API**
```powershell
.\run-api.ps1
```
Chờ tới khi thấy dòng `Now listening on: http://0.0.0.0:5270`. Mở http://localhost:5270/swagger để xem danh sách API.

**Cửa sổ 2: Trang quản trị**
```powershell
cd drivo-admin
npm install      # chỉ cần lần đầu, hoặc khi package.json thay đổi
npm run dev
```
Mở http://localhost:5173 và đăng nhập bằng tài khoản admin ở mục 4.

**Cửa sổ 3: App mobile**
```powershell
.\run-mobile.ps1 -Device web          # bản web: mở http://localhost:5001
.\run-mobile.ps1 -Device <mã-máy>     # điện thoại Android thật (xem mã bằng: flutter devices)
```
Lần đầu build mất vài phút. Script tự dò IP mạng LAN của máy tính để điện thoại gọi được API. Điện thoại cần **dùng chung Wi-Fi** với máy tính. Khi app đang chạy, bấm `r` trong cửa sổ này để cập nhật sau khi sửa code.

## 4. Tài khoản

| Vai trò | Đăng nhập | Mật khẩu |
|---|---|---|
| Admin | `admin@drivo.local` | `Admin@123` (nên đổi sau khi đăng nhập) |
| Khách hàng | Tự đăng ký trong app | |
| Tài xế | Tự đăng ký trong app, hoặc admin tạo ở trang **Tài xế** | Admin tạo: mật khẩu mặc định là số điện thoại |

**Để tài xế nhận được cuốc**, cần đủ 3 điều kiện:

1. Admin **duyệt hồ sơ** tài xế (trang **Tài xế → Duyệt**).
2. **Ví tài xế có ít nhất 500.000đ.** Tài xế bấm *Ví → Nạp tiền* trên app, rồi admin vào trang **Ví tài xế** bấm Duyệt. Hoặc admin bấm *Điều chỉnh* để cộng tiền thẳng.
3. Tài xế **bật trực tuyến** và cho phép app truy cập vị trí.

## 5. Khi kéo code mới về

```powershell
git pull
.\setup-db.ps1          # cập nhật cấu trúc database (an toàn, không xóa dữ liệu)
cd drivo-admin; npm install; cd ..
```

Sau đó chạy lại 3 cửa sổ ở mục 3.

## 6. Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| `setup-db.ps1` báo *"server was not found"* | Sai tên SQL Server. Xem tên trong SQL Server Management Studio (thường là `localhost` hoặc `localhost\SQLEXPRESS`) và truyền vào tham số `-Server` |
| API báo lỗi *"Cannot open database DrivoDB"* | Chưa chạy `setup-db.ps1`, hoặc chuỗi kết nối trong `appsettings.json` không khớp |
| App trên điện thoại không kết nối được API | Điện thoại và máy tính phải chung Wi-Fi. Cho phép cổng **5270** qua Windows Firewall |
| Bản đồ trống hoặc không tìm được địa chỉ | Cần Internet. Một số mạng (mạng công ty, trường học) chặn máy chủ bản đồ OpenStreetMap |
| Trang admin hoặc mobile web hiện bản cũ | Bấm **Ctrl + Shift + R** |
| Tài xế không bật được trực tuyến | Xem điều kiện ở mục 4 (đã duyệt hồ sơ, ví ≥ 500.000đ) |

## Tài liệu khác

- [docs/bang-gia-cuoc.md](docs/bang-gia-cuoc.md): cách tính giá cước, voucher, hoa hồng.
- [DRIVO_SYSTEM_FLOW.md](DRIVO_SYSTEM_FLOW.md): luồng nghiệp vụ tổng thể.
