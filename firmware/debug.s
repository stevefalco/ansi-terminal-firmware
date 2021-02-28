#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; show_a - Show contents of a
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_a:
	push	hl
	push	de
	push	bc
	push	af
 
	ld	hl, s_a
	call	uart_printf
	pop	af
	push	af
	ld	b, a
	call	uart_print_hex
	call	uart_print_eol
 
	pop	af
	pop	bc
	pop	de
	pop	hl

	ret

s_a: .asciz "a: "

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; show_bc - Show contents of bc
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_bc:
	push	de
	push	af
	push	hl
	push	bc

	ld	hl, s_bc
	call	uart_printf
	pop	bc
	push	bc
	; ld	b, b
	call	uart_print_hex
	pop	bc
	push	bc
	ld	b, c
	call	uart_print_hex
	call	uart_print_eol

	pop	bc
	pop	hl
	pop	af
	pop	de

	ret

s_bc: .asciz "bc: "

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; show_de - Show contents of de
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_de:
	push	af
	push	hl
	push	bc
	push	de

	ld	hl, s_de
	call	uart_printf
	pop	de
	push	de
	ld	b, d
	call	uart_print_hex
	pop	de
	push	de
	ld	b, e
	call	uart_print_hex
	call	uart_print_eol

	pop	de
	pop	bc
	pop	hl
	pop	af

	ret

s_de: .asciz "de: "

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; show_hl - Show contents of hl
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_hl:
	push	de
	push	bc
	push	af
	push	hl

	ld	hl, s_hl
	call	uart_printf
	pop	hl
	push	hl
	ld	b, h
	call	uart_print_hex
	pop	hl
	push	hl
	ld	b, l
	call	uart_print_hex
	call	uart_print_eol

	pop	hl
	pop	af
	pop	bc
	pop	de

	ret

s_hl: .asciz "hl: "
