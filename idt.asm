; IDT (Interrupt Descriptor Table) Management
; Sets up the CPU interrupt table, PIC remap, and basic ISR wrappers.

[bits 32]

global idt_init
global enable_interrupts
global disable_interrupts
global test_divide_by_zero
global double_fault_handler_task

; External Zig ISR handlers
extern isr_keyboard
extern isr_timer
extern handle_exception
extern handle_double_fault
extern handle_syscall_zig

section .data
align 16
; Space for 256 gates (8 bytes each)
idt_start:
    times 256 * 8 db 0
idt_end:

section .text
align 4
; IDT Pointer for LIDT instruction
idt_descriptor:
    dw idt_end - idt_start - 1
    dd idt_start

; Initialize the IDT and configure PIC
idt_init:
    pusha
    
    ; 1. Set exception handlers (0-31)
    %assign i 0
    %rep 32
        %if i != 8
            mov eax, exception_handler_%+i
            mov ebx, i
            call idt_set_gate
        %endif
        %assign i i+1
    %endrep

    ; 2. Set Task Gate for Double Fault (Vector 8)
    ; Selector 0x20 is DF TSS (defined in kernel32.asm GDT)
    mov eax, 0x20
    mov ebx, 8
    call idt_set_task_gate

    ; 3. Remap the PIC (offset IRQs to 0x20+)
    call remap_pic
        
    ; 4. Mask all interrupts except Keyboard
    mov al, 0xff
    out 0x21, al
    out 0xa1, al

    ; 5. Set Timer ISR (IRQ0 -> 0x20)
    mov eax, isr_timer_wrapper
    mov ebx, 0x20
    call idt_set_gate

    ; 6. Set Keyboard ISR (IRQ1 -> 0x21)
    mov eax, isr_keyboard_wrapper
    mov ebx, 0x21
    call idt_set_gate

    ; 7. Set Syscall Gate (0x80) with DPL 3
    mov eax, syscall_handler
    mov ebx, 0x80
    call idt_set_syscall_gate
    
    ; 7. Load IDT into CPU
    lidt [idt_descriptor]

    ; Flush keyboard buffer
    in al, 0x60
    
    ; 8. Unmask IRQ0 (Timer) and IRQ1 (Keyboard)
    in al, 0x21
    and al, 0xfc        ; 11111100b - Unmask IRQ0 and IRQ1
    out 0x21, al

    popa
    ret

; Helper: Set a single IDT gate
; EAX: offset of handler, EBX: gate index
idt_set_gate:
    push edi
    
    mov edi, idt_start
    shl ebx, 3          ; index * 8
    add edi, ebx
    
    mov [edi], ax       ; Offset low 16 bits
    mov word [edi + 2], 0x08 ; Selector (Kernel Code)
    mov byte [edi + 4], 0    ; Reserved
    mov byte [edi + 5], 0x8E ; IDT attributes (Present, 32bit Interrupt Gate)
    shr eax, 16
    mov [edi + 6], ax   ; Offset high 16 bits
    
    pop edi
    ret

; Helper: Set a Task Gate
; EAX: TSS selector, EBX: gate index
idt_set_task_gate:
    push edi

    mov edi, idt_start
    shl ebx, 3
    add edi, ebx

    mov word [edi], 0       ; Offset ignored
    mov word [edi + 2], ax  ; TSS Selector
    mov byte [edi + 4], 0   ; Reserved
    mov byte [edi + 5], 0x85 ; Task Gate (Present, DPL 0, Type 5)
    mov word [edi + 6], 0   ; Offset ignored

    pop edi
    ret

; Helper: Set a Syscall Gate (DPL 3)
; EAX: offset of handler, EBX: gate index
idt_set_syscall_gate:
    push edi
    
    mov edi, idt_start
    shl ebx, 3          ; index * 8
    add edi, ebx
    
    mov [edi], ax       ; Offset low 16 bits
    mov word [edi + 2], 0x08 ; Selector (Kernel Code)
    mov byte [edi + 4], 0    ; Reserved
    mov byte [edi + 5], 0xEE ; IDT attributes (Present, DPL 3, 32bit Interrupt Gate)
    shr eax, 16
    mov [edi + 6], ax   ; Offset high 16 bits
    
    pop edi
    ret

