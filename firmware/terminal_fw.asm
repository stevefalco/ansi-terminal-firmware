#target rom

#code ROM, 0x0000, 0x4000

rom			equ 0x0000
ram			equ 0x4000
video			equ 0x8000

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
RST7:	;ei
	ret

	defs	0x66-$
NMI:	ld	a, i
	push	af
	pop	af
	ret	po
	ei
	ret

start:
	im	1

	call	uart_initialize

	; Ready for interrupts
	ei

	; write char
	ld	b, 0x29
	call	uart_transmit

	; write char
	;ld	b, 0x55
	;call	uart_transmit

	; write char
	;ld	b, 0xaa
	;call	uart_transmit

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

	jr	mover
	jr	$

#include "uart.asm"
