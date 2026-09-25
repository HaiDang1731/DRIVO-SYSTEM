# Tạo / cập nhật database DRIVO: chạy DRIVO_Database_V2.sql rồi lần lượt drivo-api/sql/00x_*.sql.
# Chạy lại nhiều lần vẫn an toàn (các script đều idempotent).
# Cách dùng:
#   .\setup-db.ps1                                   # SQL Server tại localhost, đăng nhập Windows, DB tên DrivoDB
#   .\setup-db.ps1 -Server "localhost\SQLEXPRESS"    # SQL Server Express
#   .\setup-db.ps1 -Server localhost -User sa -Password "MatKhau@123"   # đăng nhập bằng tài khoản SQL
#   .\setup-db.ps1 -ExportTo DRIVO_Database_Full.sql  # chỉ gộp V2 + 00x thành 1 file SQL (mở bằng SSMS chạy), không kết nối DB
param(
    [string]$Server = 'localhost',
    [string]$Database = 'DrivoDB',
    [string]$User,
    [string]$Password,
    [string]$ExportTo
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

# Gộp toàn bộ script thành 1 file (đúng thứ tự như lúc cài) để chạy tay trong SSMS / sqlcmd.
if ($ExportTo) {
    $files = @(Get-Item "$PSScriptRoot\DRIVO_Database_V2.sql") + @(Get-ChildItem "$PSScriptRoot\drivo-api\sql\00*.sql" | Sort-Object Name)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('/* =========================================================')
    [void]$sb.AppendLine('   DRIVO - toàn bộ database trong 1 file. Tự sinh bởi: .\setup-db.ps1 -ExportTo <file>')
    [void]$sb.AppendLine('   Đừng sửa tay file này: sửa DRIVO_Database_V2.sql / drivo-api/sql/00x_*.sql rồi xuất lại.')
    [void]$sb.AppendLine("   Gồm: $(($files | ForEach-Object { $_.Name }) -join ', ')")
    [void]$sb.AppendLine('   Chạy: mở bằng SQL Server Management Studio rồi bấm Execute, hoặc')
    [void]$sb.AppendLine("         sqlcmd -S localhost -E -C -I -f 65001 -i $(Split-Path $ExportTo -Leaf)")
    [void]$sb.AppendLine('   Chạy lại nhiều lần vẫn an toàn, không xóa dữ liệu.')
    [void]$sb.AppendLine('   ========================================================= */')
    foreach ($f in $files) {
        $sql = Get-Content $f.FullName -Raw -Encoding UTF8
        if ($Database -ne 'DrivoDB') { $sql = $sql -replace '\bDrivoDB\b', $Database }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("/* ======================= $($f.Name) ======================= */")
        if ($f.Name -ne 'DRIVO_Database_V2.sql') {
            [void]$sb.AppendLine("USE [$Database];")
            [void]$sb.AppendLine('GO')
        }
        [void]$sb.AppendLine($sql.TrimEnd())
        [void]$sb.AppendLine('GO')
    }
    $out = if ([IO.Path]::IsPathRooted($ExportTo)) { $ExportTo } else { Join-Path (Get-Location) $ExportTo }
    [IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "Đã xuất $($files.Count) script vào $out" -ForegroundColor Green
    exit 0
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
