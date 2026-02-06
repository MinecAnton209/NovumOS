#!/bin/bash
set -e

if [ ! -f build/os-image.bin ]; then
    echo "Error: build/os-image.bin not found!"
    echo "Please run './build.sh' first."
    exit 1
fi

echo "Creating NovumOS.img..."
cp build/os-image.bin NovumOS.img

echo "Success! Created NovumOS.img"
