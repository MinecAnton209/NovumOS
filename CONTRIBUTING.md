# Contributing to NovumOS

Thank you for your interest in contributing to NovumOS!

This document provides guidelines for contributing to the project. Following these guidelines helps maintain a positive and productive community.

## Getting Started

### Prerequisites

- **NASM** - Assembler for x86 assembly code
- **Zig** (master branch) - Build system and compiler
- **QEMU** - Emulator for testing

### Building from Source

```bash
# Windows
.\build.bat

# Linux/macOS
chmod +x build.sh
./build.sh
```

### Running in QEMU

```bash
# BIOS boot
qemu-system-i386 -cdrom NovumOS.iso

# Or boot from disk image
qemu-system-i386 -hda NovumOS.img -m 128

# Serial console (no graphics)
qemu-system-i386 -cdrom NovumOS.iso -nographic
```

## Development Workflow

### Branch Naming

- `main` - Stable release branch
- `feat/*` - New features (e.g., `feat/add-sound-driver`)
- `fix/*` - Bug fixes (e.g., `fix/paging-null-pointer`)
- `refactor/*` - Code refactoring
- `smp` - SMP support development

### Making Changes

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Ensure the build passes
5. Test in QEMU
6. Submit a Pull Request

### Commit Messages

We accept both conventional and free-form commit messages:

**Conventional (preferred for new features):**
```
feat: add Nova language support
fix: resolve page fault in memory allocator
docs: update README with new commands
refactor: simplify IDT handling
```

**Free-form (okay for quick fixes):**
```
Fix memory leak in keyboard driver
Add SMP support for QEMU
Update build scripts
```

### Pull Request Process

1. Update documentation if needed
2. Ensure `.\build.bat` runs successfully
3. Test in QEMU at different resolutions
4. Verify kernel stack and memory integrity
5. Update the PR template checklist

## Coding Standards

### Assembly (NASM)

- Use **tabs** for indentation (not spaces)
- Label on same line as instruction: `label: instruction operands`
- Comment with `;` for single lines
- Section order: `section .text`, `section .data`, `section .rodata`, `section .bss`

### Zig

- Follow Zig standard conventions
- Use `zig fmt` for formatting
- Run `zig build` to validate

### General

- Keep changes focused and atomic
- Write meaningful commit messages
- Test thoroughly before submitting

## Testing Checklist

Before submitting a PR, verify:

- [ ] Build succeeds on Windows
- [ ] Build succeeds on Linux
- [ ] OS boots in QEMU
- [ ] Tested at multiple resolutions
- [ ] No kernel panics or crashes
- [ ] Memory usage is stable

## Reporting Bugs

Use GitHub Issues with the bug template. Include:

- Steps to reproduce
- Expected behavior
- Actual behavior
- QEMU version and settings
- Screenshots if applicable

## Feature Requests

Use GitHub Issues with the feature request template. Describe:

- What feature you want
- Why it's needed
- Possible implementation approach

## Code of Conduct

This project is governed by the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold its terms.

## Questions?

Open a GitHub Discussion or email minecanton209@gmail.com.