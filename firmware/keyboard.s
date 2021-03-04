; Keyboard registers
keyboard_base		equ 0xc020
keyboard_SCAN_CODE	equ (keyboard_base + 0x00)	; Scan Code register
keyboard_ASCII_CODE	equ (keyboard_base + 0x01)	; ASCII Code register
keyboard_STATUS		equ (keyboard_base + 0x02)	; Status register

; Keyboard register bits

; STATUS
keyboard_Shift_Key	equ 0				; Shift key depressed
keyboard_Key_Released	equ 1				; Key has been released
keyboard_Extended	equ 2				; Extended code prefix
keyboard_Interrupt	equ 3				; Interrupt received

keyboard_depth		equ 128				; Buffer depth.

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; keyboard_initialize - get the keyboard ready
;
; Input none
; Alters A
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

keyboard_initialize:
	
	xor	a

	; Clear the scan code receive buffer
	ld	(keyboard_rb_input), a
	ld	(keyboard_rb_output), a
	ld	(keyboard_rb_count), a

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; keyboard_test_interrupt - see if the keyboard has posted an interrupt
;
; This runs from the interrupt service routine with interrupts disabled.
;
; Input none
; Alters AF', HL'
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

keyboard_test_interrupt:

	; Read the status register to see if this interrupt is for us.
	; Bit 3 = 1 indicates a new character is available.
	ld	a, (keyboard_STATUS)
	bit	keyboard_Interrupt, a
	jr	Z, keyboard_test_interrupt_done

	; Bit 1 = 1 indicates that this is a key release event, which
	; we don't need to store.  But we still have to access the scan
	; code register to clear the interrupt.
	bit	keyboard_Key_Released, a
	jr	NZ, keyboard_test_interrupt_flush

	call	keyboard_store_char
	jr	keyboard_test_interrupt	; See if there is anything more

keyboard_test_interrupt_done:
	ret

keyboard_test_interrupt_flush:
	ld	a, (keyboard_SCAN_CODE)
	jr	keyboard_test_interrupt	; See if there is anything more

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; keyboard_store_char - store a character in the receive buffer
;
; This runs from the interrupt service routine with interrupts disabled.
;
; Input none
; Alters AF', HL'
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

keyboard_store_char:

	; See if there is room in the buffer
	ld	a, (keyboard_rb_count)
	sub	keyboard_depth
	jp	P, keyboard_store_char_no_room

	; Find the place to store the character.  We use a tricky
	; way to add an 8 and 16 bit register together.
	ld	a, (keyboard_rb_input)	; offset into buffer
	add	a			; a = keyboard_rb_input * 2
	add	a			; a = keyboard_rb_input * 4
	ld	hl, keyboard_rb		; start of buffer
	add	a, l			; a = a + l
	ld	l, a			; l = a + l
	adc	a, h			; a = a + l + h + carry
	sub	l			; a = a + h + carry
	ld	h, a			; h = h + carry

	ld	a, (keyboard_STATUS)	; read status
	ld	(hl), a			; store status code
	inc	hl			; move to the next byte

	ld	a, (keyboard_ASCII_CODE); read ascii
	ld	(hl), a			; store ascii code
	inc	hl			; move to the next byte

	ld	a, (keyboard_SCAN_CODE)	; read scan code (retires interrupt)
	ld	(hl), a			; store scan code

	; Increment the count
	ld	a, (keyboard_rb_count)
	inc	a
	ld	(keyboard_rb_count), a

	; Bump the input pointer for next time.
	ld	a, (keyboard_rb_input)
	inc	a
	and	keyboard_depth - 1	; keep it in range
	ld	(keyboard_rb_input), a

keyboard_store_char_no_room:
	; There is no room, but we still have to read the scan code to
	; retire the interrupt.
	ld	a, (keyboard_SCAN_CODE)
	ret

#data RAM

; Circular receive buffer
;
; We store the status byte, ascii code, and scan code.
keyboard_rb:
	ds	keyboard_depth * 4

; Input offset into receive buffer.
keyboard_rb_input:
	ds	1

; Output offset into receive buffer.
keyboard_rb_output:
	ds	1

; How many bytes are in the receive buffer.
keyboard_rb_count:
	ds	1

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; keyboard_receive - get a character from the receiver queue
;
; We have to disable interrupts for mutual exclusion with the
; keyboard_test_interrupt routine.
;
; Input none
; Alters AF, BC, D, HL
; Output B = scan code, or -1 if nothing available.
;        C = ascii code
;        D = status
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

keyboard_receive:
	di

	; Assume nothing available.
	ld	b, -1

	; See if there is something in the buffer
	ld	a, (keyboard_rb_count)
	or	a
	jr	Z, keyboard_get_char_none

	; Find the place to get the character.  We use a tricky
	; way to add an 8 and 16 bit register together.
	ld	a, (keyboard_rb_output)	; offset into buffer
	add	a			; a = keyboard_rb_output * 2
	add	a			; a = keyboard_rb_output * 4
	ld	hl, keyboard_rb		; start of buffer
	add	a, l			; a = a + l
	ld	l, a			; l = a + l
	adc	a, h			; a = a + l + h + carry
	sub	l			; a = a + h + carry
	ld	h, a			; h = h + carry

	ld	d, (hl)			; read status
	inc	hl
	ld	c, (hl)			; read ascii code
	inc	hl
	ld	b, (hl)			; read scan code

	; Decrement the count.
	ld	a, (keyboard_rb_count)
	dec	a
	ld	(keyboard_rb_count), a

	; Bump the output pointer for next time.
	ld	a, (keyboard_rb_output)
	inc	a
	and	keyboard_depth - 1	; keep it in range
	ld	(keyboard_rb_output), a

keyboard_get_char_none:
	ei
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; keyboard_handler - process any keystrokes we may have received.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

keyboard_handler:

	call	keyboard_receive
	ld	a, b
	cp	-1		; -1 means "nothing available"
	ret	Z		; No characters in our receive buffer.

	; If the ascii code is 0, then toss the character.
	ld	a, c		; ASCII code
	or	a		; set flags
	ret	Z		; toss it

	; Dump the scan code and ascii code.
	call	debug_show_bc

	; Dump the status.
	call	debug_show_de

	call	debug_print_eol

	ret

