@echo off
echo Building NovumOS...

:: Local .config: fall back to committed defconfig on first build
if not exist .config copy defconfig .config

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

:: Kernel: Zig modules, NASM objects and link. Flag parsing lives in
:: build.zig - this script never reads .config content.
echo Building kernel...
zig build %*
if %errorlevel% neq 0 (
    echo Error building kernel!
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
        iso_root -o build\NovumOS.iso
if %errorlevel% neq 0 (
    echo Error creating ISO!
    pause
    exit /b 1
)

:: Install Limine bootloader to ISO
echo Installing Limine to ISO...
limine-build\limine bios-install build\NovumOS.iso
if %errorlevel% neq 0 (
    echo Error installing Limine!
    pause
    exit /b 1
)

echo.
echo === Build Complete ===
echo.
echo To run: qemu-system-i386 -cdrom build\NovumOS.iso -serial stdio
