; Proyecto Arquitectura de Computadoras 
; Estudiante: Luis Diego García Rojas

section .data
    ; Rutas de archivos 
    file_notas      db "notas.txt", 0
    file_config     db "config.ini", 0

    ; Mensajes de error 
    err_notas       db "Error: No se pudo abrir notas.txt", 10
    err_notas_len   equ $ - err_notas
    err_config      db "Error: No se pudo abrir config.ini", 10
    err_config_len  equ $ - err_config

    ; Cabeceras de salida 
    hdr_stats       db "ESTADISTICAS ", 10, 0
    hdr_hist        db "HISTOGRAMA (", 0
    hdr_hist_end    db ") ", 10, 0

    ; Etiquetas de estadisticas 
    lbl_media       db "Media: ", 0
    lbl_sep         db " | ", 0
    lbl_mediana     db "Mediana: ", 0
    lbl_moda        db "Moda: ", 0
    lbl_desv        db 10, "Desviacion Estandar: ", 0

    ; Nombres de colores para el encabezado del histograma 
    color_name_1    db "Rojo", 0
    color_name_2    db "Verde", 0
    color_name_3    db "Amarillo", 0
    color_name_4    db "Azul", 0
    color_name_x    db "Blanco", 0

    ; Codigos de escape ANSI 
    ansi_red        db 0x1b, "[31m", 0
    ansi_green      db 0x1b, "[32m", 0
    ansi_yellow     db 0x1b, "[33m", 0
    ansi_blue       db 0x1b, "[34m", 0
    ansi_reset      db 0x1b, "[0m", 0

    ; Caracteres utiles 
    char_newline    db 10
    char_colon      db ":"
    char_space      db " "
    char_dot        db "."
    char_open_paren db " ("
    char_close_paren db ")", 10

    ; Claves de config.ini (para comparar con strncmp manual) 
    key_color       db "COLOR", 0
    key_intervalo   db "INTERVALO", 0
    key_caracter    db "CARACTER", 0

    ; Prefijos de rango del histograma 
    str_dash        db "-", 0
    str_colon_nl    db ": ", 0

section .bss
    ; Buffers de lectura de archivos 
    buf_notas       resb 8192       ; Buffer para notas.txt
    buf_config      resb 512        ; Buffer para config.ini

    ; Arreglo de notas (max 100 enteros de 64 bits) 
    grades          resq 100
    grade_count     resq 1          ; N (cantidad de estudiantes)

    ; Valores estadisticos (punto flotante doble precision) 
    val_mean        resq 1
    val_median      resq 1
    val_mode        resq 1
    val_stddev      resq 1

    ; Configuracion leida de config.ini 
    cfg_color       resq 1          ; 1=Rojo, 2=Verde, 3=Amarillo, 4=Azul
    cfg_intervalo   resq 1          ; Tamanio del rango de cada barra
    cfg_caracter    resb 2          ; Caracter ASCII para dibujar la barra

    ; Arreglo de bins para el histograma (max 20 bins) 
    hist_bins       resq 20         ; Contadores por intervalo

    ; Buffer temporal de conversion de numeros a texto 
    num_buf         resb 32         ; Para print_uint / print_float

section .text
    global _start

; INICIO DEL PROGRAMA
_start:
    ; Valores por defecto de configuracion (por si config.ini falla)
    mov qword [cfg_color],     2    ; Verde por defecto
    mov qword [cfg_intervalo], 25   ; Intervalo de 25 por defecto
    mov byte  [cfg_caracter],  '#'  ; Caracter '#' por defecto

    ; Leer y parsear config.ini
    call leer_config

    ; Abrir notas.txt
    mov rax, 2                      ; syscall: open
    mov rdi, file_notas
    mov rsi, 0                      ; O_RDONLY
    xor rdx, rdx
    syscall

    cmp rax, 0
    jl .error_notas                 ; Si fd < 0, error

    mov rdi, rax                    ; Guardar file descriptor en rdi

    ; Leer notas.txt
    mov rax, 0                      ; syscall: read
    mov rsi, buf_notas
    mov rdx, 8192
    syscall
    ; rax = bytes leidos

    push rax                        ; Guardar bytes leidos

    ; Cerrar notas.txt
    mov rax, 3                      ; syscall: close
    syscall

    pop rax                         ; Recuperar bytes leidos
    cmp rax, 0
    jle .exit_clean                 ; Si leimos 0 bytes, salir

    ; Parsear las notas del buffer
    call parsear_notas

    ; Verificar que haya al menos 1 nota
    cmp qword [grade_count], 0
    je .exit_clean

    ; Calcular estadisticas
    call calcular_media
    call bubble_sort
    call calcular_mediana
    call calcular_moda
    call calcular_desviacion

    ; Imprimir resultados
    call imprimir_estadisticas
    call imprimir_histograma

