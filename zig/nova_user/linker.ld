/* Linker script for Nova user-space ELF (Ring 3) */
OUTPUT_FORMAT(elf32-i386)
ENTRY(_start)

SECTIONS {
    /* Fixed load address — NOT PIE (elf.zig has no relocation support) */
    . = 0x08048000;

    .text : {
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
    }

    .data : {
        *(.data*)
    }

    .bss : {
        sbss = .;
        *(COMMON)
        *(.bss*)
        . = ALIGN(4096);
        ebss = .;
    }

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.eh_frame_hdr*)
        *(.gcc_except_table*)
        *(.debug*)
    }
}
