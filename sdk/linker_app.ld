/* Linker Script for NovumOS User Applications */
/* Base Address: 4MB (0x400000) */

OUTPUT_FORMAT("elf32-i386")
ENTRY(main)

SECTIONS
{
    /* Load at 4MB */
    . = 0x400000;

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
        *(.bss*)
        *(COMMON)
    }
}
