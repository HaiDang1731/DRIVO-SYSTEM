# Chạy app mobile, tự dò IP LAN hiện tại của máy tính để app gọi được API.
# Cách dùng:
#   .\run-mobile.ps1                 # chọn thiết bị (Flutter sẽ hỏi nếu có nhiều)
#   .\run-mobile.ps1 -Device web     # bản web, mở http://localhost:5001 ở trình duyệt bất kỳ
#   .\run-mobile.ps1 -Device chrome  # bản web trong cửa sổ Chrome do Flutter mở (chỉ cửa sổ đó chạy được)
#   .\run-mobile.ps1 -Device 4cc939c2
#   .\run-mobile.ps1 -ApiHost 192.168.1.10   # tự chỉ định IP
param(
    [string]$Device,
    [string]$ApiHost
)

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

$flutterArgs = @('run', "--dart-define=API_HOST=$ApiHost")

if ($Device) { $flutterArgs += @('-d', $Device) }
if ($Device -in @('chrome', 'edge', 'web-server')) { $flutterArgs += @('--web-port', '5001') }
if ($Device -eq 'web-server') {
    $flutterArgs += @('--web-hostname', '0.0.0.0')
    Write-Host "Mở http://localhost:5001 (hoặc http://${ApiHost}:5001 từ máy khác)" -ForegroundColor Cyan
}

Push-Location "$PSScriptRoot\drivo-mobile"
try { flutter @flutterArgs } finally { Pop-Location }

