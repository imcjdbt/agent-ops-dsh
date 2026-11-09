@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo  ==========================================
echo   Agent OPS - DSH   推送到 GitHub
echo  ==========================================
echo.
git rev-parse --git-dir >nul 2>&1
if errorlevel 1 (
  echo  [x] 这个文件夹不是 git 仓库
  pause
  exit /b 1
)
git config http.sslBackend openssl
echo  正在推送，如果弹出浏览器请登录 GitHub 并授权...
echo.
git push -u origin main
if errorlevel 1 (
  echo.
  echo  [x] 推送失败。常见原因：
  echo      1. 还没有在 GitHub 上建仓库 agent-ops-dsh
  echo      2. 登录窗口被关掉了 ^(再运行一次本文件即可^)
  echo      3. 仓库名不是 agent-ops-dsh ^(改 .git/config 里的 url^)
) else (
  echo.
  echo  [ok] 推送完成：https://github.com/imcjdbt/agent-ops-dsh
)
echo.
pause
