#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; debug_print_string - print the string pointed to by hl
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_print_string:

	ld	a, (hl)
	or	a		; set flags
	jr	Z, debug_printf_done

	ld	b, a

	push	hl
	call	uart_transmit
	pop	hl
	inc	hl

	jr	debug_print_string

debug_printf_done:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; debug_print_hex_nibble - print the hex value of the lower 4 bits in register B
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_print_hex_nibble:

	ld	a, b
	and	a, 0xf

	; Is it >= 0xa
	cp	0xa
	jp	P, debug_print_hex_nibble_ge

	add	a, '0'
	jr	debug_print_hex_nibble_ready

debug_print_hex_nibble_ge:
	add	a, 'A' - 0xa

debug_print_hex_nibble_ready:
	ld	b, a
	call	uart_transmit

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; debug_print_hex - print the hex value in register B
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_print_hex:

	ld	a, b
	ld	c, b

	; Get high nibble
	rr	a
	rr	a
	rr	a
	rr	a
	ld	b, a
	call	debug_print_hex_nibble

	; Get low nibble
	ld	b, c
	call	debug_print_hex_nibble

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; debug_print_eol - print CR-LF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_print_eol:
	ld	b, 0x0d
	call	uart_transmit

	ld	b, 0x0a
	call	uart_transmit

	ret



#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; debug_show_a - Show contents of a
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_show_a:
	push	hl
	push	de
	push	bc
	push	af
 
	ld	hl, s_a
	call	debug_print_string
	pop	af
	push	af
	ld	b, a
	call	debug_print_hex
	call	debug_print_eol
 
	pop	af
	pop	bc
	pop	de
	pop	hl

	ret

s_a: .asciz "a: "

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; debug_show_bc - Show contents of bc
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_show_bc:
	push	de
	push	af
	push	hl
	push	bc

	ld	hl, s_bc
	call	debug_print_string
	pop	bc
	push	bc
	; ld	b, b
	call	debug_print_hex
	pop	bc
	push	bc
	ld	b, c
	call	debug_print_hex
	call	debug_print_eol

	pop	bc
	pop	hl
	pop	af
	pop	de

	ret

s_bc: .asciz "bc: "

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; debug_show_de - Show contents of de
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_show_de:
	push	af
	push	hl
	push	bc
	push	de

	ld	hl, s_de
	call	debug_print_string
	pop	de
	push	de
	ld	b, d
	call	debug_print_hex
	pop	de
	push	de
	ld	b, e
	call	debug_print_hex
	call	debug_print_eol

	pop	de
	pop	bc
	pop	hl
	pop	af

	ret

s_de: .asciz "de: "

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; debug_show_hl - Show contents of hl
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_show_hl:
	push	de
	push	bc
	push	af
	push	hl

	ld	hl, s_hl
	call	debug_print_string
	pop	hl
	push	hl
	ld	b, h
	call	debug_print_hex
	pop	hl
	push	hl
	ld	b, l
	call	debug_print_hex
	call	debug_print_eol

	pop	hl
	pop	af
	pop	bc
	pop	de

	ret

s_hl: .asciz "hl: "
