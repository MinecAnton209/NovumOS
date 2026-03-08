#!/bin/bash
set -e

echo "Building NovumOS..."

# Create build directory
mkdir -p build

# Assemble bootloader
echo "Assembling bootloader..."
nasm -f bin bootloader.asm -o build/bootloader.bin

# Assemble kernel to ELF object file
echo "Assembling kernel..."
nasm -f elf32 kernel32.asm -o build/kernel32.o

# Assemble SMP Trampoline
echo "Assembling SMP Trampoline..."
nasm -f bin zig/smp_trampoline.asm -o zig/trampoline.bin

# Build Zig modules
echo "Building Zig modules..."
cd zig
zig build
cd ..

# Assemble User Mode
echo "Assembling User Mode..."
nasm -f elf32 user_mode.asm -o build/user_mode.o

# Link kernel with Zig modules
echo "Linking..."
zig ld.lld -m elf_i386 -T linker.ld --strip-all -o build/kernel32.elf build/kernel32.o build/user_mode.o zig/build/kernel.o

# Extract flat binary from ELF
echo "Extracting binary..."
zig objcopy -O binary build/kernel32.elf build/kernel32.bin

# Create final image
echo "Creating os-image.bin..."
cat build/bootloader.bin build/kernel32.bin > build/os-image.bin

# Pad image to 1.44MB floppy size
echo "Padding image..."
dd if=/dev/zero of=build/pad.bin bs=1024 count=1440
cat build/os-image.bin build/pad.bin | head -c 1474560 > build/temp.bin
mv build/temp.bin build/os-image.bin
rm build/pad.bin

echo "Build successful!"
ls -l build/os-image.bin

echo "Run: qemu-system-i386 -fda build/os-image.bin"
