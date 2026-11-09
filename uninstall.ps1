#requires -version 5.1
$ErrorActionPreference = 'Stop'
$lib = Join-Path $env:LOCALAPPDATA 'Lively Wallpaper\Library\wallpapers'
$dst = Join-Path $lib 'agent-ops-dsh'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Agent OPS Bridge.lnk'

Write-Host '卸载 Agent OPS · DSH 壁纸' -ForegroundColor Cyan

if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host '√ 已移除开机启动' -ForegroundColor Green }
Get-Process node -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq '' } | Out-Null
if (Test-Path $dst) {
  Remove-Item $dst -Recurse -Force
  Write-Host "√ 已删除壁纸目录 $dst" -ForegroundColor Green
}
Write-Host ''
Write-Host '剩下的：打开 Lively → 壁纸库 → 右键那个已失效的条目 → 删除。' -ForegroundColor DarkGray
Write-Host '桥接进程如果还在跑，注销一次或任务管理器结束 node.exe 即可。' -ForegroundColor DarkGray
Read-Host '按回车退出'
