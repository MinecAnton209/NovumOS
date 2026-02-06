#!/bin/bash
set -e

# Ensure base image exists
if [ ! -f NovumOS.img ]; then
    echo "NovumOS.img not found. Running './build-img.sh'..."
    ./build-img.sh
fi

# Build Tool
echo "Building ISO Tool..."
if [ ! -f tools/mkiso ]; then
    zig build-exe tools/mkiso.zig -femit-bin=tools/mkiso
fi

# Run Tool
echo "Creating NovumOS.iso..."
./tools/mkiso NovumOS.img NovumOS.iso

echo "Success! Created NovumOS.iso"
