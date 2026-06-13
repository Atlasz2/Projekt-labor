@echo off
setlocal
title Nagyvazsony Dev Launcher

echo ============================================================
echo   Nagyvazsony - Fejlesztoi indito
echo ============================================================
echo.

REM Flutter a PATH-rol; ha ott nincs, a C:\src\flutter telepitesbol.
set "FLUTTER=flutter"
where flutter >nul 2>nul || set "FLUTTER=C:\src\flutter\bin\flutter.bat"

echo [1/2] Admin panel:  http://localhost:5173
start "Admin Panel" /D "%~dp0admin" cmd /k "npm run dev"

echo [2/2] Flutter app:  valassz eszkozt a megnyilo ablakban
start "Flutter App" /D "%~dp0mobile_app" cmd /k "%FLUTTER% run"

echo.
echo Mindket ablak kulon nyilik meg:
echo   - Admin:   http://localhost:5173
echo   - Flutter: valassz a listabol (Windows vagy Android telefon)
echo.
