# Kế hoạch Triển khai Flow Khách hàng (Customer Flow) cho DRIVO

## Mục tiêu
Xây dựng trọn vẹn luồng trải nghiệm cho **Khách hàng** từ khâu quản lý xe ô tô cá nhân, chọn lộ trình di chuyển, tính cước phí dự kiến, tạo cuốc đặt tài xế lái hộ, cho đến màn hình chờ tài xế tiếp nhận cuốc và xem lịch sử chuyến đi.

---

## User Review Required

> [!IMPORTANT]
> **Đặc thù nghiệp vụ cốt lõi của DRIVO**: Khách hàng không gọi một chiếc xe đến chở mình, mà là **gọi tài xế đến lái chính chiếc xe của khách**. Do đó:
> 1. Mỗi khách hàng cần quản lý danh sách xe của họ (`CustomerVehicles`): Biển số xe, Hãng xe (Toyota, Mazda, VinFast...), và loại hộp số (**AT - Tự động** hay **MT - Số sàn**).
> 2. Khi tạo cuốc xe, bắt buộc phải chọn chiếc xe khách muốn đưa về để tài xế biết trước thông tin và mang theo bằng lái phù hợp.

---

## Proposed Changes

### 1. Backend ASP.NET Core (`drivo-api`)

#### DTOs & Services Layer
- **[NEW] [CustomerVehicleDtos.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.Application/DTOs/Customer/CustomerVehicleDtos.cs)**
  - `CreateCustomerVehicleDto` (Brand, Model, Color, LicensePlate, VehicleType, Transmission, IsDefault).
  - `CustomerVehicleResponseDto`.
- **[NEW] [BookingDtos.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.Application/DTOs/Booking/BookingDtos.cs)**
  - `EstimateFareRequestDto` & `EstimateFareResponseDto`.
  - `CreateBookingRequestDto` & `BookingResponseDto`.
  - `CancelBookingRequestDto`.
- **[NEW] [ICustomerService.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.Application/Services/ICustomerService.cs)** & **[NEW] [CustomerService.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.Infrastructure/Services/CustomerService.cs)**
  - Quản lý danh sách xe của khách (`GetVehicles`, `AddVehicle`, `DeleteVehicle`).
- **[NEW] [IBookingService.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.Application/Services/IBookingService.cs)** & **[NEW] [BookingService.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.Infrastructure/Services/BookingService.cs)**
  - Tính toán giá cước dựa theo `PricingRules` trong CSDL (`BaseFare`, `PricePerKm`, `PricePerMinute`, phụ phí ban đêm nếu có).
  - Tạo `Booking` lưu vào Database với trạng thái ban đầu `SEARCHING_DRIVER`.
  - Hủy chuyến `CancelBooking`.
  - Lấy thông tin chuyến đi đang hoạt động (`GetActiveBooking`) và lịch sử (`GetCustomerBookings`).

#### WebApi Controllers Layer
- **[NEW] [CustomerVehicleController.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.WebApi/Controllers/CustomerVehicleController.cs)**
  - `GET /api/v1/customer/vehicles`
  - `POST /api/v1/customer/vehicles`
  - `DELETE /api/v1/customer/vehicles/{id}`
- **[NEW] [BookingController.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.WebApi/Controllers/BookingController.cs)**
  - `POST /api/v1/bookings/estimate`: Tính cước trước khi bấm đặt.
  - `POST /api/v1/bookings`: Tạo cuốc mới.
  - `GET /api/v1/bookings/active`: Lấy cuốc xe đang tìm tài xế hoặc đang chạy.
  - `POST /api/v1/bookings/{id}/cancel`: Hủy cuốc.
  - `GET /api/v1/bookings/customer-history`: Lịch sử các chuyến đã đi.
- **[MODIFY] [Program.cs](file:///e:/DRIVO%20SYSTEM/drivo-api/src/DrivoApi.WebApi/Program.cs)**: Đăng ký `ICustomerService` và `IBookingService` vào DI container.

---

### 2. Frontend Flutter Mobile (`drivo-mobile`)

#### Core & API Service
- **[MODIFY] [api_service.dart](file:///e:/DRIVO%20SYSTEM/drivo-mobile/lib/core/api_service.dart)**
  - Thêm model `CustomerVehicleModel`, `BookingModel`, `FareEstimateModel`.
  - Thêm các methods: `getCustomerVehicles()`, `addCustomerVehicle()`, `estimateFare()`, `createBooking()`, `getActiveBooking()`, `cancelBooking()`, `getCustomerHistory()`.

#### Feature: Customer Screens & Flow
- **[MODIFY] [customer_home_screen.dart](file:///e:/DRIVO%20SYSTEM/drivo-mobile/lib/features/customer/customer_home_screen.dart)**
  - **Quản lý Xe của tôi**:
    - Hiển thị danh sách xe thật của khách hàng tải từ API.
    - Dialog / BottomSheet **"+ Thêm xe mới"** (Biển số xe, Hãng xe, chọn Hộp số Tự động AT hoặc Số sàn MT).
  - **Tính giá cước**:
    - Khi khách chọn Điểm đón & Điểm đến, tự động tính khoảng cách và gọi API `/bookings/estimate` để hiển thị cước phí chi tiết (Giá mở cửa, cước km).
  - **Màn hình Trạng thái Tìm kiếm (`Searching Driver Dialog/Overlay`)**:
    - Khi bấm "Đặt tài xế ngay", gọi API `POST /bookings` tạo chuyến thật.
    - Hiển thị animation Radar đang tìm kiếm tài xế DRIVO gần nhất trong bán kính khu vực.
    - Hiển thị thông tin xe được bàn giao, biển số, điểm đón & cước phí tạm tính.
    - Cho phép khách bấm **"Hủy tìm kiếm"**.
  - **Tab Lịch sử**:
    - Hiển thị danh sách các chuyến đi thực tế đã hoàn thành hoặc đã hủy từ CSDL.

---

## Verification Plan

### 1. Kiểm tra Backend API (Automated / PowerShell)
- Gửi request thêm xe cho khách hàng `0922222222`.
- Gọi API tính cước `POST /api/v1/bookings/estimate` với lộ trình mẫu (ví dụ: 8.5 km).
- Gọi API tạo cuốc `POST /api/v1/bookings` kiểm tra bản ghi được sinh ra trong bảng `Bookings` với trạng thái `SEARCHING_DRIVER`.
- Kiểm tra API lấy cuốc active và API hủy cuốc.

### 2. Kiểm tra Mobile App (CPH1805 / Flutter)
- Chạy hot reload / hot restart trên thiết bị thật.
- Đăng nhập tài khoản khách: `0922222222` / `Drivo@123`.
- Trải nghiệm flow:
  1. Thêm một xe mới (Ví dụ: `Mazda CX-5`, Biển: `30H-999.88`, Tự động AT).
  2. Nhập điểm đón (ví dụ: "Quán Nhậu Phố Biển, Cầu Giấy") và điểm đến ("Chung cư Vinhomes Smart City").
  3. Quan sát hệ thống tự hiển thị cước ước tính.
  4. Bấm "Đặt tài xế ngay" $\rightarrow$ Hiển thị màn hình radar tìm tài xế kèm nút Hủy.
