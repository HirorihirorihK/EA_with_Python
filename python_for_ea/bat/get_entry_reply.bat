@echo off
setlocal

chcp 65001 >nul
set PYTHONIOENCODING=utf-8
set "APP_DIR=%~dp0.."
set PY_FILE=get_entry_reply.py
for %%I in ("%APP_DIR%") do set "APP_DIR=%%~fI"

cd /d "%APP_DIR%"

if errorlevel 1 (
    echo ERROR: APP_DIR not found: %APP_DIR%
    exit /b 1
)

echo Current directory: %CD%
echo Run file: %APP_DIR%\%PY_FILE%

uv run python "%APP_DIR%\%PY_FILE%"

set PY_EXIT_CODE=%ERRORLEVEL%

if not "%PY_EXIT_CODE%"=="0" (
    echo ERROR: Python script failed.
    exit /b %PY_EXIT_CODE%
)

echo Finished.
exit /b 0
