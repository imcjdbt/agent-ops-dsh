# 打发行包：把仓库内容（不含开发文件）压成 Lively 可用的 zip
# 用法： powershell -NoProfile -ExecutionPolicy Bypass -File package.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'AgentOPS-DSH'
$zip = Join-Path $dist 'agent-ops-dsh-wallpaper.zip'

Remove-Item $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$include = @(
  'index.html', 'lively.html', 'LivelyInfo.json', 'lively_t.jpg', 'LICENSE',
  'NOTICE.md', 'README.md', 'README.en.md', 'install.ps1', 'uninstall.ps1',
  '使用说明.md', '使用说明-EN.md', '安装.bat'
)
foreach ($f in $include) {
  $src = Join-Path $root $f
  if (Test-Path $src) { Copy-Item $src $stage -Force }
}

New-Item -ItemType Directory -Force -Path (Join-Path $stage 'live') | Out-Null
Copy-Item (Join-Path $root 'live\*.mjs'), (Join-Path $root 'live\*.js'), (Join-Path $root 'live\*.vbs') (Join-Path $stage 'live') -Force

Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
$size = [math]::Round((Get-Item $zip).Length / 1MB, 2)
Write-Host "OK  $zip  ($size MB)" -ForegroundColor Green
