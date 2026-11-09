#requires -version 5.1
<#
  Agent OPS · DSH 壁纸 —— 一键安装
  作用：把壁纸文件装进 Lively 的壁纸库，并挂上开机自启的数据桥接程序。
  只在本机运行，不改系统设置，不需要管理员权限（除非 Lively 装在别处）。
#>
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$lib = Join-Path $env:LOCALAPPDATA 'Lively Wallpaper\Library\wallpapers'
$dst = Join-Path $lib 'agent-ops-dsh'

Write-Host ''
Write-Host '  Agent OPS · DSH 壁纸 安装程序' -ForegroundColor Cyan
Write-Host '  ---------------------------------------' -ForegroundColor DarkGray

if (-not (Test-Path (Join-Path $src 'index.html'))) {
  Write-Host '× 当前目录里没有 index.html，请把压缩包完整解压后再运行 install.ps1。' -ForegroundColor Red
  Read-Host '按回车退出'; exit 1
}

if (-not (Test-Path $lib)) {
  Write-Host '× 没有找到 Lively 的壁纸库：' -ForegroundColor Red
  Write-Host "  $lib" -ForegroundColor DarkGray
  Write-Host ''
  Write-Host '  请先安装 Lively Wallpaper（Microsoft Store 搜索 Lively Wallpaper），' -ForegroundColor Yellow
  Write-Host '  或者从 github.com/rocksdanister/lively 下载安装，装好后再运行本脚本。' -ForegroundColor Yellow
  Read-Host '按回车退出'; exit 1
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Host '× 没有检测到 Node.js。' -ForegroundColor Red
  Write-Host '  数据桥接程序需要 Node.js 18 或更高版本（只读本地文件，不联网）。' -ForegroundColor Yellow
  Write-Host '  下载：https://nodejs.org/  （选择 LTS 版本）' -ForegroundColor Yellow
  Write-Host '  装完后请重新打开一个终端窗口，再运行本脚本。' -ForegroundColor Yellow
  Read-Host '按回车退出'; exit 1
}
Write-Host ('√ Node.js ' + (& node -v)) -ForegroundColor Green

if (Test-Path $dst) {
  Write-Host "√ 更新已有安装：$dst" -ForegroundColor Green
} else {
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  Write-Host "√ 新建壁纸目录：$dst" -ForegroundColor Green
}

Get-ChildItem -Path $src -Force |
  Where-Object { $_.Name -ne 'install.ps1' -and $_.Name -ne 'uninstall.ps1' -and $_.Name -ne '使用说明.md' -and $_.Name -ne 'bridge.pid' -and $_.Name -ne 'bridge.log' } |
  ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $dst -Recurse -Force
  }
Write-Host '√ 壁纸文件已复制' -ForegroundColor Green

$vbs = Join-Path $dst 'live\start-bridge.vbs'
if (-not (Test-Path $vbs)) { throw "缺少 live\start-bridge.vbs，压缩包可能不完整" }

try {
  $startup = [Environment]::GetFolderPath('Startup')
  $lnk = Join-Path $startup 'Agent OPS Bridge.lnk'
  $ws = New-Object -ComObject WScript.Shell
  $sc = $ws.CreateShortcut($lnk)
  $sc.TargetPath = (Join-Path $env:WINDIR 'System32\wscript.exe')
  $sc.Arguments = '"' + $vbs + '"'
  $sc.WorkingDirectory = Split-Path $vbs
  $sc.Description = 'Agent OPS 壁纸：本地 DSH 数据桥接'
  $sc.Save()
  Write-Host "√ 已加入开机启动：$lnk" -ForegroundColor Green
} catch {
  Write-Host ('! 开机启动没设置成功（不影响现在使用）：' + $_.Exception.Message) -ForegroundColor Yellow
}

try {
  Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + $vbs + '"') -WindowStyle Hidden
  Start-Sleep -Seconds 3
  $data = Join-Path $dst 'live\live-data.js'
  if (Test-Path $data) {
    $age = [int]((Get-Date) - (Get-Item $data).LastWriteTime).TotalSeconds
    Write-Host "√ 桥接已启动，数据文件 ${age}s 前更新" -ForegroundColor Green
  } else {
    Write-Host '! 桥接已启动但还没写出数据，可能是 .dsh 目录里还没有记录（用一次 DSH 之后就会有了）' -ForegroundColor Yellow
  }
} catch {
  Write-Host ('! 桥接启动失败：' + $_.Exception.Message) -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  接下来：' -ForegroundColor Cyan
Write-Host '  1. 打开 Lively Wallpaper 主界面'
Write-Host '  2. 壁纸库里找到 “Agent OPS · DSH”'
Write-Host '  3. 点击它 / 右键 → Set as wallpaper（设为壁纸）'
Write-Host ''
Write-Host '  提示：壁纸右上角可以切换 粒子 / 纸面 / 墨底 三套配色，' -ForegroundColor DarkGray
Write-Host '        点「配色」还能只改“背景/文字”两个颜色，其余自动派生。' -ForegroundColor DarkGray
Write-Host ''
Read-Host '安装完成，按回车关闭'
