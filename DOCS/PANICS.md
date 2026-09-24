# NovumOS Kernel Panics

Every fatal error paints the **RSOD** (Red Screen of Death, background
`0xCC0000` / VGA attr `0x4F`), silences the speaker, disables interrupts
and mirrors the report to serial. With `ENABLE_RSOD_REBOOT = true`
(default in `zig/config.zig`) the screen ends with
`SYSTEM HALTED. Press ENTER to reboot.` — ENTER pulses the keyboard
controller reset line (`outb(0x64, 0xFE)`). Nothing is written to disk:
**capture the screen and serial output before rebooting.**

---

## What to do first (any panic)

1. Copy the serial block — run QEMU with `-serial stdio` so the full
   report lands in your terminal — or screenshot the RSOD.
2. Note the **EIP** shown on screen: that is the faulting instruction in
   `build/kernel32.elf` (only for hardware exceptions — see the
   `0xFF` caveat below).
3. For a page fault also note **CR2** (the fault address) and the error
   code bits.
4. Re-run with exception tracing:
   ```bash
   qemu-system-i386 -cdrom NovumOS.iso -serial stdio -d int,cpu_reset -D qemu.log
   ```
5. Or single-step from the panic:
   ```bash
   qemu-system-i386 -cdrom NovumOS.iso -serial stdio -s -S
   # then: gdb build/kernel32.elf  →  target remote localhost:1234
   ```
6. Press ENTER to reboot (or restart QEMU).

---

## Panic types

### 1. Hardware exceptions (real register frame on screen)

Raised by the IDT handlers in `zig/arch/x86/exceptions.zig`. The RSOD
shows the vector, error code, EIP and all general registers.

| Exception | Vector | Typical cause | What to do after |
|-----------|--------|---------------|------------------|
| Page fault `#PF` | 14 | Null or wild pointer, use-after-free, buffer overrun into an unmapped page, stack growth past its mapping. Low-address/user faults add the hint `Stack overflow or null pointer dereference`. | Map EIP to the faulting code. CR2 ≈ 0 → null deref. CR2 near the current stack top → stack overflow (process stacks are 8 KiB). CR2 inside heap/data → suspect corruption and check recent alloc/free changes. |
| Double fault `#DF` | 8 | Almost always a stack overflow (interrupt on a dead stack); also what the `stack_overflow` debug command triggers. | Reduce recursion / large on-stack arrays; check ISR and process stack depths; validate IDT/GDT are intact (see watchdog below). |
| General protection `#GP` | 13 | Privileged instruction or `in`/`out`/`cli` executed from Ring 3 without its syscall gate; corrupt segment selector. `gpf` debug command triggers it on purpose. | If EIP is in Ring-3-reachable code, find the raw asm missing its gate. Otherwise decode the selector/error code on screen. |
| Invalid opcode `#UD` | 6 | Indirect call/jump through a corrupted function pointer, execution of data. `invalid_op` debug command triggers it. | Inspect the call target that produced EIP; look for overwritten pointer tables. |
| Anything else (`#DE`, `#BP`, `#MF`, …) | varies | Divide by zero, debug traps, whatever the vector table says. | Read the vector number on the RSOD and look it up — the handler reports it verbatim. |

### 2. Explicit panic messages (synthetic frame, vector `0xFF`)

These come from `@panic(...)` / `std` panics routed through
`exceptions.panic(msg)`. **Caveat: the frame is synthetic — EIP on
screen is `0`; registers are captured at the panic site, but the faulting
code location must come from QEMU log or GDB.**

| Message | Meaning | What to do after |
|---------|---------|------------------|
| `Heap: Internal free failed (bad pointer, magic or double-free)` | `free()` rejected the pointer: bad magic, broken canary, double-free, or the block lies outside all heap regions. | The heap is USER RW (shell and Nova share it) — hunt for a buffer overrun in code writing near a heap allocation, or a double `free`. Break on `exceptions.panic` under GDB and inspect the argument pointer. |
| `OOM: Failed to allocate bootstrap process` | Heap/PMM exhausted while creating the scheduler's bootstrap process during boot. | Give QEMU more RAM (`-m 2G`), check that `pmm.init` reservations match the memory map. |
| `OOM: Failed to allocate user stack page` | PMM out of pages while loading an ELF. | Add RAM, check for leaks with the `mem` command, verify nothing allocates in a loop before `exec`. |
| `Spinlock in Ring 3` | A spinlock path was reached from user mode — a ring-0-only invariant was violated. | Find the Ring-3 caller at EIP; the lock must be wrapped by its ring check (see `smp.zig`). |

### 3. IDT watchdog

Message: `IDT integrity check failed! Table has been modified.`

A periodic checksum over the IDT (timer tick, scheduler, keyboard paths)
found a changed gate. The `idt-check` / `idt-modify` / `idt-move` debug
commands also feed this check — `idt-modify` and `idt-move` trip it on
purpose.

**After:** think corrupted write that reached the IDT page (heap
overflow, bad asm) or a leftover from IDT debugging. Reproduce under
`-s -S` and compare the live table against the watchdog snapshot
(`idt_watchdog.get_idt_base()` in GDB: `x/64wx <base>`).

### 4. Intentional debug panics

Behind `ENABLE_DEBUG_CRASH_COMMANDS` in `zig/config.zig`
(`false` for release images):

`panic`, `abort`, `gpf`, `invalid_op`, `page_fault`, `stack_overflow`,
`idt-check`, `idt-modify`, `idt-move`, `smp-test`.

These are **supposed** to produce the red screens above — they test the
RSOD/serial/reboot path itself. Expected outcome: RSOD + serial report +
ENTER reboots. Turn the flag off if you want a build that cannot be
crashed from the shell.

---

## After the reboot

1. Does it reproduce deterministically? If yes — bisect recent commits.
2. Only on SMP? Re-run with `-smp 1` to separate races from logic bugs.
3. File the issue with the serial log, QEMU log and steps to reproduce
   (template in [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)).
