[bits 16]
[org 0x8000]

start:
    cli                         ; Disable interrupts
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax

    ; 1. Load temporary GDT for switching to Protected Mode (PM)
    lgdt [gdt_descriptor]

    ; 2. Set Protected Mode (PE) bit in CR0
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 3. Far jump to clear the prefetch queue and switch to 32-bit code segment
    jmp 0x08:ap_entry_32

[bits 32]
ap_entry_32:
    ; 4. Set up data segment registers
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; 5. Set up unique stack for this CPU core
    ; Memory at 0x7000 is used as a mailbox where the BSP 
    ; places the stack address before sending the IPI.
    mov esp, [0x7000]

    ; 5.5 Enable SSE (CR4.OSFXSR | CR4.OSXMMEXCPT)
    mov eax, cr4
    or eax, 0x600           ; OSFXSR=1, OSXMMEXCPT=1
    mov cr4, eax
    mov eax, cr0
    and ax, 0xFFFB          ; Clear EM (bit 2)
    or ax, 0x2              ; Set MP (bit 1)
    mov cr0, eax

    ; 6. Signal BSP that this core is ready (using lock for atomicity)
    lock inc dword [0x9000]

    ; 7. Jump into the main Zig kernel code
    ; Address of ap_kernel_entry is stored at 0x7004
    mov eax, [0x7004]
    jmp eax

; Temporary GDT for the trampoline (matches the main kernel GDT structure)
gdt_start:
    dq 0x0                      ; Null descriptor
gdt_code:
    dw 0xFFFF                   ; Limit
    dw 0x0000                   ; Base low
    db 0x00                     ; Base middle
    db 10011010b                ; Access (Exec/Read)
    db 11001111b                ; Flags/Limit high
    db 0x00                     ; Base high
gdt_data:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b                ; Access (Read/Write)
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start
