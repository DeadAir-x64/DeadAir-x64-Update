@echo off
rem Установка и обновление Dead Air x64 поверх чистой версии.
rem Положите этот файл и install.ps1 в папку с игрой (где database и fsgame.ltx).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
