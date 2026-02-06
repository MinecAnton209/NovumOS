; NovumOS Kernel - 32-bit Protected Mode
; Main entry point and module includes
[bits 32]

; Constants
VIDEO_MEMORY    equ 0xb8000
MAX_COLS        equ 80
MAX_ROWS        equ 25
WHITE_ON_BLACK  equ 0x0f
GREEN_ON_BLACK  equ 0x0a
HISTORY_SIZE    equ 10

; Special key codes
KEY_UP          equ 0x80
KEY_DOWN        equ 0x81
KEY_LEFT        equ 0x82
KEY_RIGHT       equ 0x83

section .data
; OS State variables
shift_state     db 0
extended_key    db 0

; Put entry point in .text.start section to ensure it's first
section .text.start
global start

; External Zig / Linker symbols
extern zig_init
extern kmain
extern print_welcome
extern clear_screen
extern cursor_row
extern cursor_col
extern sbss
extern ebss

; External symbols from exceptions.zig
extern main_tss
extern df_tss
extern init_exception_handling

start:
    cli                         ; Disable interrupts during setup
    
    ; 1. Setup GDT (Global Descriptor Table)
    lgdt [gdt_descriptor_kernel]
    
    mov ax, 0x10                ; 0x10 is the data segment in GDT
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    
    ; 2. Setup Stack (at 5MB, safe from kernel/BSS)
    mov esp, 0x500000
    mov ebp, esp

    ; 3. Long jump to reload CS (Code Segment)
    jmp 0x08:.reload_cs
.reload_cs:
    jmp actual_code

; Kernel GDT Structure
align 16
gdt_kernel_start:
    dq 0                        ; Null descriptor (0x00)
    dw 0xffff, 0x0000, 0x9a00, 0x00cf ; Code segment (0x08)
    dw 0xffff, 0x0000, 0x9200, 0x00cf ; Data segment (0x10)
    ; Main TSS (0x18)
    dw 0x67, 0x0000, 0x8900, 0x0000
    ; DF TSS (0x20)
    dw 0x67, 0x0000, 0x8900, 0x0000
gdt_kernel_end:
gdt_descriptor_kernel:
    dw gdt_kernel_end - gdt_kernel_start - 1
    dd gdt_kernel_start

section .text
actual_code:
    ; 4. Clear BSS section (mandatory for Zig)
    mov edi, sbss
    mov ecx, ebss
    sub ecx, edi
    xor al, al
    rep stosb

    ; 5. Hardware Initialization
    call clear_screen

    ; Setup TSS in GDT
    call gdt_install_tss
    ; Initialize TSS data structures in Zig
    call init_exception_handling
    ; Load Task Register with Main TSS selector
    mov ax, 0x18
    ltr ax

    call idt_init               ; Setup IDT (now uses TSS 0x20 for vector 8)
    call init_serial            ; Setup COM1 for logging
    call zig_init               ; Initialize Zig modules (FS, etc)

    sti                         ; Re-enable interrupts
    
    ; 6. Print Welcome Messages
    call print_welcome

    ; 7. Transfer control to Zig Kernel
    call kmain
    
    ; Should never return
    cli
    hlt
    jmp $

; Helper: Install TSS base addresses into GDT
gdt_install_tss:
    ; Main TSS (0x18)
    mov eax, main_tss
    mov [gdt_kernel_start + 0x18 + 2], ax
    shr eax, 16
    mov [gdt_kernel_start + 0x18 + 4], al
    mov [gdt_kernel_start + 0x18 + 7], ah

    ; DF TSS (0x20)
    mov eax, df_tss
    mov [gdt_kernel_start + 0x20 + 2], ax
    shr eax, 16
    mov [gdt_kernel_start + 0x20 + 4], al
    mov [gdt_kernel_start + 0x20 + 7], ah
    ret

; --- Hardware Modules ---

; Initialize Serial COM1 (38400 baud, 8N1)
init_serial:
    mov dx, 0x3f8 + 1    ; IER
    xor al, al
    out dx, al           ; Disable all interrupts
    mov dx, 0x3f8 + 3    ; LCR
    mov al, 0x80
    out dx, al           ; Enable DLAB
    mov dx, 0x3f8 + 0    ; DLL
    mov al, 0x03         ; 38400 baud
    out dx, al
    mov dx, 0x3f8 + 1    ; DLM
    xor al, al
    out dx, al
    mov dx, 0x3f8 + 3    ; LCR
    mov al, 0x03         ; 8 bits, no parity, one stop bit
    out dx, al
    mov dx, 0x3f8 + 2    ; FCR
    mov al, 0xC7         ; Enable FIFO, clear them
    out dx, al
    mov dx, 0x3f8 + 4    ; MCR
    mov al, 0x0B         ; IRQs enabled
    out dx, al
    ret

; Include drivers
%include "idt.asm"
%include "drivers/keyboard.asm"