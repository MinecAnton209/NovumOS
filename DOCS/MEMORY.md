# NovumOS Memory Architecture (v0.18)

This document describes the high-performance memory management and paging system implemented in NovumOS.

---

## 🏗 Physical Memory Management (PMM)

### Detection
The kernel uses **BIOS CMOS** registers (`0x30/31` and `0x34/35`) to detect available Physical RAM at boot. 
- Handles the 48MB overlap between standard extension and high-extension registers.
- Supports up to **4 GB** of addressable space.
- Includes a safety fallback to 128 MB if detection fails.

### Tracking
- **Bitmap Allocator:** Uses a 128 KB bitmap (located in BSS) to track the status of all 1,048,576 pages.
- **Reserved Zone:** The first **8 MB** of RAM are strictly reserved for:
  - Kernel Code & Data
  - GDT/IDT
  - Kernel Stack (5 MB)
  - PMM Bitmap & Early Page Tables

---

## ⚡ Virtual Memory & Paging

### Huge Pages (PSE)
NovumOS utilizes **Page Size Extensions (PSE)** to enable **4 MB Huge Pages**.
- **Efficiency:** Drastically reduces the number of Page Table Entries (PTEs) and TLB pressure.
- **Implementation:** The Page Directory Entries (PDE) for most RAM regions have the **PS (Bit 7)** bit set.
- **Granularity:** The first 4 MB remain mapped using standard **4 KB pages** to allow for precise **NULL-page protection** (0x0 is marked not-present).

### Demand Paging
To save physical memory and speed up boot time:
- Memory below **64 MB** is identity-mapped as Present at boot.
- Memory above **64 MB** is marked as **Not Present** but pre-filled with physical addresses.
- When accessed, the `#PF` (Page Fault) handler simply flips the **Present bit** in the PDE/PTE.

### Fast Mapping (`map_range`)
For performance-critical allocations (like the `mem --test` tool), the kernel provides a bulk-mapping function that marks a range as Present without triggering expensive CPU exceptions.

---

## 🧹 Heap & Garbage Collection

### Linked List Allocator
The kernel heap uses a header-based linked list system for dynamic allocation.
- **Block Splitting:** Large free blocks are split to minimize waste.
- **Coalescing:** Adjacent free blocks are merged to prevent fragmentation.

### Garbage Collector (GC)
A manual/automatic garbage collection routine (`garbage_collect`) can be triggered to perform a full heap sweep and block merging. 
- Integrated into the `mem --test` utility.
- Safe to call from IRQ contexts or the shell.

---

## 🛠 Testing Tools
The `mem --test [MB]` command performs a stress test:
1. Allocates the requested size.
2. Uses `map_range` for fast PSE mapping.
3. Fills every page with a pattern.
4. Tracks total Page Faults handled during the process.
5. Can be aborted via **Ctrl+C**.
