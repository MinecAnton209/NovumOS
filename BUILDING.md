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
| make, cc (gcc/clang) | latest | Build Limine bootloader (Linux/macOS) |
| qemu-img | latest | Optional: create disk.img via `zig build mkdisk` |

### Installing Dependencies

#### Windows

**git:**
- Download from https://git-scm.com/
- Add to PATH

**NASM:**
- Download from https://www.nasm.us/
- Add to PATH

**Zig:**
- Download from https://ziglang.org/download/ (add to PATH)

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

The build scripts do everything end to end: Limine submodule, kernel asm,
Zig modules, linking, ISO. Windows uses the prebuilt `limine.exe` when
present; Linux/macOS compile Limine with `make`.

### Windows

```bash
.\build.bat
```

### Linux/macOS

```bash
chmod +x build.sh
./build.sh
```

If `xorriso` is missing on Linux/macOS, everything else builds and the
script skips ISO creation with a hint.

### Architecture selection

Sources are laid out per architecture (see [Repository Layout](#repository-layout)):

- The build scripts assemble and link the `arch/x86/` sources directly —
  there is no `ARCH` environment variable to set (the Zig side is picked
  by `-Darch` below).
- `zig build -Darch=x86` selects the compiler target and the
  `arch/mod.zig` facade branch (`x86` is the only supported value today;
  anything else fails fast with a clear error). The scripts currently run
  `zig build` with the default, so pass this flag only when invoking
  `zig build` yourself.

Adding an architecture: drop sources in `zig/arch/<name>/`, register the
name in `zig/build.zig`'s `-Darch` switch, add branches in
`zig/arch/mod.zig`, and point `ARCH` at matching asm under `arch/<name>/`.

### Outputs

| Path | What |
|------|------|
| `NovumOS.iso` | Bootable ISO (Limine + kernel) |
| `build/kernel32.elf` | Linked kernel |
| `build/trampoline.bin` | SMP AP trampoline (also embedded via `zig/arch/*/trampoline.bin`) |
| `zig/build/nova` | nova user-space ELF, embedded into the kernel with `@embedFile` |
| `disk.img` | Raw disk, only after `zig build mkdisk` (optional) |

### zig build extras

From the `zig/` directory:

```bash
zig build mkdisk --disk-size=2G   # create ../disk.img (needs qemu-img; default 32M)
zig build -Dhistory_size=100      # shell history depth
zig build test                 # config facade tests (kconfig engine: zig test kconfig.zig)
```

Bare `zig test config.zig` fails with `no module named build_config` by
design — use `zig build test` for the facade, `zig test kconfig.zig` for
the engine.

Known gap: `zig build run` and `zig build run-disk` still reference
`../build/os-image.bin`, which the current pipeline does not produce —
launch QEMU manually as shown below.

## Running

### Basic

```bash
qemu-system-i386 -cdrom NovumOS.iso -serial stdio
```

### With Disk Image

```bash
zig build mkdisk --disk-size=2G        # from zig/, once
qemu-system-x86_64 -boot d -cdrom NovumOS.iso -hda disk.img -m 2G -serial stdio
```

A freshly created `disk.img` is unformatted: on first boot run `mkfs` in
the shell before `touch`/`cat`/redirects.

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

## Repository Layout

| Path | Contents |
|------|----------|
| `arch/x86/` | `kernel32.asm`, `user_mode.asm`, `idt.asm`, `linker.ld` |
| `zig/arch/x86/` | exceptions, SMP, keyboard ISR, ring0/ring3 glue, IDT watchdog, trampoline |
| `zig/arch/mod.zig` | The only arch seam: core imports architecture through this facade |
| `zig/kernel/` | `kmain`, memory, scheduler, logger, ELF loader, fs glue |
| `zig/shell/` | shell and command table |
| `zig/drivers/` | ATA, FAT, VGA/LFB, timer, speaker, RTC, PCI, ACPI |
| `zig/syscalls/` | `int 0x80` dispatch and handlers |
| `zig/nova_user/` | modern nova (Ring 3, AST) |
| `zig/nova_legacy/` | frozen legacy nova (Ring 0) |
| `.config` / `defconfig` | local overrides / committed defaults (repo root) |
| `zig/config.zig` | config facade + derived constants (build root) |

## Development

### Configuration (.config)

Compile-time options live in `.config` at the repo root (git-ignored).
Initialize and edit:

```bash
cp defconfig .config        # Windows: copy defconfig .config
```

Edit `CONFIG_<NAME>=y|n|<decimal>` lines in any editor and rebuild —
there is no runtime/CLI config command; the file is parsed at build
time by the kconfig engine. Resolution order: `.config` → `defconfig`
→ schema defaults. Invalid lines fail the build with the exact line
number. Full flag reference and workflow: [DOCS/CONFIG.md](DOCS/CONFIG.md).

- Debug output: `ENABLE_SERIAL_DEBUG` / `ENABLE_EARLY_LFB_DEBUG`
  (passed to nasm as `-D` defines), `ENABLE_FAT_DEBUG`,
  `ENABLE_KERNEL_LOGGING`, `MOUSE_DEBUG`, `NOVA_DEBUG`.
- Compile-out gates (default `y`): `ENABLE_QUANTUM`, `ENABLE_DOOMFIRE`,
  `ENABLE_BUILTIN_SCRIPTS`, `ENABLE_MOUSE`, `ENABLE_SPEAKER`,
  `ENABLE_SMP`, `ENABLE_NOVA` — set `=n` to exclude the subsystem from
  the binary entirely.
- Audio: `ENABLE_BOOT_BEEP` / `ENABLE_ERROR_BEEP` (honored only with
  `ENABLE_SPEAKER=y`).
- Shell/system: `ENABLE_DEBUG_COMMANDS`, `ENABLE_DEBUG_CRASH_COMMANDS`,
  `ENABLE_IDT_WATCHDOG`, `ENABLE_RSOD_REBOOT`, `ENABLE_EMBEDDED_ELFS`,
  `HISTORY_SIZE` (overridable per-build via `-Dhistory_size`),
  `HEAP_INITIAL_SIZE`.
- Security: `NOVA_PATH_POLICY_ENABLED` — keep `=y` (CVE-2026-40573).

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
2. Run `.\build.bat` (or `./build.sh`)
3. Test in QEMU
4. Repeat

### Common Issues

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## CI

GitHub Actions: `.github/workflows/ci.yml` (build) and
`.github/workflows/codeql.yml` (CodeQL analysis).

## Next Steps

- See [README.md](README.md) for features
- See [CONTRIBUTING.md](CONTRIBUTING.md) for contributing
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
