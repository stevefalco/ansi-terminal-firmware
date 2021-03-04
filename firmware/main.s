#target rom

#code ROM, 0x0000, 0x4000
#data RAM, 0x4000, 0x4000

#code ROM

rst0:	; At address 0x0000
	di
	ld	sp, $8000	; stack pre-decrements, grows down
	jr	start

	defs	0x38-$, $00
isr38:	; At address 0x0038
	di			; block interrupts while in handler
	ex	af, af'		; exchange a & f with their shadows
	exx			; exchange bc, de, and hl with their shadows
	call	isr		; call our handler
	exx			; restore bc, de, and hl
	ex	af, af'		; restore a & f
	ei			; re-enable interrupts
	ret			; and go back to where we were

	defs	0x66-$, $00
nmi:	; At address 0x0066
	ld	a, i
	push	af
	pop	af
	ret	po
	ei
	ret

start:
	im	1		; interrupt mode=1, all ISRs go to 0x38

	; ModelSim wants everything cleared or else unknowns kill the simulation.
	;
	; Note that we cannot use "xor a" to clear A here, because it is
	; initially undefined in the simulator!
	ld	a, 0
	ex	af, af'
	ld	a, 0
	ex	af, af'

	ld	bc, 0
	ld	de, 0
	ld	hl, 0
	exx
	ld	bc, 0
	ld	de, 0
	ld	hl, 0
	exx

	ld	ix, 0
	ld	iy, 0
	
	call	uart_initialize
	call	screen_initialize

	; Ready for interrupts
	ei

	; Main loop
main_loop:
	; Get any waiting uart characters and process them.
	call	screen_handler

	; Get any waiting keyboard characters and process them.
	call	keyboard_handler

	jr	main_loop

isr:
	; See what caused this interrupt.  It could be the keyboard,
	; the uart, or both.

	; Check the keyboard.  The routine will read any available data
	; and clear the interrupt.
	call	keyboard_test_interrupt

	; Check the uart.  The routine will read any available data
	; and clear the interrupt.
	call	uart_test_interrupt

	ret

str:
	.asciz "got "

#include "uart.s"
#include "screen.s"
#include "keyboard.s"
#include "math.s"
#include "debug.s"
