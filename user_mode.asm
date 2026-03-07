; User Mode Logic and Transition
[bits 32]

global jump_to_ring3_entry
extern handle_syscall_zig

section .text

; Function called from Zig: jump_to_ring3_entry(entry_address, stack_address)
jump_to_ring3_entry:
    cli
    mov ebp, [esp + 4]   ; Get entry point address from argument
    mov ecx, [esp + 8]   ; Get stack address from argument
    
    ; Prepare stack for IRET:
    ; [ESP + 16] SS
    ; [ESP + 12] ESP
    ; [ESP + 8]  EFLAGS
    ; [ESP + 4]  CS
    ; [ESP + 0]  EIP
    
    push 0xAB           ; SS (User Data Segment: 0xA8 | 3)
    push ecx            ; ESP (User Stack passed from Zig)
    push 0x202          ; EFLAGS (IF set)
    push 0xA3           ; CS (User Code Segment: 0xA0 | 3)
    push ebp            ; EIP (Entry point passed as argument)
    
    ; Set segment registers to User Data
    mov ax, 0xAB
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; Jump!
    iret
