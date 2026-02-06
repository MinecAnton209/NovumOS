@echo off
set RELEASE_DIR=release
set VERSION=v0.20

echo Packaging NovumOS %VERSION%...

if not exist %RELEASE_DIR% mkdir %RELEASE_DIR%

:: Copy artifacts
if exist NovumOS.iso copy NovumOS.iso %RELEASE_DIR%\ /Y
if exist NovumOS.img copy NovumOS.img %RELEASE_DIR%\ /Y

:: Copy documentation
if exist README.md copy README.md %RELEASE_DIR%\ /Y
if exist LICENSE copy LICENSE %RELEASE_DIR%\ /Y

echo.
echo Release artifacts prepared in %RELEASE_DIR%\
dir %RELEASE_DIR%
echo.
echo Ready for distribution!
