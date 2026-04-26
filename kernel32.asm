; NovumOS Kernel - 32-bit Protected Mode
; Main entry point and module includes
; Used by Limine bootloader via Multiboot2 protocol
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

; Multiboot2 info filled by bootloader
align 4
global mb2_info
mb2_info:
    dd 0
global fb_addr
fb_addr:
    dd 0          ; framebuffer physical address
global fb_pitch
fb_pitch:
    dd 0          ; bytes per scanline
global fb_width
fb_width:
    dd 0          ; framebuffer width in pixels
global fb_height
fb_height:
    dd 0          ; framebuffer height in pixels
global fb_bpp
fb_bpp:
    dd 0          ; bits per pixel

section .text.start
global _start
_start equ limine_start

section .multiboot
align 8
_multiboot2_header_start:
    ; --- Main header ---
    dd 0xe85250d6                ; Magic: Multiboot2
    dd 0                         ; Architecture: i386 (32-bit)
    dd _multiboot2_header_end - _multiboot2_header_start ; Header length
    ; Checksum: -(magic + arch + length)
    dd -(0xe85250d6 + 0 + (_multiboot2_header_end - _multiboot2_header_start))

    ; --- Framebuffer request ---
    align 8
    dw 5                         ; Type 5: Framebuffer request
    dw 0                         ; Flags
    dd 20                        ; Size
    dd 1024                      ; Width (0 = default)
    dd 768                       ; Height
    dd 32                        ; Depth (32 bpp)

    ; --- Closing tag ---
    align 8
    dw 0                         ; Type 0
    dw 0                         ; Flags
    dd 8                         ; Size
_multiboot2_header_end:
align 8

; External Zig / Linker symbols
extern zig_init
extern kmain
extern clear_screen
extern cursor_row
extern cursor_col
extern sbss
extern ebss

; External symbols from exceptions.zig
extern cores_tss
extern df_tss
extern init_exception_handling

section .data
; Kernel GDT Structure
align 16
gdt_kernel_start:
    dq 0                        ; Null descriptor (0x00)
    dw 0xffff, 0x0000, 0x9a00, 0x00cf ; Code segment (0x08)
    dw 0xffff, 0x0000, 0x9200, 0x00cf ; Data segment (0x10)
    times 16 dw 0x0067, 0x0000, 0x8900, 0x0000 ; Core TSS slots
    dw 0x0067, 0x0000, 0x8900, 0x0000 ; DF TSS
    dw 0xffff, 0x0000, 0xfa00, 0x00cf ; User Code segment
    dw 0xffff, 0x0000, 0xf200, 0x00cf ; User Data segment
gdt_kernel_real_end:
global gdt_descriptor_kernel
gdt_descriptor_kernel:
    dw gdt_kernel_real_end - gdt_kernel_start - 1
    dd gdt_kernel_start

section .text.start
limine_start:
    cli
    lgdt [gdt_descriptor_kernel]
    
    mov ax, 0x10                ; 0x10 is the data segment in GDT
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    
    ; Setup Stack (at 5MB, safe from kernel/BSS)
    mov esp, 0x500000
    mov ebp, esp

    ; Long jump to reload CS (Code Segment)
    jmp 0x08:.reload_cs
.reload_cs:

section .text
actual_code:
    ; Parse Multiboot2 info to get framebuffer address from bootloader
    mov ebp, ebx
    add ebp, 8  ; Skip header (total_size + reserved)

.parse_tag:
    mov eax, [ebp]      ; tag type
    mov ecx, [ebp + 4] ; tag size

    cmp eax, 0         ; End tag (type 0)?
    je .no_framebuffer

    cmp eax, 8         ; Framebuffer tag (type 8)?
    je .found_fb

    ; Skip to next tag (aligned to 8 bytes)
    add ebp, ecx
    mov eax, ebp
    and eax, 7
    jz .parse_tag
    add ebp, 8
    sub ebp, eax
    jmp .parse_tag

.found_fb:
    ; Framebuffer tag: read fields
    ; type(4) + size(4) + addr(8) + pitch(4) + width(4) + height(4) + bpp(1) + type(1) + reserved(2)
    mov eax, [ebp + 8]
    mov [fb_addr], eax
    mov eax, [ebp + 16]
    mov [fb_pitch], eax
    mov eax, [ebp + 20]
    mov [fb_width], eax
    mov eax, [ebp + 24]
    mov [fb_height], eax
    movzx eax, byte [ebp + 28]  ; bpp is u8
    mov [fb_bpp], eax
    jmp .done_parse

.no_framebuffer:
    ; No framebuffer provided
    mov al, 'N'
    call debug_putc

