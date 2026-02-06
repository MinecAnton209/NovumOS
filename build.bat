@echo off
echo Building NovumOS...

:: Create build directory
if not exist build mkdir build

:: Assemble bootloader
echo Assembling bootloader...
nasm -f bin bootloader.asm -o build\bootloader.bin
if %errorlevel% neq 0 (
    echo Error assembling bootloader!
    pause
    exit /b 1
)

:: Assemble kernel to ELF object file
echo Assembling kernel...
nasm -f elf32 kernel32.asm -o build\kernel32.o
if %errorlevel% neq 0 (
    echo Error assembling kernel!
    pause
    exit /b 1
)

:: Assemble SMP Trampoline
echo Assembling SMP Trampoline...
nasm -f bin zig\smp_trampoline.asm -o zig\trampoline.bin
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

:: Link kernel with Zig modules (strip during link)
echo Linking...
zig ld.lld -m elf_i386 -T linker.ld --strip-all -o build\kernel32.elf build\kernel32.o zig\build\kernel.o
if %errorlevel% neq 0 (
    echo Error linking!
    pause
    exit /b 1
)

:: Extract flat binary from ELF
echo Extracting binary...
zig objcopy -O binary build\kernel32.elf build\kernel32.bin
if %errorlevel% neq 0 (
    echo Error extracting binary!
    pause
    exit /b 1
)

:: Create final image
echo Creating image...
copy /b build\bootloader.bin + build\kernel32.bin build\os-image.bin > nul

:: Pad image to 2880 sectors (1.44MB floppy)
:: This ensures everything is loaded correctly by the BIOS
echo Padding image...
fsutil file createnew build\pad.bin 1474560 > nul
copy /b build\os-image.bin + build\pad.bin build\temp.bin > nul
fsutil file truncate build\temp.bin 1474560 > nul
del build\os-image.bin
ren build\temp.bin os-image.bin
del build\pad.bin

echo.
echo Build successful!
dir build\*.bin

echo.
echo Run: qemu-system-i386 -drive format=raw,file=build\os-image.bin -serial stdio