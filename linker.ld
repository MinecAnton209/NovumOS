/* Linker script for NovumOS kernel */
OUTPUT_FORMAT(elf32-i386)
ENTRY(start)

SECTIONS {
    /* Kernel loads at 0x10000 */
    . = 0x10000;
    
    /* Code section first - start symbol must be at 0x10000 */
    .text : {
        *(.text.start)
        *(.text*)
    }
    
    .rodata : {
        *(.rodata*)
    }
    
    .data : {
        *(.data*)
    }
    
    sbss = .;
    .bss : {
        *(.bss*)
        *(COMMON)
    }
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
