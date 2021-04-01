#target rom

#code ROM, 0x0000, 0x4000
#data RAM, 0x4000, 0x4000

controlReg		equ 0xc030

; Bits in the control register as bits
controlScreen_b		equ 0		; Screen enabled when bit is set

; Bits in the control register as values
controlScreen_v		equ (1 << controlScreen_b)

; Time limit for screen blanking.  We want 15 minutes (900 seconds).  Since the
; counter increments roughly every two seconds, use 450 as the limit.
timeout_limit		equ 450

#code ROM

rst0:	; At address 0x0000
	di
	ld	sp, $8000		; stack pre-decrements, grows down
	jr	start

	defs	0x38-$, $00
isr38:	; At address 0x0038
	di				; block interrupts while in handler
	ex	af, af'			; exchange a & f with their shadows
	exx				; exchange bc, de, and hl with their shadows
	call	isr			; call our handler
	exx				; restore bc, de, and hl
	ex	af, af'			; restore a & f
	ei				; re-enable interrupts
	ret				; and go back to where we were

	defs	0x66-$, $00
nmi:	; At address 0x0066
	ld	a, i
	push	af
	pop	af
	ret	po
	ei
	ret

start:
	im	1			; interrupt mode=1, all ISRs go to 0x38

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
	
	; Clear our variables.  HL is already zero.
	ld	(divider), hl
	ld	(inactivity_counter), hl

	; Turn the screen on.  The control register is not readable
	; so we keep a shadow copy.
	ld	a, controlScreen_v
	ld	(controlReg), a
	ld	(controlReg_shadow), a

	call	uart_initialize
	call	screen_initialize
	call	keyboard_initialize

	; Ready for interrupts
	ei

	; Main loop
main_loop:
	; If the screen is currently on, we increment the inactivity counter.
	; If the screen is currently off, we skip the increment.  Otherwise,
	; when the count wrapped around, the screen would come back on.
	ld	hl, controlReg_shadow
	bit	controlScreen_b, (hl)
	jr	Z, skip_increment

	; We need more than 16 bits for the inactivity counter.  We could do
	; 32-bit increments and 32-bit tests, but it is easier to just run
	; two separate 16-bit counters, with overflow of the first counter
	; controlling the increment of the second counter.
	;
	; The divider variable will overflow roughly every two seconds, meaning
	; that the inactivity_counter variable will increment every two seconds.
	ld	de, 1
	ld	hl, (divider)
	add	hl, de
	ld	(divider), hl
	jr	NC, skip_increment

	ld	hl, (inactivity_counter)	; Screen is on; bump the counter
	inc	hl
	ld	(inactivity_counter), hl

skip_increment:
	
	; Test the inactivity counter, and disable the video output
	; if we've been idle too long.
	xor	a				; Clear carry
	ld	bc, timeout_limit		; Get the desired timeout limit
	ld	hl, (inactivity_counter)	; Get the current count
	sbc	hl, bc				; Sets borrow if not yet at the limit
	jr	C, skip_turnoff

	ld	a, (controlReg_shadow)
	res	controlScreen_b, a
	ld	(controlReg), a			; Clear the bit in the hardware
	ld	(controlReg_shadow), a		; Clear the bit in our shadow

skip_turnoff:
	
	; Get any waiting uart characters and process them.
	call	screen_handler

	; Get any waiting keyboard characters and process them.
	; The Z flag will be clear if anything was processed.
	call	keyboard_handler

	jr	Z, main_loop	; No activity; let the counter run.

	; Had some activity, so reset the counter and make sure the screen
	; is on.
	ld	hl, 0
	ld	(divider), hl
	ld	(inactivity_counter), hl

	ld	a, (controlReg_shadow)
	set	controlScreen_b, a
	ld	(controlReg), a			; Set the bit in the hardware
	ld	(controlReg_shadow), a		; Set the bit in our shadow

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

#data RAM

divider:
	ds	2

inactivity_counter:
	ds	2

controlReg_shadow:
	ds	1

#include "uart.s"
#include "screen.s"
#include "keyboard.s"
#include "math.s"
#include "debug.s"
