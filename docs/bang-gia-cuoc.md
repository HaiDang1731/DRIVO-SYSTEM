# Cách tính giá cước DRIVO

Tài liệu này giải thích cách hệ thống tính số tiền khách trả cho một chuyến và cách chia số tiền đó giữa nền tảng DRIVO và tài xế. Mọi con số đều lấy từ **bảng giá cước** mà admin cấu hình ở trang *Bảng giá cước*.

## Bối cảnh dịch vụ

DRIVO là dịch vụ **thuê tài xế lái hộ chính xe của khách**, dùng khi khách uống rượu bia, bận việc hoặc không tự lái được. Một chuyến gồm 2 chặng:

1. **Chặng đón:** tài xế đi **xe điện gấp** của công ty cấp từ vị trí hiện tại tới chỗ khách. Tới nơi, tài xế gấp xe bỏ vào cốp xe của khách.
2. **Chặng chính:** tài xế lái xe của khách từ điểm đón tới điểm đến.

Giá cước cần trả công cho cả 2 chặng và cả thời gian tài xế phải chờ khách.

## Tổng quan: giá cuối cùng gồm những gì

```
Giá cuối = Cước chặng chính + Phí đón + Phí chờ + Phí vượt quãng đường − Giảm giá
```

| Khoản | Tính lúc nào | Mục đích |
|---|---|---|
| Cước chặng chính | Lúc khách đặt xe (giá ước tính) | Trả công lái xe từ điểm đón tới điểm đến |
| Phí đón | Lúc tài xế nhận cuốc | Bù công tài xế đi xe điện tới chỗ khách khi ở xa |
| Phí chờ | Lúc hoàn thành chuyến | Bù thời gian tài xế phải đợi khách ở điểm đón |
| Phí vượt quãng đường | Lúc hoàn thành chuyến | Thu thêm khi quãng đường thực tế dài hơn dự kiến đáng kể |
| Giảm giá | Lúc đặt xe | Voucher khuyến mãi khách nhập khi đặt xe (xem mục 5) |

Khi chuyến hoàn thành, **giá cuối được chia** giữa nền tảng và tài xế theo tỉ lệ hoa hồng (xem mục 6).

**Quy tắc làm tròn:** mọi khoản tiền được làm tròn tới 1.000đ gần nhất. Riêng từ 500đ trở lên thì làm tròn lên, ví dụ 7.500đ thành 8.000đ.

---

## 1. Cước chặng chính (giá ước tính)

```
Cước chặng chính = Phí mở cửa
                 + max(0, km − 2) × Giá/km
                 + Số phút × Giá/phút
                 + Phụ phí đêm (nếu đặt từ 22h đến 6h)
```

Tổng được làm tròn một lần ở cuối. Khách thấy con số này trên màn đặt xe.

| Thành phần | Ý nghĩa | Mục đích |
|---|---|---|
| **Phí mở cửa** | Khoản cố định cho mỗi chuyến, **đã bao gồm 2 km đầu** | Chuyến ngắn vẫn đủ bù công tài xế: dù chỉ đi 1 km, tài xế vẫn phải đi xe điện tới, gấp xe, lái xe rồi tự về |
| **Giá/km** | Tính từ km thứ 3 trở đi | Chuyến càng xa, tài xế làm càng lâu thì trả càng nhiều |
| **Giá/phút** | Nhân với **số phút dự kiến** của lộ trình | Bù công khi đường ngắn nhưng tắc (giờ cao điểm). Dùng số phút dự kiến, không dùng số phút thực tế, nên khách không bị tính thêm khi kẹt xe |
| **Phụ phí đêm** | Cộng thêm khi khách đặt xe từ 22h đến 6h (giờ Việt Nam) | Làm việc ban đêm vất vả hơn và ít tài xế sẵn sàng |

**Số km và số phút** lấy từ dịch vụ định tuyến miễn phí OSRM, theo đường đi thực tế trên bản đồ. Nếu OSRM không phản hồi, hệ thống ước tính bằng khoảng cách đường chim bay × 1,3.

## 2. Phí đón (chặng xe điện)

```
Phí đón = max(0, km đón − Km đón miễn phí) × Phí đón/km
```

