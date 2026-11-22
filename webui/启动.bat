@echo off
chcp 65001 >nul
title H3 Studio
setlocal enabledelayedexpansion

set "APP=%~dp0app.py"
set "PY="

if defined H3_PYTHON if exist "%H3_PYTHON%" set "PY=%H3_PYTHON%"

if not defined PY (
  for %%P in (
    "%LOCALAPPDATA%\Programs\@comfyorgcomfyui-electron\resources\ComfyUI\.venv\Scripts\python.exe"
    "%LOCALAPPDATA%\Programs\@comfyorgcomfyui-electron\resources\python_embeded\python.exe"
    "C:\ComfyUI\.venv\Scripts\python.exe"
    "C:\ComfyUI\python_embeded\python.exe"
  ) do if exist %%P set "PY=%%~P"
)

if not defined PY (
  where python >nul 2>nul && set "PY=python"
)

if not defined PY (
  echo [错误] 找不到 Python。
  echo 请设置环境变量 H3_PYTHON 指向 ComfyUI 的 python.exe，例如：
  echo    set H3_PYTHON=<ComfyUI 安装目录>\.venv\Scripts\python.exe
  echo 然后重新运行本脚本。
  pause
  exit /b 1
)

echo 使用 Python: %PY%
"%PY%" -c "import aiohttp, av, PIL" 2>nul
if errorlevel 1 (
  echo [错误] 这个 Python 缺少依赖 aiohttp / av / Pillow。
  echo 建议用 ComfyUI 自带的 venv（它已经带了这三个包），或执行：
  echo    "%PY%" -m pip install aiohttp av pillow
  pause
  exit /b 1
)

if not exist "%~dp0config.json" (
  echo [提示] 没有 config.json，将自动探测 ComfyUI 的输入/输出目录。
  echo        如果探测失败，请把 config.example.json 改名为 config.json 并填写。
)

"%PY%" "%APP%"
pause
