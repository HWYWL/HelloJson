# 一键创建 GitHub Release 并上传 HAP 资产
# 用法:
#   powershell -ExecutionPolicy Bypass -File .\scripts\create-release.ps1 -Token <PAT>
#   或先设置环境变量 GITHUB_TOKEN 后不带 -Token
# 令牌权限: classic PAT 勾选 repo；fine-grained PAT 需 Contents: Read and write
param(
    [string]$Token = $env:GITHUB_TOKEN,
    [string]$Repo = "HWYWL/HelloJson",
    [string]$Tag = "v0.1.0-20261022",
    [string]$Title = "v0.1.0-20261022 · HelloJson 首发版",
    [string]$NotesFile = "docs/RELEASE-v0.1.0.md",
    [string]$Asset = "build-output/v0.1.0-20261022.hap",
    [switch]$DryRun
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$notesPath = Join-Path $root $NotesFile
$assetPath = Join-Path $root $Asset
if (-not (Test-Path $notesPath)) { throw "找不到说明文件: $notesPath" }
if (-not (Test-Path $assetPath)) { throw "找不到安装包: $assetPath（可先用 hvigor 构建并签名）" }

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

$body = @{
    tag_name   = $Tag
    name       = $Title
    body       = (Get-Content $notesPath -Raw -Encoding UTF8)
    draft      = $false
    prerelease = $false
} | ConvertTo-Json -Depth 4

Write-Host "==> 创建 Release $Tag" -ForegroundColor Cyan
try {
    $release = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/releases" `
        -Headers $headers -ContentType "application/json; charset=utf-8" -Body ([Text.Encoding]::UTF8.GetBytes($body))
} catch {
    $msg = $_.Exception.Message
    if ($msg -match "422") {
        Write-Host "!! 该 tag 已存在 Release，改为在已有 Release 上补传资产" -ForegroundColor Yellow
        $release = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers
    } else {
        throw
    }
}
Write-Host "    release id: $($release.id)"
Write-Host "    html url  : $($release.html_url)"

$uploadUrl = ($release.upload_url -replace '\{.*\}', "")
$uploadUri = "$uploadUrl?name=$assetName&label=$assetName"

Write-Host "==> 上传资产 $assetName" -ForegroundColor Cyan
$assetInfo = Invoke-RestMethod -Method Post -Uri $uploadUri -Headers $headers `
    -ContentType "application/octet-stream" -InFile $assetPath
Write-Host "    asset url : $($assetInfo.browser_download_url)"
Write-Host "完成: $($release.html_url)" -ForegroundColor Green
