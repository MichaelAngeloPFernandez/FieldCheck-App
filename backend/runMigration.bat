@echo off
REM Migration Runner Script for Windows
REM Double-click this file to run the MongoDB migration

echo.
echo ========================================
echo FieldCheck MongoDB Migration
echo ========================================
echo.

REM Check if node_modules exists
if not exist "node_modules" (
    echo Installing dependencies...
    call npm install
    echo.
)

REM Run the migration
echo Running fixNullGeofences.js...
echo.
call node scripts/fixNullGeofences.js

echo.
echo ========================================
echo Migration completed!
echo ========================================
echo.
pause
