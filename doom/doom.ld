OUTPUT_FORMAT(elf32-i386)
ENTRY(_start)

SECTIONS
{
    . = 0x02000000;

    .text : {
        *(.text*)
        *(.gnu.linkonce.t*)
    }

    .rodata : {
        *(.rodata*)
        *(.gnu.linkonce.r*)
    }

    .data : {
        *(.data*)
        *(.gnu.linkonce.d*)
    }

    .bss : {
        *(.bss*)
        *(COMMON)
    }

    .got : {
        *(.got*)
    }

    .got.plt : {
        *(.got.plt*)
    }

    __init_array_start = .;
    .init_array : {
        *(.init_array*)
    }
    __init_array_end = .;

    __fini_array_start = .;
    .fini_array : {
        *(.fini_array*)
    }
    __fini_array_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.eh_frame_hdr*)
        *(.gcc_except_table*)
        *(.debug*)
    }
}
