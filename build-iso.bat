@echo off

:: Ensure base image exists
if not exist NovumOS.img (
    echo NovumOS.img not found. Running build-img.bat...
    call build-img.bat
    if errorlevel 1 exit /b 1
)

:: Build Tool
echo Building ISO Tool...
if not exist tools\mkiso.exe (
    zig build-exe tools/mkiso.zig -femit-bin=tools/mkiso.exe
    if %errorlevel% neq 0 (
        echo Error building mkiso tool!
        pause
        exit /b 1
    )
)

:: Run Tool
echo Creating NovumOS.iso...
tools\mkiso.exe NovumOS.img NovumOS.iso
if %errorlevel% neq 0 (
    echo Error creating ISO!
    pause
    exit /b 1
)

echo Success! Created NovumOS.iso