; Common exception handler
common_exception_handler:
    push gs                 ; Save segment registers
    push fs
    push es
    push ds
    pushad
    
    ; Ensure segment registers are set to kernel data
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    cld
    
    push esp                ; Pass pointer to ExceptionFrame
    call handle_exception   ; Should not return
    
    pop esp
    popad
    add esp, 16             ; Clean up segments (4 * 4 bytes)
    add esp, 8              ; Clean up vector and error code
    iret

; Task-based Double Fault Handler
; This is the EIP for the DF TSS
double_fault_handler_task:
    ; No need to pushad, we are in a fresh task
    ; But we want to call Zig's handle_double_fault
    call handle_double_fault
    hlt
    jmp $

; Macros for exception wrappers
%macro EXCEPTION_NOERR 1
exception_handler_%1:
    push dword 0            ; Dummy error code
    push dword %1           ; Vector number
    jmp common_exception_handler
%endmacro

%macro EXCEPTION_ERR 1
exception_handler_%1:
    push dword %1           ; Vector number
    jmp common_exception_handler
%endmacro

; Generate wrappers
EXCEPTION_NOERR 0
EXCEPTION_NOERR 1
EXCEPTION_NOERR 2
EXCEPTION_NOERR 3
EXCEPTION_NOERR 4
EXCEPTION_NOERR 5
EXCEPTION_NOERR 6
EXCEPTION_NOERR 7
; Vector 8 is handled by Task Gate
EXCEPTION_NOERR 9
EXCEPTION_ERR 10
EXCEPTION_ERR 11
EXCEPTION_ERR 12
EXCEPTION_ERR 13
EXCEPTION_ERR 14
EXCEPTION_NOERR 15
EXCEPTION_NOERR 16
EXCEPTION_ERR 17
EXCEPTION_NOERR 18
EXCEPTION_NOERR 19
EXCEPTION_NOERR 20
EXCEPTION_NOERR 21
EXCEPTION_NOERR 22
EXCEPTION_NOERR 23
EXCEPTION_NOERR 24
EXCEPTION_NOERR 25
EXCEPTION_NOERR 26
EXCEPTION_NOERR 27
EXCEPTION_NOERR 28
EXCEPTION_NOERR 29
EXCEPTION_NOERR 30
EXCEPTION_NOERR 31

; --- IRQ Wrappers ---

; ISR Wrapper: Keyboard (IRQ1)
isr_keyboard_wrapper:
    pushad
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    cld
    call isr_keyboard
    mov al, 0x20
    out 0x20, al
    popad
    iret

; ISR Wrapper: Timer (IRQ0)
isr_timer_wrapper:
    pushad
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    cld
    call isr_timer
    mov al, 0x20
    out 0x20, al
    popad
    iret

; Syscall Handler
syscall_handler:
    push gs                 ; Save segment registers
    push fs
    push es
    push ds
    pushad
    
    ; Set kernel data segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    
    push esp                ; Pass pointer to Registers struct
    call handle_syscall_zig
    add esp, 4
    
    popad
    pop ds                  ; Restore segment registers
    pop es
    pop fs
    pop gs
    iretd

; Test function to trigger division by zero exception
test_divide_by_zero:
    push ebp
    mov ebp, esp
    xor edx, edx
    xor eax, eax
    mov ecx, 0
    div ecx
    mov esp, ebp
    pop ebp
    ret

; Remap the Programmable Interrupt Controller
remap_pic:
    push eax
    mov al, 0x11
    out 0x20, al
    call io_wait
    out 0xA0, al
    call io_wait
    mov al, 0x20
    out 0x21, al
    call io_wait
    mov al, 0x28
    out 0xA1, al
    call io_wait
    mov al, 0x04
    out 0x21, al
    call io_wait
    mov al, 0x02
    out 0xA1, al
    call io_wait
    mov al, 0x01
    out 0x21, al
    call io_wait
    out 0xA1, al
    call io_wait
    pop eax
    ret

io_wait:
    out 0x80, al
    ret

enable_interrupts:
    sti
    ret

disable_interrupts:
    cli
    ret