.exit_clean:
    mov rax, 60                     ; syscall: exit(0)
    xor rdi, rdi
    syscall

.error_notas:
    mov rax, 1                      ; syscall: write
    mov rdi, 1                      ; stdout
    mov rsi, err_notas
    mov rdx, err_notas_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; SUBRUTINA: leer_config
; Lee config.ini y extrae COLOR, INTERVALO y CARACTER.
; Preserva: rbx, r12, r13, r14, r15
leer_config:
    push rbx
    push r12
    push r13

    ; Abrir config.ini
    mov rax, 2
    mov rdi, file_config
    mov rsi, 0
    xor rdx, rdx
    syscall

    cmp rax, 0
    jl .done                        ; Si no existe, usar valores por defecto

    mov rdi, rax

    ; Leer config.ini
    mov rax, 0
    mov rsi, buf_config
    mov rdx, 512
    syscall

    ; Cerrar config.ini
    push rax
    mov rax, 3
    syscall
    pop rax                         ; bytes leidos (no se usa mas)

    ; Parsear lineas del config
    mov rbx, buf_config             ; rbx = puntero al buffer
    xor r12, r12                    ; r12 = indice en el buffer

.parse_config_loop:
    ; Buscar inicio de linea clave
    movzx rax, byte [rbx + r12]
    test al, al
    jz .done

    ; Intentar match con "COLOR"
    lea rsi, [rbx + r12]
    mov rdi, key_color
    call strncmp5
    test rax, rax
    jz .found_color

    ; Intentar match con "INTERVALO"
    lea rsi, [rbx + r12]
    mov rdi, key_intervalo
    call strncmp9
    test rax, rax
    jz .found_intervalo

    ; Intentar match con "CARACTER"
    lea rsi, [rbx + r12]
    mov rdi, key_caracter
    call strncmp8
    test rax, rax
    jz .found_caracter

    ; Avanzar al siguiente caracter
    inc r12
    jmp .parse_config_loop

.found_color:
    add r12, 6                      ; Saltar "COLOR="
    lea rsi, [rbx + r12]
    call parse_decimal              ; Resultado en rax
    mov [cfg_color], rax
    jmp .next_line_config

.found_intervalo:
    add r12, 10                     ; Saltar "INTERVALO="
    lea rsi, [rbx + r12]
    call parse_decimal
    cmp rax, 0
    je .next_line_config            ; No permitir intervalo 0
    mov [cfg_intervalo], rax
    jmp .next_line_config

.found_caracter:
    add r12, 9                      ; Saltar "CARACTER="
    movzx rax, byte [rbx + r12]
    mov [cfg_caracter], al
    ; Continuar

.next_line_config:
    ; Avanzar hasta el proximo newline
.skip_to_nl:
    movzx rax, byte [rbx + r12]
    test al, al
    jz .done
    cmp al, 10
    je .after_nl
    inc r12
    jmp .skip_to_nl
.after_nl:
    inc r12
    jmp .parse_config_loop

.done:
    pop r13
    pop r12
    pop rbx
    ret

; SUBRUTINA: parsear_notas
; Recorre buf_notas y extrae la ultima secuencia numerica de cada linea.
; La ultima secuencia numerica en cada linea ES la nota.
; Resultado: grades[] lleno, grade_count actualizado.
parsear_notas:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, buf_notas
    xor r12, r12                    ; r12 = indice en buffer
    xor r13, r13                    ; r13 = grade_count
    xor r14, r14                    ; r14 = ultimo numero acumulado en la linea
    xor r15, r15                    ; r15 = flag: 1 si estamos en secuencia numerica

.loop:
    movzx rax, byte [rbx + r12]
    test al, al
    jz .end_of_file

    cmp al, 10                      ; newline
    je .end_of_line
    cmp al, 13                      ; carriage return (ignorar)
    je .skip_char

    ; ¿Es digito?
    cmp al, '0'
    jl .not_digit
    cmp al, '9'
    jg .not_digit

    ; Es digito: acumular
    sub al, '0'
    movzx rax, al
    imul r14, r14, 10
    add r14, rax
    mov r15, 1                      ; Estamos en numero
    jmp .skip_char

