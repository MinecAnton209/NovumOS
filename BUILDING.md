# Building NovumOS from Source

This guide covers building and running NovumOS in detail.

## Requirements

### Software

| Tool | Version | Purpose |
|------|---------|---------|
| git | latest | Clone repo, init submodules |
| NASM | latest | Assembler for x86 assembly |
| Zig | 0.16.0 | Build system, linker, compiler |
| xorriso | latest | Create bootable ISO image |
| QEMU | latest | Emulator for testing |
| make, cc (gcc/clang) | latest | Build Limine bootloader (Linux only) |

### Installing Dependencies

#### Windows

**git:**
- Download from https://git-scm.com/
- Add to PATH

**NASM:**
- Download from https://www.nasm.us/
- Add to PATH

**Zig:**
```powershell
winget install zig.zig
# or
choco install zig
```

**xorriso:**
```powershell
winget install xorriso
# or
choco install xorriso
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
sudo apt install build-essential nasm qemu-system-x86 xorriso
```

Install Zig from https://ziglang.org/download/ (add to PATH).

#### macOS

```bash
brew install git nasm qemu xorriso
```

Install Zig from https://ziglang.org/download/ (add to PATH).

## Building

### Windows

```bash
.\build.bat
```

Output:
- `NovumOS.iso` - Bootable ISO image (with Limine + kernel)

### Linux/macOS

```bash
chmod +x build.sh
./build.sh
```

Output:
- `NovumOS.iso` - Bootable ISO image (with Limine + kernel)

## Running

### Basic

```bash
qemu-system-i386 -cdrom NovumOS.iso -serial stdio
```

### With Disk Image

```bash
qemu-system-i386 -cdrom NovumOS.iso -drive format=raw,file=disk.img -serial stdio
```

### Serial Console (No Graphics)

```bash
qemu-system-i386 -cdrom NovumOS.iso -nographic
```

### PC Speaker Audio (QEMU)

```bash
qemu-system-i386 -cdrom NovumOS.iso -audiodev sdl,id=audio0 -machine pc,pcspk-audiodev=audio0 -serial stdio
```

### Debugging

```bash
# With QEMU monitor
qemu-system-i386 -cdrom NovumOS.iso -serial stdio -monitor stdio

# With GDB
qemu-system-i386 -cdrom NovumOS.iso -serial stdio -s -S
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