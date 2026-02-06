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

# Build Zig modules
echo "Building Zig modules..."
cd zig
zig build
cd ..

# Link kernel with Zig modules
echo "Linking..."
zig ld.lld -m elf_i386 -T linker.ld --strip-all -o build/kernel32.elf build/kernel32.o zig/build/kernel.o

# Extract flat binary from ELF
echo "Extracting binary..."
zig objcopy -O binary build/kernel32.elf build/kernel32.bin

# Create final image
echo "Creating os-image.bin..."
cat build/bootloader.bin build/kernel32.bin > build/os-image.bin

echo "Build successful!"
ls -l build/os-image.bin

echo "Run: qemu-system-i386 -fda build/os-image.bin"
