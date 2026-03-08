#!/bin/bash
set -e

echo "Building NovumOS Library (libnovum)..."

# Build the library from Zig source
# Target: i386 freestanding
zig build-lib -target x86-freestanding -OReleaseSmall \
    src/main.zig -femit-bin=../libnovum.a
    
echo "Success! libnovum.a created in sdk/ folder."
