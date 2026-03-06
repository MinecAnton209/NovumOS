# NovumOS

![GitHub forks](https://img.shields.io/github/forks/MinecAnton209/NovumOS?style=social)
![GitHub last commit](https://img.shields.io/github/last-commit/MinecAnton209/NovumOS/main)
![GitHub Repo stars](https://img.shields.io/github/stars/MinecAnton209/NovumOS?style=social)
![GitHub License](https://img.shields.io/github/license/MinecAnton209/NovumOS)
![GitHub issues](https://img.shields.io/github/issues/MinecAnton209/NovumOS)

## 32-bit Protected Mode OS

NovumOS is a simple operating system that successfully boots from 16-bit real mode into 32-bit protected mode with a working console!

### Features

- ✅ **32-bit Graphics** - High-resolution Linear Framebuffer (LFB) support via **VBE** and **BGA**
- ✅ **Dynamic Resolution** - Change screen resolution on-the-fly with the `res` command
- ✅ **Relocated Kernel** - Loaded at **1MB (0x100000)** for maximum stability and compatibility
- ✅ **A20 Line Support** - Full access to high memory via BIOS & Fast A20 activation
- ✅ **LBA Disk Support** - Robust disk loading using Logic Block Addressing for larger kernels
- ✅ **VGA Emulation Layer** - High-speed text console with wrapping and scrolling over 32-bit graphics
- ✅ **IDT Support** - Interrupt Descriptor Table with exception handling
- ✅ **PIT Timer** - System timer (1kHz) for precise timing and uptime
- ✅ **RTC Driver** - Real-time clock support for date and time
- ✅ **Keyboard Driver** - Full keyboard input support with interrupts (Shift, CAPS, NUM)
- ✅ **Command Shell** - Interactive console with **Tab Autocomplete**, **Command History** (persisted to disk), and cycling matches
- ✅ **Piping & Redirection** - Support for pipes (`|`) and output redirection (`>`, `>>`)
- ✅ **FAT12/16 Support** - Native disk support for ATA drives with **Long File Name (LFN)** and **Hidden Files** support
- ✅ **PCI Bus Enumeration** - Support for scanning and identifying hardware devices on the PCI bus
- ✅ **Nova Language v0.23-beta.6** - Integrated custom interpreter with multi-line REPL, mandatory semicolons, modular system, and context-aware tab completion
- ✅ **Filesystem Overhaul** - Native implementation of `create_file`, `delete`, `rename`, and `copy` directly in the Nova interpreter
- ✅ **Embedded Scripts** - Built-in commands written in Nova (`syscheck`, `hello`)
- ✅ **Native Commands** - Native implementation of `install` and `uninstall` for Nova scripts
- ✅ **Recursive FS** - `cp` and `delete` now support recursive directory operations throughout the shell
- ✅ **Hierarchical Paths** - Full support for **Current Working Directory (CWD)**, absolute/relative paths, and quoted arguments for spaces
- ✅ **Serial Terminal** - Support for QEMU `-nographic` mode with full bidirectional shell interaction

### Building and Running

**Requirements:**
- NASM assembler
- Zig compiler (v0.12+)
- QEMU emulator

**Build:**
```bash
.\build.bat
```

**Run:**
```bash
qemu-system-i386 -drive format=raw,file=build\os-image.bin -serial stdio
```

**Run with Custom Res (BGA):**
```bash
qemu-system-i386 -drive format=raw,file=build\os-image.bin -drive format=raw,file=disk.img -nographic
```

### Available Commands

- `help`           - Show available commands (auto-synced)
- `res <w> <h>`    - **Change resolution** dynamically (e.g., `res 800 600`)
- `clear`          - Clear screen
- `matrix`         - Enterprise-grade Matrix screensaver (resolution-aware)
- `about`          - Show OS information (Version, Architecture)
- `nova`           - Start Nova Language Interpreter
- `syscheck`       - Run system health check (Embedded Nova Script)
- `uptime`         - Show system uptime and current RTC time
- `time`           - Show current date and time
- `reboot`         - Reboot system
- `shutdown`       - Shutdown system (ACPI support)
- `ls`, `la`        - List files (la shows hidden files)
- `pwd`             - Print current working directory
- `lspci`           - List PCI devices and hardware bridges
- `cd <path>`       - Change directory (supports `..`, `/`, and relative paths)
- `lsdsk`          - List storage devices and partitions
- `mount <d>`      - Select active disk (0/1 or ram)
- `touch <file>`   - Create file on disk (Supports LFN)
- `mkdir <dir>`    - Create directory (Supports LFN)
- `cp <src> <dst>` - Copy file or **folder recursively**
- `mv <src> <dst>` - Move or rename file/folder
- `cat <file>`     - Show file contents (Raw)
- `more <file>`    - Paginated file viewer with scrolling and wrapping
- `edit <file>`    - Open built-in text editor
- `rm <file>`      - Delete file/folder (recursive support)
- `history`        - Show command history
- `mkfs-fat12`     - Format disk with FAT12 filesystem
- `mkfs-fat16`     - Format disk with FAT16 filesystem
- `install`        - Install a Nova script as a system command
- `uninstall`      - Remove an installed Nova command
- `echo <text>`    - Print text (supports pipes)
- `top`            - Real-time CPU and Task Monitor
- `mem`            - Test memory allocator

### SDK (Software Development Kit)

NovumOS includes a complete SDK for developing user-mode applications in C or Zig.

**Quick Start:**
```bash
cd sdk/examples/hello_world
../../build-app.bat main.c hello.elf  # Windows
../../build-app.sh main.c hello.elf   # Linux
```

**Available APIs:**
- `nv_print()` - Print text to console
- `nv_getchar()` - Read keyboard input
- `nv_set_cursor()` - Position cursor
- `nv_clear_screen()` - Clear display
- `nv_exit()` - Exit program

See `sdk/README.md` for full documentation and examples.

### Nova Language
A powerful statement-based interpreted language built into NovumOS. Version 0.23-beta.6 introduces **Modular Sub-systems**, **Multi-line REPL**, **Mandatory Semicolons**, and **Context-aware Tab Completion**.

**Features:**
- **Variables**: `set string name = "Value";`, `set float pi = 3.14159;`
- **Arithmetic**: `+`, `-`, `*`, `/`, `%` with full support for integer and floating point math.
- **Precision Math**: Built-in high-precision `sin()` and `cos()` using Bhaskara I approximation.
- **Math Functions**: `abs()`, `min()`, `max()`, `random()`, `rad()`, `deg()`
- **Filesystem**: `create_file`, `write`, `mkdir`, `delete`, `copy`, `rename`, `read`, `size`, `exists`
- **Interactive**: `input()` for reading user input, `set_color()` for UI control.
- **System**: `reboot();`, `shutdown();`, `exit();`
- **Scripting**: `argc()`, `args(n)` with full argument persistence.

### Architecture

```
BIOS → Bootloader (16-bit) → Protected Mode Switch → Copy (0x10k to 1MB) → Kernel (32-bit) → Zig Modules
```

**Bootloader:**
- Loads kernel via **LBA** (Logical Block Addressing)
- Activates **A20 Line** (BIOS + Port 0x92)
- Performs VBE mode detection and validation
- Switches CPU to protected mode
- **Relocates kernel to 1MB** in 32-bit mode for EBDA safety

**Kernel:**
- Written in x86 Assembly and Zig
- Interrupt management (IDT & PIC remapping)
- System timer (PIT) and Real-Time Clock (RTC)
- **32-bit Linear Framebuffer (LFB)** drawing logic
- Keyboard driver (IRQ1 based)
- Command shell with persistent history (hidden `.HISTORY`) and LFN autocomplete
- Integrated Nova Interpreter

### Roadmap

#### Current progress (v0.23-beta.6)
- [x] **Graphic mode support (VBE/BGA)** (32-bit LFB, dynamic resolution)
- [x] **Kernel Relocation to 1MB** (EBDA safety, A20 activation)
- [x] **PCI Bus Enumeration (v0.23-beta.6)** (Config space access, device ID database)
- [x] **Modular Sub-systems (v0.22)** (sys, math mod)
- [x] **Multi-line REPL (v0.22)** (Accumulator buffer, continuation prompt)
- [x] **Mandatory Semicolons (v0.22)** (Complete statement tracking)
- [x] **Context-aware Tab Completion (v0.22)** (Import detection)
- [x] **Enhanced Error Handling (v0.22)** (Soft errors in REPL)
- [x] **Full Floating Point Engine (v0.21)**
- [x] **High-Precision Trig (v0.21)** (Bhaskara I formula)
- [x] **Informative REPL (v0.21)** (Descriptive status strings)
- [x] **Advanced VM FS Functions (v0.21)** (Native delete, rename, copy)
- [x] Multicore Support (v0.20)
- [x] FAT32 Support (v0.20)
- [x] IDT (Interrupt Descriptor Table)
- [x] Timer (PIT) & Precise Sleep
- [x] RTC Driver (Date/Time)
- [x] Keyboard Interrupts (Extended keys, Shift/Caps/Num)
- [x] Command Shell with **LFN Tab Autocomplete**
- [x] Persistent command history on disk (Hidden `.HISTORY`)
- [x] FAT12/FAT16 file system with **LFN and Hidden Files**
- [x] Recursive Directory Operations (cp, rm)
- [x] **Hierarchical Path Support & CWD** (Absolute/Relative paths, cd, pwd)
- [x] Built-in Text Editor (`edit`)
- [x] Dynamic Shell Commands table
- [x] Nova Language v0.22.0 (Multi-line REPL, Modules, Mandatory Semicolons, Context-aware Tab)
- [x] Native script management (install, uninstall)
- [x] File Management improvements (LFN create/read/delete)
- [x] PCI Bus Enumeration

#### Future improvements
- [x] Heap Memory Allocator (kmalloc/kfree) - *Basic implementation done*
- [ ] Paging & Virtual Memory Management
- [ ] Multi-tasking (Kernel & User threads)
- [ ] User Mode (Ring 3) & System Calls
- [ ] PS/2 Mouse Support
- [ ] Simple Sound Driver (PC Speaker)

### Author

**MinecAnton209**

### License

See LICENSE file for details.

---

**Made with ❤️ in x86 Assembly & Zig**