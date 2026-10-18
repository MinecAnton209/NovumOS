# Fork and address-space isolation: current state

This note records what the memory and process code does today, why copy-on-write
`fork()` cannot be added on top of it, and what has to change first. Everything
below was checked against the code and, where stated, reproduced under QEMU.

## Facts

- **One page directory for everything.** `memory.page_directory` is global.
  `scheduler.create_process_locked` sets `p.cr3 = memory.get_current_pd()`
  ("Inherit kernel page directory for now"), and no context switch writes CR3.
  Every process runs in the same address space.
- **Huge-page kernel mapping.** The kernel is identity-mapped with 4 MiB PS pages
  above the first 16 MiB. `map_page_at_locked` grants USER on the whole 4 MiB
  PDE when a user request touches one address in that range, so a single user
  fault can expose a whole huge page, not one 4 KiB page.
- **User mode can reach kernel data.** `check_user_permissions` allows any RAM
  address at or above the kernel image and below `MAX_MEMORY`, and maps
  `.system` pages with attribute `0x7` (user RW). The kernel heap lives in that
  range.
- **The shell runs in Ring 3 and calls kernel code directly.** Reproduced under
  QEMU: `sched-test` faulted with `CS=0xA3` on `mov eax, cr3`, which is
  privileged. Commands such as `nice` do work from Ring 3, which means they write
  kernel structures from Ring 3 without a syscall boundary.
- **Syscall path shares one kernel stack.** SYSENTER switches to
  `BSP_KERNEL_ESP` (0x500000) for every process.
- **IDT watchdog assumes a fixed CR3.** `idt_watchdog` records CR3 at boot and
  panics on any mismatch, so per-process page directories need a watchdog change.

## Why copy-on-write fork is blocked

A correct `fork()` needs all of the following, and each depends on the previous one:

1. A page directory per address space, with the kernel half shared and the user
   half private, and a CR3 write on every switch (timer path and SYSENTER path).
2. Huge kernel pages split into 4 KiB PTEs wherever user mappings exist, so
   that user pages can be made read-only without touching kernel pages.
3. A per-physical-page reference count, decremented in `free_page`.
4. A page-fault branch for "present, write, COW bit set" that copies the page.
5. Kernel writes into user memory (copy-in/copy-out of syscall buffers) must
   respect COW. With `CR0.WP` clear, supervisor writes ignore read-only PTEs, so
   WP has to be set first.
6. A child frame built from the parent's syscall registers, returning 0 in EAX.
7. The IDT watchdog CR3 check made per-process aware.

Steps 1, 2 and 5 are the real work. Until user mode is actually separated from
kernel data (the isolation issues above), copy-on-write adds risk without a
security boundary.

## Suggested order

1. Set CR0.WP and verify the kernel does not depend on writing read-only pages.
2. Restrict `check_user_permissions` so user mappings never touch kernel image,
   heap or `.system`, and make `map_page` split huge pages instead of setting
   USER on them.
3. Move shell commands that need privileged state behind syscalls, starting with
   `nice` and `sched-test`, the same way `sched-test` now spawns through syscall 117.
4. Per-process page directories and CR3 switching, with the watchdog updated.
5. Reference counts, the COW fault branch, then `fork()`.

Each step is testable on its own under QEMU. Step 2 is the security fix and is
worth doing even if fork is never added.
