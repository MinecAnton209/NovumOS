; User Mode Logic and Transition
[bits 32]

global jump_to_ring3
extern handle_syscall_zig

section .text

; Function called from Zig to jump into Ring 3
jump_to_ring3:
    cli
    ; The Zig function might have changed segments, but we want a clean state
    
    ; Prepare stack for IRET:
    ; [ESP + 16] SS
    ; [ESP + 12] ESP
    ; [ESP + 8]  EFLAGS
    ; [ESP + 4]  CS
    ; [ESP + 0]  EIP
    
    push 0x33           ; SS (User Data Segment: 0x30 | 3)
    push 0x3FFFF0       ; ESP (User Stack)
    push 0x202          ; EFLAGS (IF set)
    push 0x2B           ; CS (User Code Segment: 0x28 | 3)
    push user_entry     ; EIP (Entry point below)
    
    ; Set segment registers to User Data
    mov ax, 0x33
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; Jump!
    iret

; This code runs in Ring 3 (User Mode)
user_entry:
    mov ebx, user_msg   ; Pointer to message
    mov eax, 1          ; Syscall 1: Print
    int 0x80            ; Invoke kernel!
    
    ; We don't have an exit() syscall yet, so we just hang here
    ; HLT is privileged, so we use a simple jump to the same address
    jmp $

section .data
user_msg db "Hello from ASM Ring 3!", 10, 0
