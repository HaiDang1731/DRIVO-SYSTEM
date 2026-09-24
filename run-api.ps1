# Chạy API ở chế độ Development, nhận kết nối từ mạng LAN (để điện thoại gọi được).
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:ASPNETCORE_URLS = 'http://0.0.0.0:5270'

Push-Location "$PSScriptRoot\drivo-api\src\DrivoApi.WebApi"
try { dotnet run --no-launch-profile } finally { Pop-Location }
