#!/bin/bash
set -e

echo "Building NovumOS..."

# Local .config: fall back to committed defconfig on first build
if [ ! -f .config ]; then
    cp defconfig .config
fi

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

# Kernel: Zig modules, NASM objects and link. Flag parsing lives in
# build.zig — this script never reads .config content.
echo "Building kernel..."
zig build

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
    echo "Install xorriso to create an ISO: sudo apt install xorriso"
fi

echo ""
echo "=== Build Complete ==="
echo "ISO:  NovumOS.iso  ($(stat -c%s NovumOS.iso | numfmt --to=iec))"
echo ""
echo "To run:"
echo "  qemu-system-i386 -cdrom NovumOS.iso"
echo ""
