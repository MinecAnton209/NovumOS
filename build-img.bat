@echo off
if not exist build\os-image.bin (
    echo Error: build\os-image.bin not found!
    echo Please run 'build.bat' first.
    pause
    exit /b 1
)

echo Creating NovumOS.img...
copy build\os-image.bin NovumOS.img >nul
if %errorlevel% neq 0 (
    echo Error creating NovumOS.img!
    pause
    exit /b 1
)

echo Success! Created NovumOS.img
