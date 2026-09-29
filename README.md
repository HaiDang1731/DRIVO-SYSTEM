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

### **Cửa sổ 3: App Mobile**

Mở **Android Studio** để khởi động thiết bị chạy ứng dụng:
* **Android Virtual Device (AVD):** chạy app trên thiết bị Android ảo.
* **Thiết bị Android thật:** kết nối điện thoại với máy tính để test trực tiếp trên thiết bị.
* **Web:** có thể chạy phiên bản Web trên trình duyệt để test giao diện và chức năng.

> **Lưu ý về GPS:**
> Android Emulator không có GPS vật lý nên không thể lấy vị trí GPS thực tế của máy tính. Khi cần test GPS thực tế, nên sử dụng **thiết bị Android thật**.
> Với Emulator, có thể **cấu hình vị trí GPS giả lập** để test các chức năng liên quan đến vị trí.
------------

### **3.1. Kiểm tra thiết bị Flutter**

Sau khi mở AVD hoặc kết nối điện thoại Android thật, chạy:

```powershell
flutter devices
```
Ví dụ:

```text
4cc939c2       • Android  • Android  • Android 15 (Thiết bị thật)
emulator-5554  • Android  • Android  • Android 15 (Máy ảo 1)
emulator-5556  • Android  • Android  • Android 15 (Máy ảo 2)
```
---
### **3.2. Cấu hình GPS cho Android Emulator**

Có thể cấu hình vị trí GPS cho Emulator bằng **Extended Controls** của Android Studio.
Trong cửa sổ Emulator:
**`⋮` → `Extended Controls` → `Location`**

Nhập:
* **Latitude:** vĩ độ
* **Longitude:** kinh độ

Ví dụ vị trí trung tâm Hà Nội:

```text
Latitude:  21.0278
Longitude: 105.8412
```

Sau đó nhấn **Set location** để áp dụng.
Có thể kiểm tra lại vị trí bằng Google Maps hoặc chức năng lấy vị trí trong app DRIVO.

#### Cấu hình GPS bằng PowerShell

Có thể dùng ADB để đặt vị trí trực tiếp:

```powershell
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" `
    -s emulator-5554 `
    emu geo fix 105.8412 21.0278
```
> **Lưu ý:** `geo fix` nhận tham số theo thứ tự **Longitude → Latitude**.

Ví dụ:

```text
Longitude: 105.8412
Latitude:  21.0278
```

Nếu có nhiều Emulator, thay `emulator-5554` bằng mã thiết bị tương ứng:

```powershell
emulator-5554
emulator-5556
emulator-5558
```

Có thể kiểm tra danh sách thiết bị bằng:

```powershell
adb devices
```

hoặc:

```powershell
flutter devices
```

---

### **3.3. Chạy ứng dụng Mobile**

Sau khi thiết bị đã được khởi động và cấu hình GPS nếu cần:

```powershell
# Bản Web: mở http://localhost:5001
.\run-mobile.ps1 -Device web

# Android Emulator
.\run-mobile.ps1 -Device emulator-5554

# Android thật
.\run-mobile.ps1 -Device <mã-máy>
```
Mã thiết bị có thể xem bằng:
```powershell
flutter devices
```
Ví dụ:
```powershell
.\run-mobile.ps1 -Device 4cc939c2
```
---
### **3.4. Lưu ý khi chạy trên điện thoại Android thật**

* Lần đầu build có thể mất vài phút.
* Script sẽ tự động dò **IP LAN của máy tính** để điện thoại có thể gọi API.
* Điện thoại và máy tính cần **kết nối cùng mạng Wi-Fi/LAN**.
* Nếu API không kết nối được, kiểm tra IP máy tính và Firewall.
* Khi app đang chạy, nhấn `r` trong cửa sổ terminal để **Hot Reload** sau khi sửa code.

### **3.5. Chạy nhiều Emulator để test DRIVO**

Có thể mở nhiều AVD cùng lúc:

```text
emulator-5554 → Tài xế 1
emulator-5556 → Tài xế 2
emulator-5558 → Khách Hàng
```

Sau đó đặt mỗi Emulator một vị trí GPS khác nhau để test chức năng **tìm và ghép tài xế gần khách hàng**.

Ví dụ:

```powershell
# Tài xế 1
.\run-mobile.ps1 -Device emulator-5554 -Lat 21.0278 -Lng 105.8412

# Tài xế 2
.\run-mobile.ps1 -Device emulator-5556 -Lat 21.0326 -Lng 105.8431

# Khách hàng
.\run-mobile.ps1 -Device emulator-5558 -Lat 21.0200 -Lng 105.8350
```

Lúc này mỗi Emulator sẽ gửi một vị trí khác nhau, thuận tiện để kiểm tra **GPS, khoảng cách và chức năng tìm tài xế gần nhất của DRIVO**.


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
