# NovumOS Memory Architecture

This document describes the high-performance memory management and paging system implemented in NovumOS.

---

## Physical Memory Management (PMM)

### Detection
The kernel uses **BIOS CMOS** registers (`0x30/31` and `0x34/35`) to detect available Physical RAM at boot. 
- Handles the 48MB overlap between standard extension and high-extension registers.
- Supports up to **4 GB** of addressable space.
- Includes a safety fallback to 128 MB if detection fails.

### Tracking
- **Bitmap Allocator:** Uses a 128 KB bitmap (located in BSS) to track the status of all 1,048,576 pages.
- **Relocated Kernel Area (1MB):** The kernel is loaded above the 1MB mark (`0x100000`) to avoid conflicts with **EBDA** and other BIOS-reserved memory regions.
- **Reservation:** every page below `max(kernel_end, 8 MB)` is marked busy at boot — the kernel image, boot structures and the kernel stack at `0x500000` all live inside that range.
- **Early-boot assumption:** `pmm.init` zeroes the bitmap and reserves pages **without locks or `cli`** — it must run single-threaded, before SMP and timer interrupts (`smp.init`). Never call it later in the boot sequence.
- **Contiguous growth:** `alloc_page_after(last_page)` returns the page physically right after `last_page` when it is free. The heap uses it to grow contiguously instead of hoping the linear scan lands next to its previous page.

### A20 Line
NovumOS explicitly activates the **A20 Line** (using BIOS Int 15h and the Fast A20 port 0x92) during boot to ensure full access to the 4GB address space and prevent memory wrap-around.

---

## Virtual Memory & Paging

### Huge Pages (PSE)
NovumOS utilizes **Page Size Extensions (PSE)** to enable **4 MB Huge Pages**.
- **Efficiency:** Drastically reduces the number of Page Table Entries (PTEs) and TLB pressure.
- **Implementation:** The Page Directory Entries (PDE) for most RAM regions have the **PS (Bit 7)** bit set.
- **Granularity:** The first **16 MB** (PDE 0–3) stay on standard **4 KB page tables** for precise control: the NULL page is not-present, IDT/system structures are supervisor-only, while code/rodata/data/heap remain user-accessible (Ring 3 shell and Nova live inside the kernel image).

### Demand Paging
To save physical memory and speed up boot time:
- Memory below **64 MB** is identity-mapped as Present at boot (16–64 MB as supervisor-only 4 MB huge pages).
- Memory above **64 MB** is marked as **Not Present** but pre-filled with physical addresses.
- When accessed, the `#PF` handler maps the page — **after** `check_user_permissions(vaddr)` on every user-mode fault. The gate runs before the huge-page fast path, so no path can grant USER bits without asking first.
- All page-table writes, including the 4 MB PDE read-modify-write on the huge-page path, hold `paging_lock` with interrupts off. The permission check and the lock are the two invariants of `map_page`.

### Fast Mapping (`map_range`)
For performance-critical allocations (like the `mem --test` tool), the kernel provides a bulk-mapping function that marks a range as Present without triggering expensive CPU exceptions.

---

## Heap

### Allocator
Segregated explicit free list with boundary tags (`zig/kernel/memory.zig`):
- **Blocks** carry `HEAP_MAGIC`, size, an end canary and padding canary; allocated memory is poisoned with `0xAA`, freed memory with `0xDF`.
- **Bins:** 27 size-segregated free lists. `alloc` splits large blocks; `free` merges neighbors inline — there is no separate sweep.
- **Validate before trust:** `free()` checks, in order: header inside a heap region → `block_size` plausible **and** region-contained → `requested <= block_size` → canary offset inside the block → canary bytes. The header lives in USER-RW memory (shell/Nova share the heap), so no field is used as an offset before it has been validated — a corrupted `requested` can no longer make `free()` dereference outside the block.

### Heap regions (coalescing safety)
`pmm.alloc_page` never guarantees physical adjacency, so the heap tracks its memory as up to **16 contiguous regions** (`base`, `end`) plus a `heap_high_water` mark:
- **Growth:** `allocate_new_page` first asks `pmm.alloc_page_after` for the page physically next to the heap top. A page touching an existing region extends it (regions it bridges are merged in); a page that lands elsewhere becomes a **standalone island** — pushed to the free list **without** coalescing.
- **Gates:** every neighbor-header dereference (forward/backward coalescing, `free()` itself) must first prove the whole candidate lies inside ONE region (`regionContains`). A foreign page that happens to contain `HEAP_MAGIC` can never be absorbed or freed into.
- **Boot reset:** `heap.init` clears bins, regions and high-water — warm-reboot RAM contents must not survive into a fresh heap.

### Garbage Collector
`garbage_collect()` is currently a reserved no-op behind `USE_GARBAGE_COLLECTOR`. Real reclamation is the inline coalescing in `free()` described above.

---

## Testing Tools
The `mem --test [MB]` command performs a stress test:
1. Allocates the requested size.
2. Uses `map_range` for fast PSE mapping.
3. Fills every page with a pattern.
4. Tracks total Page Faults handled during the process.
5. Can be aborted via **Ctrl+C**.
