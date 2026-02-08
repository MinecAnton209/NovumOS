; User Mode Logic and Transition
[bits 32]

global jump_to_ring3_entry
extern handle_syscall_zig

section .text

; Function called from Zig: jump_to_ring3_entry(entry_address)
jump_to_ring3_entry:
    cli
    mov ebp, [esp + 4]   ; Get entry point address from argument
    
    ; Prepare stack for IRET:
    ; [ESP + 16] SS
    ; [ESP + 12] ESP
    ; [ESP + 8]  EFLAGS
    ; [ESP + 4]  CS
    ; [ESP + 0]  EIP
    
    push 0x33           ; SS (User Data Segment: 0x30 | 3)
    push 0x3FFFF0       ; ESP (User Stack - 16-byte aligned)
    push 0x202          ; EFLAGS (IF set)
    push 0x2B           ; CS (User Code Segment: 0x28 | 3)
    push ebp            ; EIP (Entry point passed as argument)
    
    ; Set segment registers to User Data
    mov ax, 0x33
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    ; Jump!
    iret

; Original test entry point (just in case)
global jump_to_ring3
jump_to_ring3:
    push user_test_entry
    call jump_to_ring3_entry
    ret

user_test_entry:
    mov ebx, user_msg   ; Pointer to message
.loop:
    mov eax, 1          ; Syscall 1: Print
    int 0x80            ; Invoke kernel!
    
    ; Simple delay loop
    mov ecx, 0x1000000
.delay:
    nop
    loop .delay
    
    jmp .loop

section .data
user_msg db "Hello from ASM Ring 3 via syscall!", 10, 0
