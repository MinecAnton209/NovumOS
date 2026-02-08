# NovumOS Release Notes

## 🚀 Release Notes - NovumOS v0.22.0

**Date:** February 8, 2026
**Version:** v0.22.0

### 🌟 Highlights - The Modular & Multi-line Update

This release marks a major evolution of the **Nova Language**, transitioning from a linear script executor to a structured, modular system. We've introduced mandatory syntax rules for better code reliability and a significantly more powerful interactive environment.

#### 📦 Modular Architecture
- **Namespaced Commands:** Built-in functions have been moved into dedicated modules (`math` and `sys`). This prevents namespace pollution and allows for cleaner code organization.
- **Explicit Imports:** You now use `import "math";` or `import "sys";` to load these modules. Functions are then accessed via `math.sin()`, `sys.delay()`, etc.
- **On-Demand Loading:** Modules are only active when explicitly requested, optimizing the interpreter's memory footprint during execution.

#### ⌨️ Advanced REPL & Multi-line Support
- **Multi-line Input (Accumulator):** The REPL now supports multi-line statements. If a line is not terminated with a `;` or a closing brace `}`, Nova enters a "continuation mode" (indicated by a `...` prompt).
- **Mandatory Semicolons:** To support complex expressions and multi-line formatting, all statements now require a `;` terminator.
- **Enhanced history:** Multi-line commands are saved correctly in the command history (now expanded to **20 entries**).
- **Ctrl+C Integration:** Pressing `Ctrl+C` while typing a multi-line command now safely clears the accumulator buffer instead of exiting the interpreter.

#### 🧠 Context-Aware Tab Completion
- **Module Sensitivity:** Tab completion is now aware of your imports. Functions like `math.max(` or `sys.reboot();` will only appear in suggestions *after* you have imported the respective module.
- **Smart Separators:** The completion engine now correctly detects prefixes after common separators like `(`, `,`, `+`, and `"`.
- **Predefined Fragments:** Added completions for `import "math";`, `import "sys";`, `math.`, and `sys.` to speed up coding.

#### 🛡️ Runtime Stability & Validation
- **Soft Errors in REPL:** Runtime errors (like calling an undefined function) no longer exit the Nova interpreter. You receive a descriptive error message and remain in the REPL environment.
- **Parameter Validation:** Added strict syntax checking for every built-in function. The interpreter now reports missing commas or parentheses immediately, providing much clearer feedback than v0.21.
- **Buffer Overflow Protection:** Increased internal buffers to **4KB** to handle large multi-line scripts comfortably.

#### 📖 Documentation & Polish
- **Updated Guides:** `README.md` and `DOCS/NOVA.md` have been fully updated to reflect the v0.22.0 rules and modular syntax.
- **Version Sync:** Both the NovumOS kernel and Nova interpreter are now synchronized at version **0.22.0**.

---

## 🚀 Release Notes - NovumOS v0.21.0

**Date:** February 8, 2026
**Version:** v0.21.0

### 🌟 Highlights - The Precision & UX Update

This release brings a long-awaited feature to the Nova Language: **Full Floating Point Support**. We've also overhauled the user experience (UX) to make Nova feel like a professional system tool rather than a debug console.

#### 🧪 Nova Language & Math
- **Floating Point Engine:** Nova now supports 32-bit floating point numbers (`float`). You can use decimal literals like `3.14` and perform precise arithmetic and comparisons across the language.
- **High-Precision Trig:** Implemented a custom math engine using **Bhaskara I's formula** for `sin()` and `cos()`. This delivers high accuracy for kernel-space calculations without external dependencies.
- **New Math Functions:** Added `abs()`, `min()`, `max()`, `rad()`, and `deg()`, all fully compatible with the new float engine.

#### 💾 Filesystem & Automation
- **Native FS Functions:** Added advanced filesystem control to Nova scripts and REPL:
    - `create_file(path)`
    - `delete(path)` (with aliases `rm`, `remove`)
    - `rename(old, new)` (with alias `mv`)
    - `copy(src, dest)` (with alias `cp`)
- **Directory Management:** `mkdir()` now returns status messages for better automation scripts.

#### 🖥 User Experience (UX)
- **Informative REPL:** Commands now return human-readable status strings (e.g., "File created", "Data written") instead of confusing numeric codes.
- **Clean Console Output:** Void functions like `print()`, `delay()`, and `exec()` no longer clutter the screen with extra return values.
- **Fixed exit():** The `exit()` command now correctly terminates the Nova environment and returns you to the system shell with a friendly goodbye.

#### 📖 Documentation
- **Comprehensive Guide:** Restored and expanded `DOCS/NOVA.md`. It now includes detailed tables, usage examples for every built-in function, and updated technical specs for v0.21.0.

---
