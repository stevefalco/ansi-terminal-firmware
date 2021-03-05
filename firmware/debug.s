#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; debug_print_string - print the string pointed to by HL
;
; Input HL
; Alters none
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_print_string:

	push	af
	push	bc
	push	de
	push	hl

debug_print_string_again:

	ld	a, (hl)
	or	a		; set flags
	jr	Z, debug_printf_done

	ld	c, a

	push	hl
	call	uart_transmit
	pop	hl
	inc	hl

	jr	debug_print_string_again

debug_printf_done:

	pop	hl
	pop	de
	pop	bc
	pop	af

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; debug_print_hex_nibble - print the hex value of the lower 4 bits in register C
;
; Input C
; Alters none
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_print_hex_nibble:

	push	af
	push	bc
	push	de
	push	hl

	ld	a, c
	and	a, 0xf

	; Is it >= 0xa
	cp	0xa
	jp	P, debug_print_hex_nibble_ge

	add	a, '0'
	jr	debug_print_hex_nibble_ready

debug_print_hex_nibble_ge:
	add	a, 'A' - 0xa

debug_print_hex_nibble_ready:
	ld	c, a
	call	uart_transmit

	pop	hl
	pop	de
	pop	bc
	pop	af

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; debug_print_hex - print the hex value in register C
;
; Input C
; Alters none
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_print_hex:

	push	af
	push	bc
	push	de
	push	hl

	ld	a, c
	ld	b, c

	; Get high nibble
	rr	a
	rr	a
	rr	a
	rr	a
	ld	c, a
	call	debug_print_hex_nibble

	; Get low nibble
	ld	c, b
	call	debug_print_hex_nibble

	pop	hl
	pop	de
	pop	bc
	pop	af

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; debug_print_eol - print CR-LF
;
; Input none
; Alters none
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_print_eol:

	push	af
	push	bc
	push	de
	push	hl

	ld	c, 0x0d
	call	uart_transmit

	ld	c, 0x0a
	call	uart_transmit

	pop	hl
	pop	de
	pop	bc
	pop	af

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; debug_show_a - Show contents of a
;
; Input none
; Alters none
; Output none
;
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
	ld	c, a
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
;
; debug_show_bc - Show contents of bc
;
; Input none
; Alters none
; Output none
;
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
	ld	c, b
	call	debug_print_hex
	pop	bc
	push	bc
	; ld	c, c
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
;
; debug_show_de - Show contents of de
;
; Input none
; Alters none
; Output none
;
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
	ld	c, d
	call	debug_print_hex
	pop	de
	push	de
	ld	c, e
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
;
; debug_show_hl - Show contents of hl
;
; Input none
; Alters none
; Output none
;
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
	ld	c, h
	call	debug_print_hex
	pop	hl
	push	hl
	ld	c, l
	call	debug_print_hex
	call	debug_print_eol

	pop	hl
	pop	af
	pop	bc
	pop	de

	ret

s_hl: .asciz "hl: "

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; debug_show_sp - Show contents of sp
;
; Input none
; Alters none
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

debug_show_sp:

	; The only way to read the SP is to copy it to memory.
	; Note that the value we get will include the return
	; address that we must go back to.
	ld	(debug_get_sp), SP

	push	de
	push	bc
	push	af
	push	hl

	ld	hl, s_sp
	call	debug_print_string
	ld	hl, (debug_get_sp)
	ld	c, h
	call	debug_print_hex
	ld	hl, (debug_get_sp)
	ld	c, l
	call	debug_print_hex
	call	debug_print_eol

	pop	hl
	pop	af
	pop	bc
	pop	de

	ret

s_sp: .asciz "sp: "

#data RAM

debug_get_sp:
	ds	2
