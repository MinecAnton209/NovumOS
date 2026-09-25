# Build Configuration (.config)

Compile-time configuration for the kernel. Everything in `.config` is
evaluated by the Zig build at compile time — there is no runtime `config`
shell command: toggling a flag means editing the file and rebuilding.

## Quick start

```bash
cp defconfig .config        # Windows: copy defconfig .config
```

Open `.config` in any editor, flip a value, rebuild:

```
CONFIG_ENABLE_MOUSE=n
```

```bash
./build.sh                  # or .\build.bat, or: cd zig && zig build
```

`.config` is git-ignored — local tweaks stay local. `defconfig` is the
committed template mirrored from the schema defaults.

## Format

- One option per line: `CONFIG_<NAME>=y|n|<decimal>`
- Comments start with `#` (whole lines only)
- `# CONFIG_X is not set` is only a comment — the option falls back to
  its schema default
- Options missing from the file fall back to schema defaults, so a
  minimal `.config` may contain only what you change
- Invalid lines fail the build immediately with file and line number:
  `invalid config in .config at line N: ...`

## Resolution order

1. `.config` (repo root)
2. `defconfig` (repo root)
3. Schema defaults (`zig/config_schema.zig`)

## Compile-out gates (default `y`)

`=n` truly excludes the subsystem: its code is never analyzed, never
linked, and its commands disappear from `help`.

| Flag | What `=n` removes |
|------|-------------------|
| `ENABLE_QUANTUM` | Quantum simulator, all `q*` commands, syscalls 55–57 (−8 KB). With `ENABLE_NOVA=y` legacy nova still links the entropy helpers — add `ENABLE_NOVA=n` for full exclusion (−49 KB total, nova ELF not built) |
| `ENABLE_DOOMFIRE` | `doomfire` command (also prints "disabled" cleanly if only `QUANTUM=n`) |
| `ENABLE_BUILTIN_SCRIPTS` | Embedded `hello`/`syscheck` `.nv` scripts |
| `ENABLE_MOUSE` | PS/2 driver, `mouse` command, IDT/IRQ12 asm wiring — passed to nasm as `-DENABLE_MOUSE=0` (−4 KB) |
| `ENABLE_SPEAKER` | Driver, `beep` command, syscall 42, panic sound. `ENABLE_BOOT_BEEP`/`ENABLE_ERROR_BEEP` apply only while speaker is on |
| `ENABLE_SMP` | AP bring-up (kernel runs BSP-only), `smp-test`/`stress-test`. Partial by design — locks/per-CPU arrays stay |
| `ENABLE_NOVA` | `nova`/`nova_legacy`/`install`/`uninstall` commands, `.nv` script dispatch, embedded `nova.elf`, and the nova build step itself (`zig/build/nova` not produced) |

Measured on `build/kernel32.elf` vs the default build (364920 bytes):
`QUANTUM=n` 356728, `MOUSE=n` 360824, `NOVA=n` 315768.

## Other flags

**Debug output** — `ENABLE_SERIAL_DEBUG` / `ENABLE_EARLY_LFB_DEBUG` go
to nasm as `-D` defines; `ENABLE_FAT_DEBUG`, `ENABLE_KERNEL_LOGGING`,
`MOUSE_DEBUG`, `NOVA_DEBUG` are Zig-side traces.

**Shell** — `ENABLE_DEBUG_COMMANDS`, `ENABLE_DEBUG_CRASH_COMMANDS`,
`HISTORY_SIZE` (default 50; `zig build -Dhistory_size=N` overrides for
one build), `ENABLE_EMBEDDED_ELFS` (default `n`).

**Audio** — `ENABLE_BOOT_BEEP`, `ENABLE_ERROR_BEEP` (require
`ENABLE_SPEAKER=y`).

**System** — `ENABLE_IDT_WATCHDOG`, `ENABLE_RSOD_REBOOT`,
`NOVA_PATH_POLICY_ENABLED` (security kill-switch for CVE-2026-40573 —
keep `y`), `USE_GARBAGE_COLLECTOR` (default `n`),
`HEAP_INITIAL_SIZE` (default 1 MB, shown by `sysinfo`).

## Verifying a config change

```bash
cd zig
zig test kconfig.zig   # config engine
zig build test         # config facade
zig build              # build with the current .config
```

Compile-out proof: `build/kernel32.elf` must shrink vs a default build
when you disable a gate. In QEMU, `help` no longer lists gated commands.

## Adding a new flag

1. Add the field to `zig/config_schema.zig` (name, default, help)
2. Expose it in `zig/config.zig`: `pub const NAME = value(bool, "NAME");`
3. Mirror the default in `defconfig` as `CONFIG_NAME=y` (or `=n`)
4. Gate the code: append-chunk in `shell.zig` for commands, a comptime
   call-site guard for modules, `-D` define for asm
5. Run `zig test kconfig.zig && zig build test && zig build`
