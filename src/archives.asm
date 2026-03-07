section .data
   ; Initialized Variables
   file_name db "notas.txt", 0                      ;0 is Null-terminated file name 
   error_msg db "Error. Cannot open notas.txt ", 10 ;10 is newline \n
   error_len equ $ - error_msg                      ;Auto-calculate the lenght of the error messagge

section .bss
   ; Reserve a Memory block
   read_buffer resb 4096 ;Reserve 4KB memory for a notes file

section .text
   global _start         ;Entry point to the linker (ld)


_start:
   ; OPEN THE FILE
   mov rax, 2		    ; 2 is 'open' syscall
   mov rdi, file_name       ; RDI: Pointer to "notas.txt"
   mov rsi, 0               ; RSI: Flags (0 = read only) 	 
   mov rdx, 0               ; RDX: Mode (0, we are not creating a file)
   syscall                  ; Transfer control to the Linux Kernel

    ; ERROR HANDLING 
    cmp rax, 0                       ; The kernel returns the File Descriptor in RAX
    jl open_error                    ; Jump if Less (If RAX < 0, the file doesn't exist)

    ; READ THE FILE     
    mov rdi, rax                     ; Move the valid File Descriptor from RAX to RDI
    mov rax, 0                       ; Syscall 0 is 'read'
    mov rsi, read_buffer             ; RSI: Pointer to our empty 4KB memory block
    mov rdx, 4096                    ; RDX: Maximum number of bytes to read
    syscall

    ; CLOSE THE FILE (Syscall: sys_close)
    mov rax, 3                       ; Syscall 3 is 'close'
    syscall

    ; Went perfectly.
    jmp clean_exit

    ; ERROR ROUTINE
open_error:
    mov rax, 1                       ; Syscall 1 is 'write'
    mov rdi, 1                       ; RDI: 1 is standard output (the terminal)
    mov rsi, error_msg                 ; RSI: Pointer to our error string
    mov rdx, error_len                 ; RDX: The auto-calculated length
    syscall
    
    mov rax, 60                      ; Syscall 60 is 'exit'
    mov rdi, 1                       ; RDI: Exit code 1 (Indicates a failure)
    syscall

    ; EXIT ROUTINE
clean_exit:
    mov rax, 60                      ; Syscall 60 is 'exit'
    mov rdi, 0                       ; RDI: Exit code 0 (Indicates success)
    syscall
