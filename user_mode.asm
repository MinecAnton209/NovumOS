; User Mode Logic and Transition
[bits 32]

global jump_to_ring3_entry
extern handle_syscall_zig

section .text

; Function called from Zig: jump_to_ring3_entry(entry_address, stack_address)
; Function called from Zig: jump_to_ring1_entry(entry_address, stack_address)
jump_to_ring3_entry:
    cli
    mov ebp, [esp + 4]   ; Get entry point address
    mov ecx, [esp + 8]   ; Get stack address
    
    ; Setup IRET frame
    push 0xAB           ; SS
    push ecx            ; ESP
    push 0x202          ; EFLAGS (IF=1)
    push 0xA3           ; CS
    push ebp            ; EIP
    
    ; 1. Zero out segment registers for Ring 3
    mov ax, 0xAB
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; 2. Zero out SSE registers to prevent information leak
    pxor xmm0, xmm0
    pxor xmm1, xmm1
    pxor xmm2, xmm2
    pxor xmm3, xmm3
    pxor xmm4, xmm4
    pxor xmm5, xmm5
    pxor xmm6, xmm6
    pxor xmm7, xmm7

    ; 3. Zero out all GPRs (Sanitization)
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx
    xor esi, esi
    xor edi, edi
    xor ebp, ebp

    ; All set. Jump to Ring 3!
    iret
