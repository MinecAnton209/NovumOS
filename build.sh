#!/bin/bash
set -e

echo "Building NovumOS..."

# Initialize/update limine submodule
echo "Initializing Limine..."
git submodule update --init --recursive limine

mkdir -p build limine-build iso_root/boot

# Build Limine
echo "Building Limine..."
cd limine
make
cd ..

# Copy Limine build artifacts
cp limine/limine-bios.sys limine-build/
cp limine/limine-bios-cd.bin limine-build/
cp limine/limine-uefi-cd.bin limine-build/
cp limine/BOOTX64.EFI limine-build/
cp limine/limine limine-build/

# Assemble kernel
echo "Assembling kernel..."
nasm -f elf32 kernel32.asm -o build/kernel32.o

# Assemble SMP Trampoline
echo "Assembling SMP Trampoline..."
nasm -f bin zig/smp_trampoline.asm -o build/trampoline.bin

# Build Zig modules
echo "Building Zig modules..."
cd zig
zig build
cd ..

# Assemble User Mode
echo "Assembling User Mode..."
nasm -f elf32 user_mode.asm -o build/user_mode.o

# Link kernel
echo "Linking..."
zig ld.lld -m elf_i386 -T linker.ld --strip-all -o build/kernel32.elf build/kernel32.o build/user_mode.o zig/build/kernel.o

# Copy Limine files to ISO directory
cp limine-build/limine-bios.sys iso_root/boot/
cp limine-build/limine-bios.sys iso_root/
cp limine-build/limine-bios-cd.bin iso_root/boot/
cp limine-build/limine-uefi-cd.bin iso_root/boot/
cp limine-build/BOOTX64.EFI iso_root/boot/

# Copy kernel
cp build/kernel32.elf iso_root/boot/
cp build/trampoline.bin iso_root/boot/

# Copy Limine config
cp limine.conf iso_root/

# Create ISO image (if xorriso is available)
if command -v xorriso &> /dev/null; then
    echo "Creating ISO..."
    xorriso -as mkisofs -b boot/limine-bios-cd.bin \
            -no-emul-boot -boot-load-size 4 -boot-info-table \
            --efi-boot boot/limine-uefi-cd.bin \
            -efi-boot-part --efi-boot-image --protective-msdos-label \
            iso_root -o NovumOS.iso

    # Install Limine bootloader to ISO
    echo "Installing Limine to ISO..."
    ./limine-build/limine bios-install NovumOS.iso
else
    echo "Skipping ISO (xorriso not found)"
    echo "Install xorriso to create ISO: sudo apt install xorriso"
fi

echo ""
echo "=== Build Complete ==="
echo "ISO:  NovumOS.iso  ($(stat -c%s NovumOS.iso | numfmt --to=iec))"
echo ""
echo "To run:"
echo "  qemu-system-i386 -cdrom NovumOS.iso"
echo ""