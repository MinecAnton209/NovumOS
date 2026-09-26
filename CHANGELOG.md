# Changelog

All notable changes to NovumOS are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.25-beta.3] - 2026-09-26

### Added
- Interactive Linux `lxdialog`-style `menuconfig` TUI tool (`zig build menuconfig`) with mouse and keyboard navigation
- Submenu hierarchy for Debug, Audio, Shell/System, Security, and Memory configuration options
- Comprehensive descriptions, prompt labels, and help dialogs for all 24 schema configuration options
- Middle-click (SCM) info shortcut, mouse wheel scrolling, hover highlights, and save/exit confirmation modals
- Compile-time `.config` engine (`kconfig.zig`) with strict validation and duplicate key detection
- Format-preserving `.config` serializer and merger (`cfg_write.zig`) retaining comments and ordering
- Subsystem compile-out gates: `ENABLE_QUANTUM`, `ENABLE_DOOMFIRE`, `ENABLE_BUILTIN_SCRIPTS`, `ENABLE_MOUSE`, `ENABLE_SPEAKER`, `ENABLE_SMP`, and `ENABLE_NOVA`
- Configurable settings for shell history size, heap initial size, serial/LFB debug, and security path policies
- Dedicated test suites for configuration engine, facade, serializer, and TUI logic (`test`, `test-cfg-write`, `test-menuconfig`)
- Auto-dirty detection prompting creation of `.config` from `defconfig` on first `menuconfig` run
- Support for `[skip ci]` / `[ci skip]` directives in GitHub Actions CI workflows

### Changed
- Moved `build.zig` and `build.zig.zon` to the repository root for direct root-level execution
- Updated `build.bat` and `build.sh` build scripts to invoke `zig build` from repository root
- Output bootable ISO directly to `build/NovumOS.iso` and updated all documentation / CI paths
- Migrated external dependencies to `libvaxis` via root Zig package manager
- Formatted entire Zig codebase with `zig fmt`

### Fixed
- Added NASM include content-tracking for `arch/x86/idt.asm` to prevent stale build artifacts
- Fixed word-wrapped text margin alignment inside Help modal dialogs
- Fixed `@embedFile` artifact installation path for the embedded Nova binary on clean builds

## [0.25-beta.2] - 2026-09-25

### Added
- PS/2 mouse driver with graphics/input syscalls (60–63) and event queue
- FD-based file syscalls (100–114) and futex (120)
- Segregated explicit free-list kernel heap with boundary tags
- Quantum random number generator and Nova `qrand` module
- Quantum state-vector simulator in the shell, register sized from free RAM with 32 MB reserve
- Quantum-ignited DOOM fire effect on the framebuffer
- Real Bell state for the quantum decoherence pair, guarded by a lock
- `crash` shell alias; command history buffers moved to the heap
- Architecture selection via `-Darch` and `arch/mod.zig` facade
- `DOCS/PANICS.md` panic reference; README and BUILDING.md rewrites

### Fixed
- Scheduler: lock scheduler state and per-CPU current, try-once `sched_lock` so the timer ISR never spins, skip ISR heap work while `heap_lock` is owned, defer reaping, free the `Process` struct when reaping a zombie
- Memory: take `paging_lock` in every `map_page_at` path, validate heap header claims before using them as offsets, coalesce blocks only inside tracked regions, gate the huge-page path behind user permission checks, reserve the mmap slot first and roll back on OOM
- Security: canonicalize paths before policy matching (case-insensitive, slashless prefixes), require privilege for `idtMove` (34) and `ShellExec` (53), close secondary ATA/A20/DMA page ports, force absolute validated paths in rename and copy
- FAT: FAT32 EOF constants and full 32-bit start clusters in directory walks, grow the cluster chain before `fat_puts` writes past it, repair FAT16 `root_entries`, write file data in the file's own cluster chain, probe both master and slave drives during boot disk check
- Syscalls: bound `ReadFile` writes by the user buffer size, bound mmap growth and rounding, source uname release from versioning
- Shell: bound `.HISTORY` load and save against the 50 KB buffer, tick the prompt clock while the user types, keep redirect defer at function scope, print command-not-found with correct polarity
- Quantum: guard the buffered rdrand word with a spinlock, reset qubit register state on init
- VGA: drop vsync from cursor and erase flushes
- Time: stop latching RTC after the first read
- Video: route BGA resolution switch through a Ring 0 syscall

### Changed
- Rework source layout into `arch/x86`, `kernel`, `shell` and select the architecture with `-Darch`
- Drop top-of-file path and summary headers from sources
- Remove unused `ENABLE_NOTIFICATION_BEEP`; disable FAT driver debug prints

### Performance
- Batch console VRAM flushes to the command boundary; skip vsync wait on console scroll
- Cache FAT BPB after first read, invalidate on mkfs
- O(1) `get_free_memory`/`get_used_memory` via a maintained free page counter
- Next-fit scan hint in `find_free_cluster`
- Read rdrand in 4-byte words with retry and rdseed

### Refactored
- Merge mkfs variants, I/O port functions, `printSize*` helpers, LFN parsing and string/math helpers into shared modules
- Split shell, FAT, scheduler, memory and kernel init into focused helpers
- Proxy ring-3 syscalls through a shared syscall proxy; centralize Nova syscall wrappers

### Documentation
- Sync `DOCS/MEMORY.md` with the region heap and paging gates
- Document the scheduler interrupt-gate assumption and logger interrupt-safety invariant
- Fix `NOVA.md` import examples and bit-flag check
