; NovumOS Bootloader - 16-bit Real Mode (LBA Support)
[bits 16]
[org 0x7c00]

KERNEL_OFFSET equ 0x10000

start:
    ; 1. Initialize segment registers and stack
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    
    ; 2. Save boot drive index
    mov [BOOT_DRIVE], dl
    
    ; 3. Check LBA support
    mov ah, 0x41
    mov bx, 0x55aa
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc disk_error
    
    ; 4. Load kernel using LBA Packet
    ; We'll load it in two steps to be safe
    
    ; Step 1: Load 127 sectors
    mov si, dap
    mov byte [si], 0x10      ; Packet size
    mov byte [si+1], 0       ; Reserved
    mov word [si+2], 127     ; Count
    mov word [si+4], 0       ; Offset
    mov word [si+6], 0x1000  ; Segment
    mov dword [si+8], 1      ; LBA Start (Sector 2)
    mov dword [si+12], 0     ; LBA High
    
    mov ah, 0x42
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc disk_error
    
    ; Step 2: Load next 128 sectors (Total 255 sectors = 127.5KB)
    mov word [si+2], 128     ; Next chunk
    mov word [si+6], 0x1FE0  ; Next segment (0x1000 + (127 * 512 / 16))
    mov dword [si+8], 128    ; LBA Start (1 + 127)
    
    mov ah, 0x42
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc disk_error
    
    ; 5. Clear screen
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    
    ; 6. Switch to Protected Mode
    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:init_pm

[bits 32]
init_pm:
    mov ax, 0x10
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ebp, 0x500000
    mov esp, ebp
    jmp KERNEL_OFFSET

disk_error:
    jmp $

; GDT
gdt_start:
    dq 0
gdt_code:
    dw 0xffff, 0
    db 0, 10011010b, 11001111b, 0
gdt_data:
    dw 0xffff, 0
    db 0, 10010010b, 11001111b, 0
gdt_end:
gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

align 4
dap: times 16 db 0
BOOT_DRIVE: db 0

times 510-($-$$) db 0
dw 0xaa55