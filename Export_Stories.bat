@echo off
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if %errorlevel%==0 (
    py -3 "tools\export_stories.py" %*
    goto :done
)

where python >nul 2>nul
if %errorlevel%==0 (
    python "tools\export_stories.py" %*
    goto :done
)

echo Python 3 was not found in PATH. Install Python 3 from python.org to use the story folder exporter.

:done
echo.
pause