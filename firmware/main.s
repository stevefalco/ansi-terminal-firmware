#target rom

#code ROM, 0x0000, 0x4000
#data RAM, 0x4000, 0x4000

ram			equ 0x4000
video			equ 0x8000

#code ROM

rst0:	; at address 0x0000
	di
	ld	sp, $8000	; stack pre-decrements, grows down
	jp	start

	defs	0x38-$, $00
isr38:	; at address 0x0038
	di			; block interrupts while in handler
	ex	af, af'		; exchange a & f with their shadows
	exx			; exchange bc, de, and hl with their shadows
	call	isr		; call our handler
	exx			; restore bc, de, and hl
	ex	af, af'		; restore a & f
	ei			; re-enable interrupts
	ret			; and go back to where we were

	defs	0x66-$, $00
nmi:	; at address 0x0066
	ld	a, i
	push	af
	pop	af
	ret	po
	ei
	ret

start:
	im	1		; interrupt mode=1, all ISRs go to 0x38

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
mover:	ld	bc, screen_buffer_end - screen_buffer
	ld	de, screen_buffer
	ld	hl, video
again:	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	bc
	ld	a, b
	or	c
	jr	nz, again

back:	ld	bc, screen_buffer_end - screen_buffer
	ld	de, video
	ld	hl, screen_buffer_end - 1
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

isr:

#data RAM
screen_buffer:
	ds	1920
screen_buffer_end:

#include "uart.s"
