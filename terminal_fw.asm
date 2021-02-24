#target rom

#code ROM, 0x0000, 0x4000

rom	equ 0x0000
ram	equ 0x4000
video	equ 0x8000
uart	equ 0xc000
dipSW	equ 0xc010

RST0:	di
	ld	sp, $7fff
	jp	start

	defs	0x08-$
RST1:	ret

	defs	0x10-$
RST2:	ret

	defs	0x18-$
RST3:	ret

	defs	0x20-$
RST4:	ret

	defs	0x28-$
RST5:	ret

	defs	0x30-$
RST6:	ret

	defs	0x38-$
RST7:	ei
	ret

	defs	0x66-$
NMI:	ld	a, i
	push	af
	pop	af
	ret	po
	ei
	ret

start:
	call	set_baud

	; write char
	ld	b, 0x29
	call	send_char

	; write char
	ld	b, 0x55
	call	send_char

	; write char
	ld	b, 0xaa
	call	send_char

	; move bytes around
mover:	ld	bc, 1920
	ld	de, ram
	ld	hl, video
again:	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	bc
	ld	a, b
	or	c
	jr	nz, again

back:	ld	bc, 1920
	ld	de, video
	ld	hl, ram + 1919
b2:	ld	a, (hl)
	ld	(de), a
	dec	hl
	inc	de
	dec	bc
	ld	a, b
	or	c
	jr	nz, b2

pause:	ld	d, 10

b4:	ld	bc, 65535
b3:	dec	bc
	ld	a, b
	or	c
	jr	nz, b3

	dec	d
	jr	nz, b4

	jr	start
	jr	$


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; send_char - write the character in B to the uart
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

send_char:

	ld	hl, uart + 5
	ld	a, (hl)
	bit	6, a
	jr	z, send_char ; wait for the uart to be ready

	ld	hl, uart
	ld	(hl), b

	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; set_baud - set the baud rate based on the dip switches
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

set_baud:

	; read dip switches into de
	ld	hl, dipSW
	ld	d, 0
	ld	e, (hl)

	; point to the correct entry
	ld	hl, baud_table
	add	hl, de
	add	hl, de

	; load the entry into bc
	ld	a, (hl)
	inc	hl
	ld	b, (hl)
	ld	c, a

	; unlock divisor registers
	ld	hl, uart + 3
	ld	a, 0x80
	ld	(hl), a

	; write the baud rate divisor
	ld	hl, uart
	ld	(hl), c

	inc	hl
	ld	(hl), b

	; lock divisor registers and set 8 bit data, no parity, one stop bit.
	ld	hl, uart + 3
	ld	a, 0x03
	ld	(hl), a

	ret

baud_table:
	.DW	7330	; sw=0 for 110 baud
	.DW	2688	; sw=1 for 300 baud
	.DW	1344	; sw=2 for 600 baud
	.DW	672	; sw=3 for 1200 baud
	.DW	336	; sw=4 for 2400 baud
	.DW	168	; sw=5 for 4800 baud
	.DW	84	; sw=6 for 9600 baud
	.DW	42	; sw=7 for 19200 baud
	.DW	21	; sw=8 for 38400 baud
	.DW	14	; sw=9 for 57600 baud
	.DW	7	; sw=10 for 115200 baud

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
