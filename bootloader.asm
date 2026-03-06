; NovumOS Bootloader - 16-bit Real Mode (LBA Support)
[bits 16]
[org 0x7c00]

KERNEL_OFFSET equ 0x100000      ; Actual location (1MB)
LOAD_BUFFER   equ 0x10000       ; Temp buffer (64KB)

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
    
    ; 4. Load kernel to 0x10000 (LOAD_BUFFER)
    
    ; Step 1: Load Initial Part (127 sectors)
    mov si, dap
    mov byte [si], 0x10      ; Packet size
    mov byte [si+1], 0       ; Reserved
    mov word [si+2], 127     ; Count
    mov word [si+4], 0       ; Offset
    mov word [si+6], 0x1000  ; Segment (0x10000 physical)
    mov dword [si+8], 1      ; LBA Start (Sector 2)
    mov dword [si+12], 0     ; LBA High
    
    mov ah, 0x42
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc disk_error
    
    ; Step 2: Loop to load up to 1024 sectors (~512KB) into LOAD_BUFFER
    mov word [si+2], 64      ; Count per step
    mov word [si+6], 0x1FE0  ; Start after first 127 sectors
    mov dword [si+8], 128    ; Start LBA (1 + 127)
    
    mov cx, 14               ; 14 * 64 = 896 sectors more
.load_loop:
    push cx
    mov ah, 0x42
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc disk_error
    
    add word [si+6], 0x0800  ; Increment segment
    add dword [si+8], 64     ; Increment LBA
    pop cx
    loop .load_loop
    
    ; 5. Set up VBE Linear Framebuffer (with validation)
    xor ax, ax
    mov es, ax
    jmp .vbe_start

    ; --- Data ---
    align 2
.current_mode: dw 0
.vbe_candidates:
    dw 0x011B, 0x0118, 0x0115, 0x0112, 0xFFFF

.vbe_start:
    mov si, .vbe_candidates

.vbe_try_next:
    mov cx, [si]
    add si, 2
    cmp cx, 0xFFFF
    je .vbe_none

    mov [.current_mode], cx
    mov ax, 0x4f01
    mov di, 0x8000
    int 0x10
    cmp ax, 0x004f
    jne .vbe_try_next

    mov ax, [0x8000]
    test ax, 0x0001
    jz .vbe_try_next
    test ax, 0x0080
    jz .vbe_try_next

    mov bx, [.current_mode]
    or  bx, 0x4000
    mov ax, 0x4f02
    int 0x10
    cmp ax, 0x004f
    jne .vbe_try_next

    xor ax, ax
    mov es, ax
    mov cx, [.current_mode]
    mov ax, 0x4f01
    mov di, 0x8000
    int 0x10
    jmp .vbe_done

.vbe_none:
    mov bx, 0x4112
    mov ax, 0x4f02
    int 0x10
    xor ax, ax
    mov es, ax
    mov cx, 0x0112
    mov ax, 0x4f01
    mov di, 0x8000
    int 0x10

.vbe_done:
    ; --- Enable A20 Line ---
    mov ax, 0x2401
    int 0x15
    in al, 0x92
    or al, 2
    out 0x92, al

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

    ; --- COPY KERNEL FROM 0x10000 TO 0x100000 ---
    ; We copy 512 KB to be sure (131072 dwords)
    mov esi, 0x10000    ; Source
    mov edi, 0x100000   ; Destination
    mov ecx, 131072     ; 512 * 1024 / 4
    rep movsd

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

align 16
dap: times 16 db 0
BOOT_DRIVE: db 0

times 510-($-$$) db 0
dw 0xaa55