- **Km đón** là quãng đường từ vị trí tài xế tới điểm đón, tính **lúc tài xế bấm nhận cuốc**.
- Trong phạm vi *Km đón miễn phí* thì không thu. Chỉ phần vượt mới tính tiền.
- **Mục đích:** khi xung quanh không có tài xế gần, khách vẫn đặt được xe và tài xế ở xa vẫn có động lực nhận cuốc, vì quãng xe điện dài được trả thêm.
- Lúc khách đặt xe, app hiện trước **phí đón dự kiến**, tính theo tài xế đang trực tuyến gần nhất.

## 3. Phí chờ

```
Phí chờ = max(0, phút chờ − Phút chờ miễn phí) × Phí chờ/phút
```

- **Phút chờ** được đếm từ lúc tài xế bấm *"Đã đến điểm đón"* tới lúc bấm *"Bắt đầu chạy"*. Số phút lẻ được bỏ, ví dụ chờ 12 phút 50 giây tính là 12 phút.
- **Phút chờ miễn phí** do admin đặt riêng cho từng loại xe ở trang *Bảng giá cước*, **không cố định 10 phút**.
- **Mục đích:** khách có một khoảng miễn phí để chuẩn bị. Quá thời gian đó thì tài xế được trả cho thời gian chờ và không thể nhận cuốc khác.

**Chờ khách tại điểm đón:**

1. Từ lúc tài xế bấm *"Đã đến điểm đón"*, cả app khách và app tài xế hiện **đồng hồ đếm ngược** thời gian chờ miễn phí.
2. Hết thời gian miễn phí, đồng hồ chuyển sang **"Đang tính phí chờ X đ/phút"** và hiện số tiền phí chờ tăng dần theo thời gian thực.
3. Tài xế gọi xác nhận với khách, sau đó chọn một trong hai:
   - **"Khách vẫn đi, chờ tiếp":** khách nhận thông báo *"Tài xế tiếp tục chờ bạn, phí chờ đang được tính"*. Phí chờ tiếp tục tính cho tới lúc bắt đầu chạy.
   - **Hủy chuyến vì khách vắng mặt / không giao xe:** không trừ tỉ lệ hoàn thành của tài xế (xem mục 8).

Phí chờ luôn được tính theo công thức trên, dù tài xế có bấm *"Khách vẫn đi, chờ tiếp"* hay không. Nút này chỉ để báo cho khách biết.

## 4. Phí vượt quãng đường

```
Nếu  km thực tế > km dự kiến × (1 + Dung sai %)
thì  Phí vượt = (km thực tế − km dự kiến) × Giá/km
còn không  Phí vượt = 0
```

- **Km thực tế** được đo bằng GPS của tài xế trong lúc chạy. Hệ thống bỏ các điểm GPS sai số trên 50 m và các đoạn có tốc độ vô lý (trên 150 km/h).
- **Dung sai** cho phép lệch một chút mà không thu thêm, vì đường vòng hay GPS sai lệch nhỏ là bình thường.
- Khi đã vượt dung sai, **toàn bộ phần chênh** so với km dự kiến đều bị tính tiền, không chỉ phần vượt ngưỡng.
- **Mục đích:** khách đổi điểm đến giữa đường hoặc yêu cầu đi vòng thì tài xế được trả đúng công. Còn chênh lệch nhỏ thì khách không bị thu.

## 5. Giá cuối cùng

Giá cuối được **chốt khi tài xế bấm "Hoàn thành chuyến"**:

```
Giá cuối = Cước chặng chính + Phí đón + Phí chờ + Phí vượt quãng đường − Giảm giá
```

**Giảm giá (voucher)** được chốt **lúc đặt xe**, tính trên cước chặng chính:

| Loại mã | Số tiền giảm |
|---|---|
| Theo % (`PERCENT`) | Cước chặng chính × %, làm tròn 1.000đ, không vượt *mức giảm tối đa* |
| Số tiền cố định (`FIXED`) | Đúng số tiền của mã |

- Mã chỉ dùng được khi: đang bật, còn trong thời hạn, còn lượt, và cước chặng chính đạt *đơn tối thiểu*.
- Mỗi khách chỉ dùng một mã **một lần**. Nếu chuyến bị hủy, lượt dùng được trả lại cho cả khách và mã.
- Tiền giảm không bao giờ lớn hơn cước chặng chính.

**Thanh toán:** khi chuyến hoàn thành, hệ thống tạo bản ghi thanh toán bằng đúng giá cuối (xem ở trang *Thanh toán* trên admin). Khách chọn tiền mặt thì tài xế thu tại chỗ. Ví điện tử và chuyển khoản QR hiện là **giả lập**, luôn được ghi là đã thanh toán thành công.

## 6. Chia doanh thu: nền tảng và tài xế