.not_digit:
    ; Si veniamos en un numero, lo terminamos (pero NO guardamos aun,
    ; guardamos el ULTIMO numero de la linea en el newline)
    ; Solo reseteamos el flag si hay espacio (separador)
    cmp al, ' '
    je .space_found
    ; Cualquier otro caracter (letra) resetea la acumulacion
    mov r15, 0
    xor r14, r14
    jmp .skip_char

.space_found:
    ; Si habia un numero antes del espacio, ese podria ser la nota
    ; pero esperamos al final de linea para confirmar
    ; (El ultimo numero acumulado antes del newline es la nota)
    mov r15, 0
    ; r14 guarda el ultimo valor numerico completo visto
    ; pero necesitamos guardarlo temporalmente
    ; La logica correcta: guardar el numero cuando encontramos espacio
    ; y al final de linea usar ese valor guardado
    jmp .skip_char

.end_of_line:
    ; Al final de la linea, si r15=1 significa que la linea termina
    ; directo en digitos. Si r15=0 y r14>0, r14 tiene el ultimo numero.
    ; En ambos casos, r14 es la nota de esta linea.
    cmp r14, 0
    je .reset_line                  ; Linea vacia o sin numeros, ignorar
    cmp r14, 100
    jg .reset_line                  ; Nota invalida (>100), ignorar

    mov [grades + r13 * 8], r14
    inc r13

.reset_line:
    xor r14, r14
    mov r15, 0
    jmp .skip_char

.skip_char:
    inc r12
    jmp .loop

.end_of_file:
    ; Manejar ultima linea si no terminaba en newline
    cmp r14, 0
    je .done_parse
    cmp r14, 100
    jg .done_parse
    mov [grades + r13 * 8], r14
    inc r13

.done_parse:
    mov [grade_count], r13
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; SUBRUTINA: calcular_media
; Suma todas las notas y divide entre N.
; Resultado: val_mean (double)
calcular_media:
    push rbx
    push rcx

    mov rcx, [grade_count]
    mov rbx, grades
    xor r11, r11
    xorpd xmm0, xmm0               ; Acumulador de suma

.sum_loop:
    cmp r11, rcx
    jge .done
    cvtsi2sd xmm1, qword [rbx + r11 * 8]
    addsd xmm0, xmm1
    inc r11
    jmp .sum_loop

.done:
    cvtsi2sd xmm1, rcx
    divsd xmm0, xmm1
    movsd [val_mean], xmm0

    pop rcx
    pop rbx
    ret

; SUBRUTINA: bubble_sort
; Ordena grades[] de menor a mayor (para mediana y moda).
bubble_sort:
    push rbx
    push r12
    push r13
    push r14

    mov r14, [grade_count]
    cmp r14, 1
    jle .done

    mov r12, r14
    dec r12                         ; Pasadas = N-1

.outer:
    cmp r12, 0
    jle .done
    xor r13, r13                    ; Indice inner

.inner:
    lea rbx, [r13 + 1]
    cmp rbx, r12
    jg .end_inner

    mov rax, [grades + r13 * 8]
    mov rdx, [grades + r13 * 8 + 8]
    cmp rax, rdx
    jle .no_swap

    mov [grades + r13 * 8], rdx
    mov [grades + r13 * 8 + 8], rax

.no_swap:
    inc r13
    jmp .inner

.end_inner:
    dec r12
    jmp .outer

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; SUBRUTINA: calcular_mediana
; Asume que grades[] ya esta ordenado.
; Resultado: val_median (double)
calcular_mediana:
    push rbx

    mov rbx, [grade_count]
    mov rax, rbx
    test rax, 1
    jz .even

    ; N impar: elemento central
    shr rax, 1
    cvtsi2sd xmm0, qword [grades + rax * 8]
    jmp .store

.even:
    ; N par: promedio de los dos centrales
    shr rax, 1
    cvtsi2sd xmm0, qword [grades + rax * 8]
    lea rcx, [rax - 1]
    cvtsi2sd xmm1, qword [grades + rcx * 8]
    addsd xmm0, xmm1
    mov rax, 2
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1

.store:
    movsd [val_median], xmm0

    pop rbx
    ret

