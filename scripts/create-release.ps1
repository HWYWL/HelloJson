# 一键创建 GitHub Release 并上传安装包
# 用法:
#   powershell -ExecutionPolicy Bypass -File .\scripts\create-release.ps1 -Token <PAT>
#   powershell -ExecutionPolicy Bypass -File .\scripts\create-release.ps1 -DryRun
#   powershell -ExecutionPolicy Bypass -File .\scripts\create-release.ps1 -Version 0.3.0 -Asset <路径>
# 版本号 / tag / 标题 / 说明文件 / 资产名默认都由 AppScope/app.json5 与日期推导，发新版不用改脚本。
# 令牌权限: classic PAT 勾选 repo；fine-grained PAT 需 Contents: Read and write
param(
    [string]$Token = $env:GITHUB_TOKEN,
    [string]$Repo = "HWYWL/HelloJson",
    [string]$Version = "",
    [string]$Date = (Get-Date -Format 'yyyyMMdd'),
    [string]$Tag = "",
    [string]$Title = "",
    [string]$NotesFile = "",
    [string]$Asset = "",
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

# ---- 版本信息：-Version 优先，否则读 AppScope/app.json5 ----
$appJsonPath = Join-Path $root 'AppScope/app.json5'
if (-not (Test-Path $appJsonPath)) { throw "找不到 $appJsonPath" }
$appJson = [IO.File]::ReadAllText($appJsonPath, [Text.Encoding]::UTF8)
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [regex]::Match($appJson, '"versionName"\s*:\s*"([^"]+)"').Groups[1].Value
}
if ([string]::IsNullOrWhiteSpace($Version)) { throw "无法读取 versionName，请用 -Version 指定" }
$versionCode = [regex]::Match($appJson, '"versionCode"\s*:\s*(\d+)').Groups[1].Value

if ([string]::IsNullOrWhiteSpace($Tag)) { $Tag = "v$Version-$Date" }
if ([string]::IsNullOrWhiteSpace($Title)) { $Title = "v$Version-$Date · HelloJson" }
if ([string]::IsNullOrWhiteSpace($NotesFile)) { $NotesFile = "docs/RELEASE-v$Version.md" }

# ---- 资产：-Asset 优先，否则按约定候选顺序查找 ----
if ([string]::IsNullOrWhiteSpace($Asset)) {
    $candidates = @(
        "build-output/v$Version-$Date-unsigned.hap",
        "build-output/HelloJson-v$Version-release.app",
        "build-output/HelloJson-v$Version-release.hap"
    )
    $found = $candidates | Where-Object { Test-Path (Join-Path $root $_) } | Select-Object -First 1
    if ($null -eq $found) {
        throw ("找不到安装包，请先执行 scripts/build-release.ps1 或显式传 -Asset。候选：" + ($candidates -join " / "))
    }
    $Asset = $found
}

Write-Host "==> 版本 $Version (versionCode=$versionCode)" -ForegroundColor Cyan
Write-Host "    tag   : $Tag"
Write-Host "    title : $Title"
Write-Host "    notes : $NotesFile"
Write-Host "    asset : $Asset"

$notesPath = Join-Path $root $NotesFile
$assetPath = Join-Path $root $Asset
if (-not (Test-Path $notesPath)) { throw "找不到说明文件: $notesPath" }
if (-not (Test-Path $assetPath)) { throw "找不到安装包: $assetPath（可先用 scripts/build-release.ps1 构建并签名）" }

$assetName = Split-Path $assetPath -Leaf
$assetSize = (Get-Item $assetPath).Length

if ($DryRun) {
    Write-Host "[dry-run] repo    : $Repo"
    Write-Host "[dry-run] tag     : $Tag"
    Write-Host "[dry-run] title   : $Title"
    Write-Host "[dry-run] notes   : $NotesFile ($((Get-Item $notesPath).Length) bytes)"
    Write-Host "[dry-run] asset   : $assetName ($([math]::Round($assetSize / 1KB, 1)) KB)"
    if ([string]::IsNullOrWhiteSpace($Token)) { Write-Host "[dry-run] token   : 未提供（正式执行需要 PAT）" }
    else { Write-Host "[dry-run] token   : 已提供" }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "缺少访问令牌：请用 -Token <PAT> 传入，或设置环境变量 GITHUB_TOKEN"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = "application/vnd.github+json"
    "User-Agent"           = "HelloJson-release-script"
    "X-GitHub-Api-Version" = "2022-11-28"
}

# 注意：Windows PowerShell 5.1 下 Get-Content -Raw 返回的字符串会被 ConvertTo-Json
# 序列化成 {"value": ..., "PSPath": ...} 对象，导致 GitHub 报 422。必须用 ReadAllText。
$notes = [string][IO.File]::ReadAllText($notesPath, [Text.Encoding]::UTF8)

$body = @{
    tag_name   = $Tag
    name       = $Title
    body       = $notes
    draft      = $false
    prerelease = $false
} | ConvertTo-Json -Depth 4

Write-Host "==> 创建 Release $Tag" -ForegroundColor Cyan
try {
    $release = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/releases" `
        -Headers $headers -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body))
} catch {
    $code = $null
    try { $code = $_.Exception.Response.StatusCode.value__ } catch { }
    $detail = $_.ErrorDetails.Message
    if ($code -eq 422 -and $detail -match "already_exists") {
        Write-Host "!! 该 tag 已存在 Release，改为在已有 Release 上补传资产" -ForegroundColor Yellow
        $release = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers
    } else {
        Write-Host "!! 创建失败 (HTTP $code)" -ForegroundColor Red
        if ($detail) { Write-Host $detail -ForegroundColor DarkGray }
        throw
    }
}
Write-Host "    release id: $($release.id)"
Write-Host "    html url  : $($release.html_url)"

$existing = @()
try {
    $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/$($release.id)/assets" -Headers $headers
} catch { }

if ($existing -and ($existing | Where-Object { $_.name -eq $assetName })) {
    Write-Host "==> 资产 $assetName 已存在，跳过上传" -ForegroundColor Yellow
} else {
    $uploadUrl = ($release.upload_url -replace '\{.*\}', "")
    $uploadUri = "$uploadUrl" + "?name=$assetName&label=$assetName"

    Write-Host "==> 上传资产 $assetName" -ForegroundColor Cyan
    $assetInfo = Invoke-RestMethod -Method Post -Uri $uploadUri -Headers $headers `
        -ContentType "application/octet-stream" -InFile $assetPath
    Write-Host "    asset url : $($assetInfo.browser_download_url)"
}
Write-Host "完成: $($release.html_url)" -ForegroundColor Green
