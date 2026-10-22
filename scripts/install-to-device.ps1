# HelloJson 一键安装到真机
# 用法: powershell -ExecutionPolicy Bypass -File .\scripts\install-to-device.ps1 -Password "<p12密码>"
param(
    [string]$Password = "whfR>;O4K@-CkUMdI=",
    [string]$Device = "5JB0224A09000317",
    [string]$KeyDir = "F:\OpenHarmony\Key\HelloJson\Dev",
    [string]$KeyAlias = "hellojson",
    [string]$Mode = "debug"
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$env:DEVECO_SDK_HOME = "F:\OpenHarmony\command-line-tools\sdk"
$env:PATH = "F:\OpenHarmony\command-line-tools\bin;$env:PATH"
$hvigor = "F:\OpenHarmony\command-line-tools\bin\hvigorw.bat"
$hdc = "D:\Programs\HapKit\resources\toolchains\hdc.exe"
$java = "D:\Program Files\JDK\jdk1.8.0_503\bin\java.exe"
$signTool = "F:\OpenHarmony\Sdk\26.0.0\toolchains\lib\hap-sign-tool.jar"
$bundle = "com.yi.json"
$ability = "EntryAbility"
$outDir = Join-Path $root "build-output"

function Get-ProfileInfo([string]$path) {
    $text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($path))
    $info = [ordered]@{}
    $info.Name = Split-Path $path -Leaf
    $m = [regex]::Match($text, '"bundle-name"\s*:\s*"([^"]+)"'); $info.Bundle = $m.Groups[1].Value
    $m = [regex]::Match($text, '"type"\s*:\s*"([^"]+)"'); $info.Type = $m.Groups[1].Value
    $m = [regex]::Match($text, '"(distribution-certificate|development-certificate)"')
    $info.CertField = $m.Groups[1].Value
    $info.HasProfileDevices = $text.Contains('device-ids') -or $text.Contains('deviceIds')
    return $info
}

Write-Host "==> 检测设备 $Device" -ForegroundColor Cyan
$targets = @(& $hdc list targets | ForEach-Object { ($_ -split "`t")[0].Trim() } | Where-Object { $_ })
$connected = $targets | Where-Object { $_ -eq $Device }
if ($null -eq $connected) {
    Write-Host "!! 设备未连接，当前设备: $($targets -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "==> 识别签名材料 $KeyDir" -ForegroundColor Cyan
$profiles = @()
Get-ChildItem $KeyDir -Filter "*.p7b" -ErrorAction SilentlyContinue | ForEach-Object {
    $profiles += Get-ProfileInfo $_.FullName
}
if ($profiles.Count -eq 0) {
    Write-Host "!! 目录中没有 .p7b profile" -ForegroundColor Red
    exit 1
}
foreach ($p in $profiles) {
    Write-Host ("    {0}: bundle={1} type={2} cert={3}" -f $p.Name, $p.Bundle, $p.Type, $p.CertField)
}

$debugProfile = $profiles | Where-Object { $_.Type -eq "debug" -and $_.Bundle -eq $bundle } | Select-Object -First 1
$hdcHap = $null

if ($null -ne $debugProfile) {
    Write-Host "==> 使用调试 profile: $($debugProfile.Name)" -ForegroundColor Cyan
    $stem = [IO.Path]::GetFileNameWithoutExtension($debugProfile.Name)
    $p12 = Get-ChildItem $KeyDir -Filter "*.p12" | Where-Object { $stem -match [regex]::Escape($_.BaseName) } | Select-Object -First 1
    if ($null -eq $p12) { $p12 = Get-ChildItem $KeyDir -Filter "*.p12" | Select-Object -First 1 }
    # 调试 profile 绑定的是开发证书，优先选名字含 Dev 的证书，避免误用 release 证书
    $cerFiles = Get-ChildItem $KeyDir -Filter "*.cer" | Where-Object { $_.BaseName -notmatch "rootCA|subCA" }
    $cer = $cerFiles | Where-Object { $_.BaseName -match "Dev" } | Select-Object -First 1
    if ($null -eq $cer) { $cer = $cerFiles | Select-Object -First 1 }

    Write-Host "==> 构建（未签名）" -ForegroundColor Cyan
    & $hvigor assembleHap --no-daemon -p product=default -p buildMode=$Mode | Out-Null
    $unsigned = Join-Path $root "entry\build\default\outputs\default\entry-default-unsigned.hap"
    if (-not (Test-Path $unsigned)) { Write-Host "!! 构建失败" -ForegroundColor Red; exit 1 }

    Write-Host "==> 使用 hap-sign-tool 签名" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $signed = Join-Path $outDir "HelloJson-debug-signed.hap"
    & $java -jar $signTool sign-app -mode localSign -keyAlias $KeyAlias -appCertFile $cer.FullName `
        -profileFile (Join-Path $KeyDir $debugProfile.Name) -inFile $unsigned `
        -signAlg SHA256withECDSA -keystoreFile $p12.FullName -keystorePwd $Password -keyPwd $Password `
        -outFile $signed -compatibleVersion 24 -signCode 1 | Select-String "success|ERROR" | Out-Host
    $hdcHap = $signed
} else {
    Write-Host "==> 未发现 bundle=com.yi.json 的调试 profile，尝试使用 hvigor 已配置的签名" -ForegroundColor Yellow
    & $hvigor assembleHap --no-daemon -p product=default -p buildMode=$Mode | Out-Null
    $candidate = Get-ChildItem "entry\build\default\outputs\default" -Filter "*-signed.hap" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -ne $candidate) {
        $hdcHap = $candidate.FullName
    }
}

if ($null -eq $hdcHap) {
    Write-Host ""
    Write-Host "!! 无法生成可安装的 HAP" -ForegroundColor Red
    Write-Host "   现有 profile 仅为 release（distribution）类型，真机安装必须使用调试证书 + 含本机 UDID 的调试 profile。" -ForegroundColor Yellow
    Write-Host "   解决方式（任选其一）：" -ForegroundColor Yellow
    Write-Host "     1) DevEco Studio: File > Project Structure > Signing Configs > 勾选 Automatically generate signature，登录华为账号后 Apply" -ForegroundColor Yellow
    Write-Host "        然后重新执行本脚本" -ForegroundColor Yellow
    Write-Host "     2) 在 AGC 创建调试证书与调试 profile（添加设备 UDID），把 .p7b/.cer/.p12 放入 $KeyDir 后重新执行本脚本" -ForegroundColor Yellow
    Write-Host ("   本机 UDID: " + ((& $hdc -t $Device shell bm get -u) -join ' ').Trim()) -ForegroundColor Yellow
    exit 2
}

Write-Host "==> 安装 $hdcHap" -ForegroundColor Cyan
& $hdc -t $Device install -r $hdcHap
if ($LASTEXITCODE -ne 0) {
    Write-Host "!! 安装失败（若为 9568322，表示签名来源不被信任，需调试证书）" -ForegroundColor Red
    exit 3
}

Write-Host "==> 启动 $bundle" -ForegroundColor Cyan
& $hdc -t $Device shell aa start -a $ability -b $bundle
Write-Host "完成" -ForegroundColor Green
