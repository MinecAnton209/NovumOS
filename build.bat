@echo off
echo Building NovumOS...

:: Create directories
if not exist build mkdir build
if not exist limine-build mkdir limine-build

:: Initialize Limine submodule if needed
if not exist limine\Makefile (
    echo Initializing Limine submodule...
    git submodule update --init --recursive
)

:: Build Limine (use prebuilt on Windows)
echo Building Limine...
if exist limine\limine.exe (
    copy limine\limine.exe limine-build\
) else (
    cd limine
    make
    cd ..
)
copy limine\limine-bios.sys limine-build\
copy limine\limine-bios-cd.bin limine-build\
copy limine\limine-uefi-cd.bin limine-build\
copy limine\BOOTX64.EFI limine-build\

:: Assemble kernel
echo Assembling kernel...
nasm -f elf32 kernel32.asm -o build\kernel32.o
if %errorlevel% neq 0 (
    echo Error assembling kernel!
    pause
    exit /b 1
)

:: Assemble SMP Trampoline
echo Assembling SMP Trampoline...
nasm -f bin zig\smp_trampoline.asm -o build\trampoline.bin
if %errorlevel% neq 0 (
    echo Error assembling SMP trampoline!
    pause
    exit /b 1
)

:: Build Zig modules
echo Building Zig modules...
pushd zig
zig build %*
if %errorlevel% neq 0 (
    echo Error building Zig modules!
    popd
    pause
    exit /b 1
)
popd

:: Assemble User Mode
echo Assembling User Mode...
nasm -f elf32 user_mode.asm -o build\user_mode.o
if %errorlevel% neq 0 (
    echo Error assembling user_mode!
    pause
    exit /b 1
)

:: Link kernel
echo Linking...
zig ld.lld -m elf_i386 -T linker.ld --strip-all -o build\kernel32.elf build\kernel32.o build\user_mode.o zig\build\kernel.o
if %errorlevel% neq 0 (
    echo Error linking!
    pause
    exit /b 1
)

:: Extract binary
echo Extracting binary...
zig objcopy -O binary build\kernel32.elf build\kernel32.bin
if %errorlevel% neq 0 (
    echo Error extracting binary!
    pause
    exit /b 1
)

:: Create bootable image
echo Creating image...
copy /b limine-build\limine-bios.sys + build\kernel32.bin build\os-image.bin > nul

:: Pad to 1.44MB
fsutil file createnorm build\pad.bin 1474560 > nul 2>nul
copy /b build\os-image.bin + build\pad.bin build\temp.bin > nul
del /f build\os-image.bin 2>nul
ren build\temp.bin os-image.bin
del /f build\pad.bin 2>nul

echo.
echo Build successful!
dir build\*.bin os-image.bin

echo.
echo Run: qemu-system-i386 -drive format=raw,file=build\os-image.bin