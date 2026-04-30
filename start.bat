@echo off
title Nagyvazsony Dev Launcher
echo.
echo ============================================================
echo   Nagyvazsony - Fejlesztoi indito
echo ============================================================
echo.
echo [1/2] Admin panel inditasa (http://localhost:5173)...
start "Admin Panel" cmd /k "cd /d "%~dp0" && npm --prefix admin run dev"
echo.
echo [2/2] Flutter mobilalkalmazas inditasa (Windows)...
start "Flutter App" cmd /k "cd /d "%~dp0" && flutter run --project-dir mobile_app -d windows"
echo.
echo Mindket ablak elindult.
echo Admin:  http://localhost:5173
echo Mobile: kulonallo ablakban indul
echo.