.done_parse:
    mov al, 'D'
    call debug_putc

    ; Early boot visual feedback - draw test pattern to framebuffer
    mov eax, [fb_addr]
    test eax, eax
    jz .skip_fb_write

    ; Draw gradient: white rows on even Y, red rows on odd Y
    mov edi, eax
    mov ebx, [fb_height]
    mov eax, [fb_width]

.fill_y:
    push eax
    push ebx
    mov ecx, eax         ; width
    mov ebx, edi
    sub ebx, [fb_addr]
    shr ebx, 16         ; approximate row number
    and ebx, 1
    test ebx, ebx
    jnz .row_red

.row_white:
    mov [edi], dword 0xFFFFFFFF  ; white pixel
    add edi, 4
    loop .row_white
    jmp .row_done

.row_red:
    mov [edi], dword 0x000000FF  ; red pixel
    add edi, 4
    loop .row_red

.row_done:
    pop ebx
    pop eax
    dec ebx
    jnz .fill_y

.skip_fb_write:
    mov al, 'K'
    call debug_putc

    ; Enable SSE (required by modern compilers like Zig/Clang)
    mov eax, cr0
    and ax, 0xFFFB      ; Clear EM bit
    or ax, 0x0002       ; Set MP bit
    mov cr0, eax
    mov eax, cr4
    or ax, 0x0600       ; Set OSFXSR and OSXMMEXCPT bits
    mov cr4, eax

    ; Clear BSS section (mandatory for Zig)
    mov edi, sbss
    mov ecx, ebss
    sub ecx, edi
    xor al, al
    rep stosb

    mov al, 'P'
    call debug_putc

    ; Hardware Initialization
    call clear_screen

    mov al, 'C'
    call debug_putc

    ; Setup TSS in GDT
    call gdt_install_tss
    ; Initialize TSS data structures in Zig
    call init_exception_handling
    ; Load Task Register with the first Core's TSS (BSP)
    mov ax, 0x18
    ltr ax

    mov al, 'G'
    call debug_putc

    call idt_init               ; Setup IDT (now uses TSS 0x98 for vector 8)
    call init_serial            ; Setup COM1 for logging
    call zig_init               ; Initialize Zig modules (FS, etc)

    mov al, 'I'
    call debug_putc

    sti                         ; Re-enable interrupts

    ; Transfer control to Zig Kernel
    call kmain

    ; Should never return
    cli
    hlt
    jmp $

; Helper: Install TSS base addresses into GDT
gdt_install_tss:
    pushad
    mov ecx, 16                 ; 16 core descriptors
    mov esi, cores_tss          ; Base of Zig cores_tss array
    mov edi, gdt_kernel_start + 0x18 ; GDT entry for first core
.tss_loop:
    mov eax, esi
    mov [edi + 2], ax
    shr eax, 16
    mov [edi + 4], al
    mov [edi + 7], ah
    add esi, 104                ; sizeof(TSS) = 104
    add edi, 8                  ; sizeof(GDT entry) = 8
    loop .tss_loop

    ; DF TSS (0x98)
    mov eax, df_tss
    mov [gdt_kernel_start + 0x98 + 2], ax
    shr eax, 16
    mov [gdt_kernel_start + 0x98 + 4], al
    mov [gdt_kernel_start + 0x98 + 7], ah
    popad
    ret

; --- Hardware Modules ---

; Initialize debug serial port (COM1, 38400 baud)
debug_putc_init:
    mov dx, 0x3f8 + 1    ; IER
    xor al, al
    out dx, al
    mov dx, 0x3f8 + 3   ; LCR
    mov al, 0x80
    out dx, al
    mov dx, 0x3f8 + 0    ; DLL
    mov al, 0x03
    out dx, al
    mov dx, 0x3f8 + 1   ; DLM
    xor al, al
    out dx, al
    mov dx, 0x3f8 + 3
    mov al, 0x03
    out dx, al
    ret

; Write character to debug serial port
debug_putc:
    push eax
    mov dx, 0x3f8 + 5
.wait:
    in al, dx
    test al, 0x20
    jz .wait
    pop eax
    mov dx, 0x3f8
    out dx, al
    ret

; Write 32-bit hex value to debug serial
debug_putc_hex:
    pushad
    mov ecx, 8
.hex_loop:
    rol eax, 4
    mov ebx, eax
    and ebx, 0x0f
    add ebx, '0'
    cmp ebx, '9'
    jle .hex_skip
    add ebx, 'a' - '9' - 1
.hex_skip:
    push eax
    mov al, bl
    call debug_putc
    pop eax
    loop .hex_loop
    popad
    ret

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
