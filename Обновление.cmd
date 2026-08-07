@echo off
rem Обновление Dead Air x64 до актуальной версии.
rem
rem Сходит на GitHub, посмотрит, что вышло нового, скачает и разложит.
rem Файлы, которых в новой сборке больше нет, уберёт. Ваши настройки,
rem сохранения и посторонние моды не трогаются.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
