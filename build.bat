@echo off
echo Building NovumOS...

:: Create directories
if not exist build mkdir build
if not exist limine-build mkdir limine-build
if not exist iso_root\boot mkdir iso_root\boot

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

:: Detect config flags from zig/config.zig
set SERIAL_DEBUG=0
set EARLY_LFB_DEBUG=0
findstr /c:"ENABLE_SERIAL_DEBUG = true" zig\config.zig > nul 2>&1
if %errorlevel% equ 0 set SERIAL_DEBUG=1
findstr /c:"ENABLE_EARLY_LFB_DEBUG = true" zig\config.zig > nul 2>&1
if %errorlevel% equ 0 set EARLY_LFB_DEBUG=1

:: Assemble kernel
echo Assembling kernel...
nasm -f elf32 kernel32.asm -o build\kernel32.o -DENABLE_SERIAL_DEBUG=%SERIAL_DEBUG% -DENABLE_EARLY_LFB_DEBUG=%EARLY_LFB_DEBUG%
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

:: Copy files to ISO directory
echo Creating ISO...
copy limine-build\limine-bios.sys iso_root\boot\ > nul
copy limine-build\limine-bios.sys iso_root\ > nul
copy limine-build\limine-bios-cd.bin iso_root\boot\ > nul
copy limine-build\limine-uefi-cd.bin iso_root\boot\ > nul
copy limine-build\BOOTX64.EFI iso_root\boot\ > nul
copy build\kernel32.elf iso_root\boot\ > nul
copy build\trampoline.bin iso_root\boot\ > nul
copy limine.conf iso_root\ > nul

:: Create ISO image
xorriso -as mkisofs -b boot/limine-bios-cd.bin ^
        -no-emul-boot -boot-load-size 4 -boot-info-table ^
        --efi-boot boot/limine-uefi-cd.bin ^
        -efi-boot-part --efi-boot-image --protective-msdos-label ^
        iso_root -o NovumOS.iso
if %errorlevel% neq 0 (
    echo Error creating ISO!
    pause
    exit /b 1
)

:: Install Limine bootloader to ISO
echo Installing Limine to ISO...
limine-build\limine bios-install NovumOS.iso
if %errorlevel% neq 0 (
    echo Error installing Limine!
    pause
    exit /b 1
)

echo.
echo === Build Complete ===
echo.
echo To run: qemu-system-i386 -cdrom NovumOS.iso -serial stdio