```
Giá trước giảm    = Giá cuối + Giảm giá
Hoa hồng DRIVO    = Giá trước giảm × Hoa hồng %     (làm tròn 1.000đ)
Tài xế thực nhận  = Giá trước giảm − Hoa hồng DRIVO
DRIVO thực thu    = Giá cuối − Tài xế thực nhận  (= Hoa hồng − Giảm giá, có thể âm)
```

**Tiền voucher do DRIVO chịu toàn bộ.** Tài xế luôn nhận đủ như khi khách không dùng mã. Khi khách trả tiền mặt, tài xế thu *Giá cuối* rồi được DRIVO bù phần giảm giá.

- **Hoa hồng %** được đặt riêng cho từng loại xe, hiện đều là **15%**.
- Hoa hồng tính trên **toàn bộ giá trước giảm**, gồm cả phí đón, phí chờ và phí vượt quãng đường.
- **Mục đích:** nền tảng có doanh thu để vận hành (xe điện gấp, bảo hiểm, máy chủ, chăm sóc khách hàng). Tài xế giữ phần lớn tiền cước.
- Thu nhập tài xế trong app và ở trang admin (*Thống kê thu nhập*) là phần **thực nhận**, không phải toàn bộ giá cuối.

## 7. Bảng giá áp dụng cho chuyến nào

- Khi khách đặt xe, hệ thống lấy bảng giá **đang bật và đang trong thời gian hiệu lực** của loại xe đó, rồi **lưu lại cho chuyến**.
- Mọi khoản tính sau đó, gồm phí đón, phí chờ, phí vượt và hoa hồng, đều dùng **đúng bảng giá đã lưu**.
- Vì vậy khi admin sửa bảng giá, **các chuyến đặt trước đó vẫn tính theo giá cũ**. Khách không bị đổi giá giữa chừng.
- Nếu không có bảng giá nào đang bật, hệ thống dùng bảng giá mặc định cài sẵn trong code.

## 8. Hủy chuyến

Hiện **không thu phí hủy** ở cả hai phía. Khi hủy, khách và tài xế đều phải chọn lý do. Lý do được lưu kèm chuyến, và bên còn lại nhận thông báo có ghi lý do. Nếu chuyến đã áp voucher thì lượt dùng được trả lại (mục 5).

Mỗi lần hủy được ghi nhận là **có hoặc không tính lỗi tài xế**. Chỉ những lần hủy tính lỗi mới làm giảm **tỉ lệ hoàn thành** của tài xế.

**Khách hủy:**

| Lý do | Tính lỗi tài xế |
|---|---|
| Thay đổi kế hoạch | Không |
| Chờ tài xế quá lâu | Không |
| Đặt nhầm địa chỉ | Không |
| Lý do khác (bắt buộc ghi rõ) | Không |
| **Tài xế yêu cầu tôi hủy** | **Có**, để chặn trường hợp tài xế nhờ khách hủy hộ nhằm tránh bị trừ tỉ lệ |

**Tài xế hủy:**

| Lý do | Điều kiện | Tính lỗi tài xế |
|---|---|---|
| Khách không có mặt | Đã đến điểm đón **và** đã chờ hết thời gian chờ miễn phí | Không |
| Không nhận được xe của khách | Đã đến điểm đón **và** đã chờ hết thời gian chờ miễn phí | Không |
| Khách báo không đi nữa | Đã đến điểm đón (không cần chờ hết thời gian miễn phí) | Không |
| Tài xế có việc cá nhân | Bất kỳ lúc nào trước khi bắt đầu chạy | Có |
| Xe điện gấp gặp sự cố | Bất kỳ lúc nào trước khi bắt đầu chạy | Có |
| Lý do khác (bắt buộc ghi rõ) | Bất kỳ lúc nào trước khi bắt đầu chạy | Có |

Khi chuyến đang chạy thì tài xế không thể hủy. Server tự kiểm tra lại các điều kiện trên, nên dù app gửi yêu cầu sai thì cũng bị từ chối.

**Tỉ lệ hoàn thành của tài xế** (tính trong 30 ngày gần nhất):

```
Tỉ lệ hoàn thành = Chuyến hoàn thành / (Chuyến hoàn thành + Lần hủy tính lỗi tài xế)
```