; SUBRUTINA: calcular_moda
; Recorre el arreglo ordenado y encuentra el valor con mayor frecuencia.
; Resultado: val_mode (double)
calcular_moda:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, [grade_count]
    cmp rbx, 0
    je .done

    mov rax, [grades]               ; Valor actual
    mov r10, 1                      ; Contador actual
    mov r12, rax                    ; Mejor moda hasta ahora
    mov r13, 1                      ; Mejor frecuencia
    mov rcx, 1                      ; Indice

.loop:
    cmp rcx, rbx
    jge .check_last

    mov rdx, [grades + rcx * 8]
    cmp rdx, rax
    je .same_val

    ; Valor diferente: comparar frecuencia
    cmp r10, r13
    jle .reset_counter
    mov r13, r10
    mov r12, rax

.reset_counter:
    mov rax, rdx
    mov r10, 1
    jmp .next

.same_val:
    inc r10

.next:
    inc rcx
    jmp .loop

.check_last:
    cmp r10, r13
    jle .store_mode
    mov r12, rax

.store_mode:
    cvtsi2sd xmm0, r12
    movsd [val_mode], xmm0

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; SUBRUTINA: calcular_desviacion
; Calcula la desviacion estandar usando XMM/SSE.
; Resultado: val_stddev (double)
calcular_desviacion:
    push rbx

    mov rbx, [grade_count]
    movsd xmm4, [val_mean]          ; xmm4 = media
    xorpd xmm2, xmm2               ; xmm2 = suma de (x - media)^2
    xor r11, r11

.loop:
    cmp r11, rbx
    jge .calc_sqrt

    cvtsi2sd xmm3, qword [grades + r11 * 8]
    subsd xmm3, xmm4                ; xmm3 = x - media
    mulsd xmm3, xmm3                ; xmm3 = (x - media)^2
    addsd xmm2, xmm3
    inc r11
    jmp .loop

.calc_sqrt:
    cvtsi2sd xmm1, rbx
    divsd xmm2, xmm1               ; Varianza = suma / N
    sqrtsd xmm2, xmm2              ; Desv = sqrt(varianza)
    movsd [val_stddev], xmm2

    pop rbx
    ret

; SUBRUTINA: imprimir_estadisticas
; Imprime: " ESTADISTICAS " y los valores calculados.
imprimir_estadisticas:
    push rbx

    ; Encabezado
    mov rsi, hdr_stats
    call print_str

    ; "Media: X.XX | Mediana: X.XX | Moda: X.XX"
    mov rsi, lbl_media
    call print_str
    movsd xmm0, [val_mean]
    call print_float_2dec

    mov rsi, lbl_sep
    call print_str

    mov rsi, lbl_mediana
    call print_str
    movsd xmm0, [val_median]
    call print_float_2dec

    mov rsi, lbl_sep
    call print_str

    mov rsi, lbl_moda
    call print_str
    movsd xmm0, [val_mode]
    call print_float_2dec

    ; Salto de linea + "Desviacion Estandar: X.XX"
    mov rsi, lbl_desv
    call print_str
    movsd xmm0, [val_stddev]
    call print_float_2dec

    ; Dos saltos de linea
    mov rax, 1
    mov rdi, 1
    mov rsi, char_newline
    mov rdx, 1
    syscall

    pop rbx
    ret

; SUBRUTINA: imprimir_histograma
; Genera el histograma dinamico segun cfg_intervalo y cfg_color.
imprimir_histograma:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Aplicar color ANSI segun configuracion 
    mov rax, [cfg_color]
    cmp rax, 1
    je .color_red
    cmp rax, 2
    je .color_green
    cmp rax, 3
    je .color_yellow
    cmp rax, 4
    je .color_blue
    jmp .color_default

.color_red:
    mov rsi, ansi_red
    call print_str
    mov rsi, color_name_1
    jmp .print_header

.color_green:
    mov rsi, ansi_green
    call print_str
    mov rsi, color_name_2
    jmp .print_header

.color_yellow:
    mov rsi, ansi_yellow
    call print_str
    mov rsi, color_name_3
    jmp .print_header

.color_blue:
    mov rsi, ansi_blue
    call print_str
    mov rsi, color_name_4
    jmp .print_header

.color_default:
    mov rsi, color_name_x

.print_header:
    push rsi                        ; Guardar puntero al nombre del color

    ; Imprimir " HISTOGRAMA ("
    mov rsi, hdr_hist
    call print_str

    ; Imprimir nombre del color
    pop rsi
    call print_str

    ; Imprimir ") \n"
    mov rsi, hdr_hist_end
    call print_str

    ; Limpiar arreglo de bins 
    xor rcx, rcx
