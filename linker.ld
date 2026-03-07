/* Linker script for NovumOS kernel */
OUTPUT_FORMAT(elf32-i386)
ENTRY(start)

SECTIONS {
    /* Kernel + User environment loads at 0x100000 (1MB) */
    . = 0x100000;
    _code_start = .;

    /* Single .text section — Zig compiles everything into one kernel.o
       Fine-grained protection is done via linksection() in Zig source */
    .text : {
        *(.text.start)
        *(.text*)
    }
    _code_end = .;

    _rodata_start = .;
    .rodata : {
        *(.rodata*)
    }
    _rodata_end = .;

    _data_start = .;
    .data : {
        *(.data*)
    }

    /* Critical kernel structures: page_directory, bitmap, page_tables
       These are placed here via linksection(".system") in memory.zig
       and mapped as Supervisor-only (no USER bit) in init_paging */
    .system ALIGN(4096) : {
        _system_start = .;
        *(.system*)
        . = ALIGN(4096);
        _system_end = .;
    }

    sbss = .;
    .bss : {
        *(.bss*)
        *(COMMON)
    }
    _data_end = .;
    ebss = .;

    /* Discard all debug and exception handling sections */
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.eh_frame_hdr*)
        *(.gcc_except_table*)
        *(.debug*)
    }
}
