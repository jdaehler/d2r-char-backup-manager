@echo off
rem Startet den D2R Char Backup Manager. -Sta wird von WPF zwingend benoetigt.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File "%~dp0D2RCharBackupManager.ps1"
if errorlevel 1 (
  echo.
  echo Der D2R Char Backup Manager wurde mit einem Fehler beendet.
  pause
)
