# Tạo / cập nhật database DRIVO: chạy DRIVO_Database_V2.sql rồi lần lượt drivo-api/sql/00x_*.sql.
# Chạy lại nhiều lần vẫn an toàn (các script đều idempotent).
# Cách dùng:
#   .\setup-db.ps1                                   # SQL Server tại localhost, đăng nhập Windows, DB tên DrivoDB
#   .\setup-db.ps1 -Server "localhost\SQLEXPRESS"    # SQL Server Express
#   .\setup-db.ps1 -Server localhost -User sa -Password "MatKhau@123"   # đăng nhập bằng tài khoản SQL
param(
    [string]$Server = 'localhost',
    [string]$Database = 'DrivoDB',
    [string]$User,
    [string]$Password
)

$ErrorActionPreference = 'Stop'

function New-Conn([string]$db) {
    $auth = if ($User) { "User ID=$User;Password=$Password;" } else { 'Trusted_Connection=True;' }
    $c = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Database=$db;${auth}TrustServerCertificate=True;")
    $c.Open()
    return $c
}

function Invoke-SqlFile($conn, [string]$path, [string]$replaceDbWith) {
    $sql = Get-Content $path -Raw -Encoding UTF8
    if ($replaceDbWith) { $sql = $sql -replace '\bDrivoDB\b', $replaceDbWith }
    foreach ($batch in ($sql -split '(?m)^\s*GO\s*$')) {
        if ($batch.Trim().Length -eq 0) { continue }
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $batch
        $cmd.CommandTimeout = 300
        [void]$cmd.ExecuteNonQuery()
    }
}

try {
    Write-Host "SQL Server: $Server  |  Database: $Database" -ForegroundColor Cyan

    Write-Host '-> DRIVO_Database_V2.sql (tạo database, bảng, dữ liệu gốc)'
    $master = New-Conn 'master'
    Invoke-SqlFile $master "$PSScriptRoot\DRIVO_Database_V2.sql" $Database
    $master.Close()

    $conn = New-Conn $Database
    foreach ($f in Get-ChildItem "$PSScriptRoot\drivo-api\sql\00*.sql" | Sort-Object Name) {
        Write-Host "-> $($f.Name)"
        Invoke-SqlFile $conn $f.FullName $null
    }
    $conn.Close()

    Write-Host ''
    Write-Host 'Xong! Tài khoản admin: admin@drivo.local / Admin@123 (đổi mật khẩu sau khi đăng nhập).' -ForegroundColor Green
    if ($Server -ne 'localhost' -or $Database -ne 'DrivoDB' -or $User) {
        Write-Host 'Lưu ý: sửa ConnectionStrings:DefaultConnection trong drivo-api/src/DrivoApi.WebApi/appsettings.json cho khớp.' -ForegroundColor Yellow
    }
}
catch {
    Write-Host "LỖI: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
