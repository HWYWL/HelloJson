# HelloJson 构建 / 安装 / 启动脚本
# 用法（在项目根目录）: powershell -ExecutionPolicy Bypass -File .\scripts\build-install.ps1 [-Mode release|debug]
param(
    [string]$Mode = "release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$env:DEVECO_SDK_HOME = "F:\OpenHarmony\command-line-tools\sdk"
$env:PATH = "F:\OpenHarmony\command-line-tools\bin;$env:PATH"
$hvigor = "F:\OpenHarmony\command-line-tools\bin\hvigorw.bat"
$hdc = "D:\Programs\HapKit\resources\toolchains\hdc.exe"
$device = "5JB0224A09000317"
$bundle = "com.yi.json"
$ability = "EntryAbility"

Write-Host "==> 构建 ($Mode)" -ForegroundColor Cyan
& $hvigor assembleHap --no-daemon -p product=default -p buildMode=$Mode
if ($LASTEXITCODE -ne 0) { throw "构建失败" }

$signed = Get-ChildItem "entry\build\default\outputs\default" -Filter "*-signed.hap" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $signed) {
    Write-Host "!! 未找到已签名 HAP：请先在 DevEco Studio 中配置调试签名（Project Structure > Signing Configs）" -ForegroundColor Yellow
    $unsigned = Get-ChildItem "entry\build\default\outputs\default" -Filter "*-unsigned.hap" | Select-Object -First 1
    Write-Host "未签名产物: $($unsigned.FullName)"
    exit 1
}

Write-Host "==> 安装 $($signed.Name)" -ForegroundColor Cyan
& $hdc -t $device install -r $signed.FullName
if ($LASTEXITCODE -ne 0) { throw "安装失败" }

Write-Host "==> 启动 $bundle" -ForegroundColor Cyan
& $hdc -t $device shell aa start -a $ability -b $bundle
Write-Host "完成" -ForegroundColor Green