- Tài xế có dưới 3 chuyến thì chưa đủ dữ liệu. Khi điều phối, hệ thống tạm tính tài xế đó ở mức 90%.
- Tỉ lệ này chiếm **20% điểm xếp hạng** khi điều phối cuốc. 80% còn lại gồm 60% khoảng cách và 20% số sao đánh giá.
- Admin xem tỉ lệ ở trang *Tài xế* (cột *Tỉ lệ hoàn thành*) và trong chi tiết tài xế (tab *Tỉ lệ hoàn thành & hủy*, liệt kê từng lần hủy kèm lý do).

---

## Bảng giá hiện tại

Số liệu lấy từ database ngày 24/09/2026.

| Tham số | Motorbike | Car | SUV |
|---|---|---|---|
| Phí mở cửa (gồm 2 km đầu) | 30.000đ | 50.000đ | 60.000đ |
| Giá/km (từ km thứ 3) | 10.000đ | 15.000đ | 18.000đ |
| Giá/phút | 0đ | 0đ | 0đ |
| Hoa hồng DRIVO | 15% | 15% | 15% |

Hiện **Giá/phút = 0đ** cho mọi loại xe, nên cước thời gian chưa được thu. Các tham số còn lại (phụ phí đêm, km đón miễn phí, phí đón/km, phút chờ miễn phí, phí chờ/phút, dung sai) xem trực tiếp ở trang *Bảng giá cước*. Ví dụ dưới đây dùng đúng giá xe Car hiện tại.

## Ví dụ minh họa (xe Car)

Tham số xe Car: phí mở cửa 50.000đ, giá/km 15.000đ, giá/phút 0đ, km đón miễn phí 3 km, phí đón 5.000đ/km, phút chờ miễn phí 10 phút, phí chờ 1.500đ/phút, dung sai 10%, hoa hồng 15%.

**Tình huống:** khách đặt lúc 20h, quãng đường dự kiến 6,6 km (khoảng 10 phút). Tài xế ở cách 4,2 km, khách ra muộn làm tài xế chờ 15 phút, và giữa đường khách đổi lộ trình nên thực tế chạy 7,5 km.

| Bước | Cách tính | Số tiền |
|---|---|---|
| Phí mở cửa | | 50.000đ |
| Cước km | (6,6 − 2) × 15.000 | 69.000đ |
| Cước phút | 10 × 0 | 0đ |
| Phụ phí đêm | 20h, không phải giờ đêm | 0đ |
| **Cước chặng chính** | | **119.000đ** |
| Phí đón | (4,2 − 3) × 5.000 | 6.000đ |
| Phí chờ | (15 − 10) × 1.500 = 7.500, làm tròn | 8.000đ |
| Phí vượt quãng đường | ngưỡng 6,6 × 1,1 = 7,26 km; 7,5 > 7,26 nên (7,5 − 6,6) × 15.000 = 13.500, làm tròn | 14.000đ |
| **Giá cuối (khách trả)** | 119.000 + 6.000 + 8.000 + 14.000 | **147.000đ** |
| Hoa hồng DRIVO | 147.000 × 15% = 22.050, làm tròn | 22.000đ |
| **Tài xế thực nhận** | 147.000 − 22.000 | **125.000đ** |

Có thể kiểm tra lại ví dụ bằng **máy tính thử giá** ở trang *Bảng giá cước*.

## Mã nguồn liên quan

- Tính giá ước tính, phí đón, phí chờ, phí vượt, hoa hồng: `drivo-api/src/DrivoApi.Infrastructure/BookingService.cs` (`ComputeEstimateAsync`, `AcceptBookingAsync`, `CompleteBookingAsync`)
- Làm tròn và khoảng cách: `drivo-api/src/DrivoApi.Application/Common/GeoUtils.cs`
- Cấu hình bảng giá: `drivo-admin/src/pages/PricingPage.tsx`
- Voucher và thanh toán: `BookingService.cs` (`ResolveVoucherAsync`, `CreateBookingAsync`, `CompleteBookingAsync`)
- Hủy chuyến, chờ khách: `BookingService.cs` (`CancelBookingAsync`, `CancelBookingByDriverAsync`, `KeepWaitingAsync`), app: `drivo-mobile/lib/core/widgets/trip_cancel_wait.dart`
- Tỉ lệ hoàn thành: `drivo-api/src/DrivoApi.Infrastructure/DriverCompletionStats.cs`
- Cột database: `drivo-api/sql/002_maps_tracking_pricing.sql`, `drivo-api/sql/003_commission.sql`, `drivo-api/sql/004_payments_vouchers.sql`, `drivo-api/sql/008_cancel_fault_waiting.sql`
