# Building NovumOS from Source

This guide covers building and running NovumOS in detail.

## Requirements

### Software

| Tool | Version | Purpose |
|------|---------|---------|
| NASM | latest | Assembler for x86 assembly |
| Zig | master (0.12+) | Build system & compiler |
| QEMU | latest | Emulator for testing |

### Installing Dependencies

#### Windows

**NASM:**
- Download from https://www.nasm.us/
- Add to PATH

**Zig:**
```powershell
winget install zig.zig
# or
choco install zig
```

**QEMU:**
```powershell
winget install qemu.qemu
# or
choco install qemu
```

#### Linux (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install nasm qemu-system-x86 zig
```

#### macOS

```bash
brew install nasm qemu zig
```

## Building

### Windows

```bash
.\build.bat
```

Output:
- `build/os-image.bin` - Kernel image
- `NovumOS.img` - Disk image with filesystem

### Linux/macOS

```bash
chmod +x build.sh
./build.sh
```

### Building Components Separately

```bash
# Build kernel only (NASM)
nasm -f bin bootloader.asm -o build/bootloader.bin
nasm -f bin kernel32.asm -o build/kernel32.bin

# Build SDK
cd sdk/libnovum
.\build.bat  # Windows
./build.sh  # Linux/macOS

# Build example apps
cd ..
.\build-app.bat examples\hello_world\main.c examples\hello_world\hello.elf
```

## Running

### Basic

```bash
qemu-system-i386 -cdrom NovumOS.iso
```

### With Disk Image

```bash
qemu-system-i386 -drive format=raw,file=build/os-image.bin -drive format=raw,file=NovumOS.img
```

### Serial Console (No Graphics)

```bash
qemu-system-i386 -cdrom NovumOS.iso -nographic
```

Connect via:
```bash
# In another terminal
nc localhost 4444
```

### Custom Resolution (BGA)

```bash
qemu-system-i386 -drive format=raw,file=build/os-image.bin -drive format=raw,file=NovumOS.img -vga std
```

### Debugging

```bash
# With QEMU monitor
qemu-system-i386 -cdrom NovumOS.iso -monitor stdio

# With GDB
qemu-system-i386 -cdrom NovumOS.iso -s -S
# Then in gdb: target remote localhost:1234
```

## Development

### IDE Setup

#### VS Code

Install extensions:
- NASM Syntax Highlighting
- Zig Language

`.vscode/settings.json`:
```json
{
  "files.associations": {
    "*.asm": "nasm"
  },
  "editor.formatOnSave": false
}
```

#### Vim/Neovim

For Zig:
```vim
:TSInstall zig
```

### Testing Changes

1. Make changes to code
2. Run `.\build.bat`
3. Test in QEMU
4. Repeat

### Common Issues

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## CI/Build Matrix

| Platform | Build Command | Status |
|----------|--------------|--------|
| Windows | `.\build.bat` | ✅ CI |
| Linux | `./build.sh` | ✅ CI |

## Next Steps

- See [README.md](README.md) for features
- See [CONTRIBUTING.md](CONTRIBUTING.md) for contributing
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues