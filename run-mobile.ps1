# Chạy app mobile, tự dò IP LAN hiện tại của máy tính để app gọi được API.
# Cách dùng:
#   .\run-mobile.ps1                 # chọn thiết bị (Flutter sẽ hỏi nếu có nhiều)
#   .\run-mobile.ps1 -Device web     # bản web, mở http://localhost:5001 ở trình duyệt bất kỳ
#   .\run-mobile.ps1 -Device chrome  # bản web trong cửa sổ Chrome do Flutter mở (chỉ cửa sổ đó chạy được)
#   .\run-mobile.ps1 -Device 4cc939c2
#   .\run-mobile.ps1 -ApiHost 192.168.1.10        # tự chỉ định IP
#   .\run-mobile.ps1 -Lat 21.0278 -Lng 105.8412   # tự chỉ định vị trí giả lập (chỉ máy ảo)
param(
    [string]$Device,
    [string]$ApiHost,
    [double]$Lat = 21.0278,   # Mặc định: trung tâm Hà Nội
    [double]$Lng = 105.8412
)

# Tìm adb.exe (ưu tiên ANDROID_HOME, fallback về vị trí mặc định)
$adb = if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe' }
       else { "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" }

if (-not $ApiHost) {
    # Lấy IPv4 của card mạng đang có default gateway (Wi-Fi/Ethernet đang dùng)
    $ApiHost = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1 -ExpandProperty IPv4Address |
        Select-Object -ExpandProperty IPAddress
}
if (-not $ApiHost) {
    Write-Error "Không dò được IP mạng. Hãy truyền -ApiHost <IP>."
    exit 1
}

Write-Host "API: http://${ApiHost}:5270/api/v1" -ForegroundColor Cyan

if ($Device -eq 'web') { $Device = 'web-server' }

# Tự động đặt vị trí cho máy ảo (emulator không có GPS thật)
if (Test-Path $adb) {
    if ($Device -match '^emulator-') {
        Write-Host "Đặt vị trí giả lập: lat=$Lat lng=$Lng → $Device" -ForegroundColor Yellow
        & $adb -s $Device emu geo fix $Lng $Lat
    } elseif (-not $Device -or $Device -eq '') {
        # Không chỉ định thiết bị → đặt cho tất cả emulator đang chạy
        $emulators = & $adb devices | Select-String '^emulator-' | ForEach-Object { ($_ -split '\s+')[0] }
        foreach ($emu in $emulators) {
            Write-Host "Đặt vị trí giả lập: lat=$Lat lng=$Lng → $emu" -ForegroundColor Yellow
            & $adb -s $emu emu geo fix $Lng $Lat
        }
    }
} else {
    Write-Warning "Không tìm thấy adb.exe tại: $adb — bỏ qua set vị trí."
}

$flutterArgs = @('run', "--dart-define=API_HOST=$ApiHost")

if ($Device) { $flutterArgs += @('-d', $Device) }
if ($Device -in @('chrome', 'edge', 'web-server')) { $flutterArgs += @('--web-port', '5001') }
if ($Device -eq 'web-server') {
    $flutterArgs += @('--web-hostname', '0.0.0.0')
    Write-Host "Mở http://localhost:5001 (hoặc http://${ApiHost}:5001 từ máy khác)" -ForegroundColor Cyan
}

Push-Location "$PSScriptRoot\drivo-mobile"
try { flutter @flutterArgs } finally { Pop-Location }
