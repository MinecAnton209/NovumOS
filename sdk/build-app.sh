#!/bin/bash
# NovumOS SDK - Application Builder
# Usage: build-app.sh <source.c> <output.elf>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <source.c> <output.elf>"
    echo "Example: $0 main.c app.elf"
    exit 1
fi

SOURCE=$1
OUTPUT=$2
TEMP_OBJ="${SOURCE%.c}.o"

echo "Building $SOURCE -> $OUTPUT..."

# Compile
zig cc -target x86-freestanding -O2 -I libnovum/include -c "$SOURCE" -o "$TEMP_OBJ"
if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

# Link
zig ld.lld -T linker_app.ld "$TEMP_OBJ" libnovum.a -o "$OUTPUT" --entry main
if [ $? -ne 0 ]; then
    echo "Linking failed!"
    rm "$TEMP_OBJ"
    exit 1
fi

rm "$TEMP_OBJ"
echo "Success! Created $OUTPUT"
