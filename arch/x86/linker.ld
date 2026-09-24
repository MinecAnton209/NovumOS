/* Linker script for NovumOS kernel - Limine/Multiboot2 */
OUTPUT_FORMAT(elf32-i386)
ENTRY(_start)

SECTIONS {
    /* Kernel loads at 0x100000 (1MB) */
    . = 0x100000;

    /* Multiboot2 header */
    .multiboot : {
        KEEP(*(.multiboot))
    }

    /* Additional boot requests */
    .requests : {
        KEEP(*(.requests))
    }

    /* Kernel code */
    .text : {
        *(.text.start)
        *(.text*)
    } =0x90909090

    _code_start = ADDR(.text);
    _code_end = ADDR(.text) + SIZEOF(.text);

    _rodata_start = .;
    .rodata : {
        *(.rodata*)
    }
    _rodata_end = .;

    _data_start = .;
    .data : {
        *(.data*)
    }

    /* Critical kernel structures: page_directory, bitmap, page_tables */
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

    /* Discard debug and exception handling sections */
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.eh_frame_hdr*)
        *(.gcc_except_table*)
        *(.debug*)
    }
}