.clear_bins:
    cmp rcx, 20
    jge .bins_cleared
    mov qword [hist_bins + rcx * 8], 0
    inc rcx
    jmp .clear_bins
.bins_cleared:

    ; Clasificar cada nota en su bin 
    mov r14, [grade_count]
    mov r15, [cfg_intervalo]
    xor r12, r12

.classify_loop:
    cmp r12, r14
    jge .draw_hist

    mov rax, [grades + r12 * 8]
    xor rdx, rdx
    div r15                         ; rax = bin index = nota / intervalo
    cmp rax, 19
    jle .valid_bin
    mov rax, 19                     ; Clamp al ultimo bin
.valid_bin:
    inc qword [hist_bins + rax * 8]
    inc r12
    jmp .classify_loop

.draw_hist:
    ; Imprimir cada bin con rango y barras 
    ; Calcular cuantos bins necesitamos: ceil(101 / intervalo)
    mov rax, 100
    xor rdx, rdx
    div r15
    ; rax = 100 / intervalo, rdx = resto
    test rdx, rdx
    jz .no_extra_bin
    inc rax
.no_extra_bin:
    ; Limitar a 20 bins
    cmp rax, 20
    jle .bins_ok
    mov rax, 20
.bins_ok:
    mov r13, rax                    ; r13 = numero total de bins a imprimir
    xor r12, r12                    ; r12 = bin actual

.bin_loop:
    cmp r12, r13
    jge .hist_done

    ; Calcular rango_inicio = r12 * intervalo
    mov rax, r12
    mul r15
    mov rbx, rax                    ; rbx = rango_inicio

    ; Calcular rango_fin = rango_inicio + intervalo - 1
    mov rcx, rbx
    add rcx, r15
    dec rcx                         ; rcx = rango_fin

    ; Imprimir "XX-YY: "
    mov rax, rbx
    call print_uint_inline          ; Imprime rango_inicio

    mov rax, 1
    mov rdi, 1
    mov rsi, str_dash
    mov rdx, 1
    syscall

    mov rax, rcx
    call print_uint_inline          ; Imprime rango_fin

    mov rax, 1
    mov rdi, 1
    mov rsi, str_colon_nl
    mov rdx, 2
    syscall

    ; Imprimir barras (caracter repetido segun conteo del bin)
    mov r10, [hist_bins + r12 * 8]  ; r10 = conteo
    test r10, r10
    jz .print_count_zero            ; Si 0, saltar directamente al newline

    xor r11, r11
.bar_loop:
    cmp r11, r10
    jge .after_bars

    ; Imprimir cfg_caracter una vez
    mov rax, 1
    mov rdi, 1
    mov rsi, cfg_caracter
    mov rdx, 1
    syscall

    inc r11
    jmp .bar_loop

.after_bars:
    ; Imprimir " (N)\n"
    mov rax, 1
    mov rdi, 1
    mov rsi, char_open_paren
    mov rdx, 2
    syscall

    mov rax, r10
    call print_uint_inline

    mov rax, 1
    mov rdi, 1
    mov rsi, char_close_paren
    mov rdx, 2
    syscall

    jmp .next_bin

.print_count_zero:
    ; Solo imprimir newline
    mov rax, 1
    mov rdi, 1
    mov rsi, char_newline
    mov rdx, 1
    syscall

.next_bin:
    inc r12
    jmp .bin_loop

.hist_done:
    ; Reset color ANSI
    mov rsi, ansi_reset
    call print_str

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; SUBRUTINA: print_str
; Imprime cadena terminada en 0 apuntada por rsi.
; Modifica: rax, rdx (los restaura via push/pop no requerido - es caller-saved)
print_str:
    push rsi
    push rdx

    xor rdx, rdx
.find_len:
    cmp byte [rsi + rdx], 0
    je .do_write
    inc rdx
    jmp .find_len
.do_write:
    test rdx, rdx
    jz .done_str
    mov rax, 1
    mov rdi, 1
    syscall
.done_str:
    pop rdx
    pop rsi
    ret

; SUBRUTINA: print_uint_inline
; Imprime el entero sin signo en rax a stdout.
; Usa num_buf como buffer temporal.
; Preserva todos los registros excepto rax.
print_uint_inline:
    push rbx
    push rcx
    push rdx
    push rsi

    ; Caso especial: rax = 0
    test rax, rax
    jnz .convert

    mov byte [num_buf], '0'
    mov rax, 1
    mov rdi, 1
    mov rsi, num_buf
    mov rdx, 1
    syscall
    jmp .done_uint

