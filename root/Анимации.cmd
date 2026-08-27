@echo off
setlocal
rem ============================================================================
rem  Dead Air x64 - модуль анимаций. Установка одним файлом.
rem
rem  Ничего никуда раскладывать не нужно: этот файл можно запускать откуда
rem  угодно, хоть из Загрузок. Он сам скачает установщик и сам найдёт игру.
rem
rem  Установщик качается КАЖДЫЙ раз, а не хранится рядом: так у человека
rem  всегда свежая версия, и починенная ошибка доезжает до него сама.
rem ============================================================================
title Dead Air x64 - модуль анимаций
cd /d "%~dp0"

set "PS1=%TEMP%\da_anim_install.ps1"
set "URL=https://raw.githubusercontent.com/DeadAir-x64/DeadAir-x64-Animation/main/anim_install.ps1"

echo.
echo   Скачиваю установщик...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; try { (New-Object Net.WebClient).DownloadFile('%URL%','%PS1%'); exit 0 } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"

if errorlevel 1 (
  echo.
  echo   Не удалось скачать установщик.
  echo   Проверьте подключение к сети, либо скачайте архив вручную:
  echo   https://github.com/DeadAir-x64/DeadAir-x64-Animation/releases/latest
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
del "%PS1%" >nul 2>&1
endlocal
