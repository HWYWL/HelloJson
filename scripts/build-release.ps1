# HelloJson 发布包构建：release 编译 + Release 证书/profile 签名 + 签名校验
# 用法: powershell -ExecutionPolicy Bypass -File .\scripts\build-release.ps1
#       可选参数: -Password "<p12密码>" -VersionCode <n> -VersionName <x.y.z>
param(
    [string]$Password = "whfR>;O4K@-CkUMdI=",
    [string]$KeyDir = "F:\OpenHarmony\Key\HelloJson\Release",
    [string]$KeyAlias = "hellojson",
    [string]$ProfileName = "HelloJsonRelease.p7b"
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$env:DEVECO_SDK_HOME = "F:\OpenHarmony\command-line-tools\sdk"
$env:PATH = "F:\OpenHarmony\command-line-tools\bin;$env:PATH"
$hvigor = "F:\OpenHarmony\command-line-tools\bin\hvigorw.bat"
$java = "D:\Program Files\JDK\jdk1.8.0_503\bin\java.exe"
$signTool = "F:\OpenHarmony\Sdk\26.0.0\toolchains\lib\hap-sign-tool.jar"
$outDir = Join-Path $root "build-output"

function Fail([string]$msg) {
    Write-Host ""
    Write-Host "!! $msg" -ForegroundColor Red
    exit 1
}

Write-Host "==> 检查签名材料 $KeyDir" -ForegroundColor Cyan
if (-not (Test-Path $KeyDir)) { Fail "签名目录不存在: $KeyDir" }
$p12 = Get-ChildItem $KeyDir -Filter "*.p12" -ErrorAction SilentlyContinue | Select-Object -First 1
$cer = Get-ChildItem $KeyDir -Filter "*.cer" -ErrorAction SilentlyContinue |
    Where-Object { $_.BaseName -notmatch "rootCA|subCA" } | Select-Object -First 1
$profile = Join-Path $KeyDir $ProfileName
if ($null -eq $p12) { Fail "缺少 .p12 密钥库" }
if ($null -eq $cer) { Fail "缺少 .cer 证书" }
if (-not (Test-Path $profile)) { Fail "缺少 release profile: $profile" }
Write-Host ("    密钥库: {0}" -f $p12.Name)
Write-Host ("    证书  : {0}" -f $cer.Name)
Write-Host ("    Profile: {0}" -f $ProfileName)

Write-Host "==> 读取应用版本信息" -ForegroundColor Cyan
$appJson = Get-Content "AppScope\app.json5" -Raw -Encoding UTF8
$bundleName = [regex]::Match($appJson, '"bundleName"\s*:\s*"([^"]+)"').Groups[1].Value
$versionName = [regex]::Match($appJson, '"versionName"\s*:\s*"([^"]+)"').Groups[1].Value
$versionCode = [regex]::Match($appJson, '"versionCode"\s*:\s*(\d+)').Groups[1].Value
if (-not $bundleName) { Fail "无法读取 AppScope/app.json5 的 bundleName" }
Write-Host ("    {0}  v{1} ({2})" -f $bundleName, $versionName, $versionCode)

Write-Host "==> 校验 release profile" -ForegroundColor Cyan
$text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($profile))
$pbBundle = [regex]::Match($text, '"bundle-name"\s*:\s*"([^"]+)"').Groups[1].Value
$pbType = [regex]::Match($text, '"type"\s*:\s*"([^"]+)"').Groups[1].Value
$pbAppId = [regex]::Match($text, '"app-identifier"\s*:\s*"([^"]+)"').Groups[1].Value
$pbCert = [regex]::Match($text, '"(distribution-certificate|development-certificate|debug-certificate)"').Groups[1].Value
Write-Host ("    bundle={0} type={1} cert={2} app-id={3}" -f $pbBundle, $pbType, $pbCert, $pbAppId)
if ($pbBundle -ne $bundleName) { Fail "profile 的 bundle($pbBundle) 与应用($bundleName) 不一致" }
if ($pbType -ne "release") { Fail "profile 类型为 $pbType，release 发布需要 release 类型 profile" }
if ($text.Contains("device-ids") -or $text.Contains("deviceIds")) {
    Write-Host "    提示: 该 profile 含设备白名单，仅能安装到指定设备（正常发布包不应包含）" -ForegroundColor Yellow
}

Write-Host "==> 构建 release app 包" -ForegroundColor Cyan
& $hvigor assembleApp --no-daemon -p product=default -p buildMode=release | Out-Host
$unsigned = Get-ChildItem "$root\build\outputs\default" -Filter "*-unsigned.app" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $unsigned) { Fail "构建未生成 unsigned app 包" }
Write-Host ("    未签名包: {0}" -f $unsigned.FullName)

Write-Host "==> 使用 Release 证书签名" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$signed = Join-Path $outDir ("HelloJson-v{0}-release.app" -f $versionName)
if (Test-Path $signed) { Remove-Item $signed -Force }

# hvigor 若能按 build-profile.json5 的 signingConfigs 签出包，直接用它的产物
$hvigorSigned = Get-ChildItem "$root\build\outputs\default" -Filter "*-signed.app" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -ne $hvigorSigned -and $hvigorSigned.LastWriteTime -ge $unsigned.LastWriteTime) {
    Write-Host ("    使用 hvigor 内置签名产物: {0}" -f $hvigorSigned.Name) -ForegroundColor Cyan
    Copy-Item $hvigorSigned.FullName $signed -Force
} else {
    & $java -jar $signTool sign-app -mode localSign -keyAlias $KeyAlias -appCertFile $cer.FullName `
        -profileFile $profile -inFile $unsigned.FullName -signAlg SHA256withECDSA `
        -keystoreFile $p12.FullName -keystorePwd $Password -keyPwd $Password `
        -outFile $signed -signCode 1 | Select-String "success|ERROR" | Out-Host
}
if (-not (Test-Path $signed)) { Fail "签名失败（检查 p12 密码 / 别名 $KeyAlias）" }

Write-Host "==> 校验签名" -ForegroundColor Cyan
$tmpCer = Join-Path $env:TEMP "hellojson-verify.cer"
$tmpP7b = Join-Path $env:TEMP "hellojson-verify.p7b"
& $java -jar $signTool verify-app -inFile $signed -outCertChain $tmpCer -outProfile $tmpP7b | Select-String "Verify success|ERROR" | Out-Host
Remove-Item $tmpCer, $tmpP7b -ErrorAction SilentlyContinue

$size = [math]::Round((Get-Item $signed).Length / 1MB, 2)
Write-Host ""
Write-Host "==> 发布包已生成" -ForegroundColor Green
Write-Host ("    文件   : {0}" -f $signed)
Write-Host ("    大小   : {0} MB" -f $size)
Write-Host ("    应用   : {0}  v{1} ({2})" -f $bundleName, $versionName, $versionCode)
Write-Host ("    Profile: {0}  app-id={1}" -f $ProfileName, $pbAppId)
Write-Host ""
Write-Host "上架步骤: AppGallery Connect > 我的应用 > 版本信息 > 软件包 > 上传 .app 文件" -ForegroundColor Yellow
Write-Host "注意: 每次上架 versionCode 必须递增（当前 $versionCode），否则会被拒绝" -ForegroundColor Yellow
