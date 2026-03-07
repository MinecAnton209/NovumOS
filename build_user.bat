@echo off
setlocal enabledelayedexpansion

echo Building User-Mode ELF Test Programs...

if not exist build mkdir build
if not exist build\user mkdir build\user

set ZIG_EXE=E:\zig\zig.exe

:: Build hello_user.zig
echo Compiling tests/hello_user.zig...
%ZIG_EXE% build-exe zig\tests\hello_user.zig ^
    -target x86-freestanding-none ^
    -mcpu baseline-avx-avx2-mmx-sse-sse2-sse3-sse4_1-sse4_2-ssse3 ^
    -fno-stack-check ^
    -OReleaseSmall ^
    --name hello.elf ^
    --cache-dir .zig-cache

if %errorlevel% neq 0 (
    echo [ERROR] Failed to compile hello_user.zig
    exit /b 1
)

if not exist zig\embedded mkdir zig\embedded
copy hello.elf build\user\hello.elf > nul
move hello.elf zig\embedded\hello.elf
echo [SUCCESS] zig\embedded\hello.elf (embedded) and build\user\hello.elf are ready.

echo.
echo NOTE: To test this in NovumOS, you need to add this file to your FAT disk image 
echo and run it using the 'run' command in the shell.
echo Usage: run hello.elf