.convert:
    mov rbx, 10
    xor rcx, rcx
    lea rsi, [num_buf + 20]         ; Apuntar al FINAL del buffer

.div_loop:
    test rax, rax
    jz .print_uint_str

    xor rdx, rdx
    div rbx                         ; rax = cociente, rdx = digito
    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc rcx
    jmp .div_loop

.print_uint_str:
    mov rax, 1
    mov rdi, 1
    mov rdx, rcx
    syscall

.done_uint:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; SUBRUTINA: print_float_2dec
; Imprime xmm0 con exactamente 2 decimales (ej: "75.50").
print_float_2dec:
    push rax
    push rbx
    push rcx

    ; Imprimir parte entera
    cvttsd2si rax, xmm0
    ; Manejar negativos (desviacion siempre >= 0, pero por seguridad)
    test rax, rax
    jns .pos_int
    neg rax
.pos_int:
    call print_uint_inline

    ; Imprimir punto decimal
    mov rax, 1
    mov rdi, 1
    mov rsi, char_dot
    mov rdx, 1
    syscall

    ; Calcular decimales: (xmm0 - parte_entera) * 100
    cvttsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1                ; xmm0 = fraccion
    ; Asegurar que la fraccion sea positiva
    xorpd xmm3, xmm3
    ucomisd xmm0, xmm3
    jae .frac_pos
    ; Negar fraccion si negativa
    mov rax, 1
    cvtsi2sd xmm3, rax
    subsd xmm3, xmm3
    ; simple fix: usar abs value
    pxor xmm4, xmm4
    subsd xmm4, xmm0
    movsd xmm0, xmm4
.frac_pos:
    mov rax, 100
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    cvttsd2si rax, xmm0             ; rax = decimales (0-99)

    ; Imprimir con cero adelante si < 10
    cmp rax, 10
    jge .no_leading_zero
    push rax
    mov byte [num_buf], '0'
    mov rax, 1
    mov rdi, 1
    mov rsi, num_buf
    mov rdx, 1
    syscall
    pop rax
.no_leading_zero:
    call print_uint_inline

    pop rcx
    pop rbx
    pop rax
    ret

; SUBRUTINA: parse_decimal
; Lee entero decimal de cadena apuntada por rsi.
; Resultado en rax.
parse_decimal:
    xor rax, rax
    xor rcx, rcx
.loop:
    movzx rcx, byte [rsi]
    cmp cl, '0'
    jl .done_parse
    cmp cl, '9'
    jg .done_parse
    sub cl, '0'
    imul rax, rax, 10
    movzx rcx, cl
    add rax, rcx
    inc rsi
    jmp .loop
.done_parse:
    ret

; SUBRUTINAS: strncmp5, strncmp8, strncmp9
; Compara los primeros N bytes de [rsi] con la cadena literal [rdi].
; Retorna rax=0 si son iguales, rax=1 si no.
strncmp5:                           ; Compara 5 bytes ("COLOR")
    push rbx
    xor rbx, rbx
.loop5:
    cmp rbx, 5
    jge .eq5
    movzx rax, byte [rsi + rbx]
    movzx rcx, byte [rdi + rbx]
    cmp al, cl
    jne .neq5
    inc rbx
    jmp .loop5
.eq5:
    xor rax, rax
    pop rbx
    ret
.neq5:
    mov rax, 1
    pop rbx
    ret

strncmp8:                           ; Compara 8 bytes ("CARACTER")
    push rbx
    xor rbx, rbx
.loop8:
    cmp rbx, 8
    jge .eq8
    movzx rax, byte [rsi + rbx]
    movzx rcx, byte [rdi + rbx]
    cmp al, cl
    jne .neq8
    inc rbx
    jmp .loop8
.eq8:
    xor rax, rax
    pop rbx
    ret
.neq8:
    mov rax, 1
    pop rbx
    ret

strncmp9:                           ; Compara 9 bytes ("INTERVALO")
    push rbx
    xor rbx, rbx
.loop9:
    cmp rbx, 9
    jge .eq9
    movzx rax, byte [rsi + rbx]
    movzx rcx, byte [rdi + rbx]
    cmp al, cl
    jne .neq9
    inc rbx
    jmp .loop9
.eq9:
    xor rax, rax
    pop rbx
    ret
.neq9:
    mov rax, 1
    pop rbx
    ret
