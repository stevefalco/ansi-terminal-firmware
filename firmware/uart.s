; ANSI Terminal
;
; (c) 2021 Steven A. Falco
;
; UART driver.  We respond to UART receiver interrupts, and store the
; characters in a circular buffer.  If our circular buffer becomes too
; full, we deassert the RTS signal to stop the sender (assuming the
; sender supports hardware flow control).
;
; 2.11bsd as implemented via Sytse's FPGA runs the console at 9600
; baud, and we can keep up with that, even without flow control.  That
; is good, because by default, Sytse's FPGA doesn't implement hardware
; flow control, although it can be turned on in his VHDL if needed.

; UART registers
uart_base		equ 0xc000
uart_RBR		equ (uart_base + 0x00)		; Receiver Buffer Register - read-only
uart_THR		equ (uart_base + 0x00)		; Transmitter Holding Register - write-only
uart_IER		equ (uart_base + 0x01)		; Interrupt Enable Register
uart_IIR		equ (uart_base + 0x02)		; Interrupt Identification Register - read-only
uart_FCR		equ (uart_base + 0x02)		; FIFO Control Register - write-only
uart_LCR		equ (uart_base + 0x03)		; Line Control Register
uart_MCR		equ (uart_base + 0x04)		; Modem Control Register
uart_LSR		equ (uart_base + 0x05)		; Line Status Register
uart_MSR		equ (uart_base + 0x06)		; Modem Status Register
uart_SCR		equ (uart_base + 0x07)		; Scratch Register
uart_DLL		equ (uart_base + 0x00)		; Divisor Latch Low Byte (only when DLAB=1)
uart_DLM		equ (uart_base + 0x01)		; Divisor Latch High Byte (only when DLAB=1)

; UART register bits

; IER
uart_IER_ERBFI_b	equ 0				; Enable Received Data Available Interrupt
uart_IER_ETBEI_b	equ 1				; Enable Transmitter Holding Register Empty Interrupt
uart_IER_ELSI_b		equ 2				; Enable Receiver Line Status Interrupt
uart_IER_EDSSI_b	equ 3				; Enable Model Status Interrupt

; IER bits as values
uart_IER_ERBFI_v	equ (1 << uart_IER_ERBFI_b)
uart_IER_ETBEI_v	equ (1 << uart_IER_ETBEI_b)
uart_IER_ELSI_v		equ (1 << uart_IER_ELSI_b)
uart_IER_EDSSI_v	equ (1 << uart_IER_EDSSI_b)

; IER convenience
uart_IER_INIT		equ (uart_IER_ERBFI_v)

; IIR
uart_IIR_PENDING_b	equ 0				; Interrupt pending when 0

; FCR
uart_FCR_FEN_b		equ 0				; FIFO Enable
uart_FCR_RFR_b		equ 1				; Receive FIFO Reset
uart_FCR_XFR_b		equ 2				; Transmit FIFO Reset

; FCR bits as values
uart_FCR_FEN_v		equ (1 << uart_FCR_FEN_b)
uart_FCR_RFR_v		equ (1 << uart_FCR_RFR_b)
uart_FCR_XFR_v		equ (1 << uart_FCR_XFR_b)

; FCR convenience
uart_FCR_INIT		equ (uart_FCR_FEN_v | uart_FCR_RFR_v | uart_FCR_XFR_v)

; LCR
uart_LCR_WLS0_b		equ 0				; Word Length Select Bit 0
uart_LCR_WLS1_b		equ 1				; Word Length Select Bit 1
uart_LCR_STB_b		equ 2				; Number of Stop Bits
uart_LCR_PEN_b		equ 3				; Parity Enable
uart_LCR_EPS_b		equ 4				; Even Parity Select
uart_LCR_SBRK_b		equ 6				; Set Break
uart_LCR_DLAB_b		equ 7				; Divisor Latch Access Bit

; LCR bits as values
uart_LCR_WLS0_v		equ (1 << uart_LCR_WLS0_b)
uart_LCR_WLS1_v		equ (1 << uart_LCR_WLS1_b)
uart_LCR_STB_v		equ (1 << uart_LCR_STB_b)
uart_LCR_PEN_v		equ (1 << uart_LCR_PEN_b)
uart_LCR_EPS_v		equ (1 << uart_LCR_EPS_b)
uart_LCR_SBRK_v		equ (1 << uart_LCR_SBRK_b)
uart_LCR_DLAB_v		equ (1 << uart_LCR_DLAB_b)

; LCR convenience
uart_LCR_WLS5		equ (0)
uart_LCR_WLS6		equ (uart_LCR_WLS0_v)
uart_LCR_WLS7		equ (uart_LCR_WLS1_v)
uart_LCR_WLS8		equ (uart_LCR_WLS0_v | uart_LCR_WLS1_v)

; MCR
uart_MCR_DTR_b		equ 0				; Data Terminal Ready
uart_MCR_RTS_b		equ 1				; Request To Send

; MCR bits as values
uart_MCR_DTR_v		equ (1 << uart_MCR_DTR_b)
uart_MCR_RTS_v		equ (1 << uart_MCR_RTS_b)

; MCR convenience
uart_MCR_INIT		equ (uart_MCR_DTR_v | uart_MCR_RTS_v)

; LSR
uart_LSR_THRE_b		equ 5				; Transmitter Holding Register Empty

; LSR bits as values
uart_LSR_THRE_v		equ (1 << uart_LSR_THRE_b)

; Baud rate, etc. dip switches
dipSW			equ 0xc010
dipBaudMask		equ 0x0f

uart_depth		equ 128				; SW receiver fifo depth
uart_high_water		equ 64

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uart_receive - get a character from the receiver queue
;
; We have to disable interrupts for mutual exclusion with the
; uart_test_interrupt routine.
;
; Input none
; Alters AF, HL
; Output B = character, or -1 if nothing available.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_receive:
	di				; Disable interrupts

	; Assume nothing available.
	ld	b, -1

	; See if there is something in the buffer
	ld	a, (uart_rb_count)
	or	a
	jr	Z, uart_get_char_none

	; Find the place to get the character.  We use a tricky
	; way to add an 8 and 16 bit register together.
	ld	a, (uart_rb_output)	; offset into buffer
	ld	hl, uart_rb		; start of buffer
	add	a, l			; a = a + l
	ld	l, a			; l = a + l
	adc	a, h			; a = a + l + h + carry
	sub	l			; a = a + h + carry
	ld	h, a			; h = h + carry
	ld	b, (hl)			; read from the buffer

	; Decrement the count.
	ld	a, (uart_rb_count)
	dec	a
	ld	(uart_rb_count), a

	; Bump the output pointer for next time.
	ld	a, (uart_rb_output)
	inc	a
	and	uart_depth - 1		; keep it in range
	ld	(uart_rb_output), a

	ei				; Re-enable interrupts
	ret

uart_get_char_none:

	; If there is nothing available, make sure we haven't blocked
	; the sender.
	ld	hl, uart_MCR
	set	uart_MCR_RTS_b, (hl)

	ei				; Re-enable interrupts
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uart_test_interrupt - see if the uart has posted an interrupt
;
; This runs from the interrupt service routine with interrupts disabled.
;
; Input none
; Alters AF', HL'
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_test_interrupt:

	; (Bit_0 = 1) means no interrupt
	ld	a, (uart_IIR)
	bit	uart_IIR_PENDING_b, a
	jr	NZ, uart_test_interrupt_done

	; Read characters and store them until the uart is empty.  This
	; is ugly because we really cannot tell how much data is in the
	; fifo.  However, we have set the threshold to "1", so when the
	; interrupt clears, the fifo must be empty.  If we had set any
	; other threshold, we'd have to burst "threshold" characters out.
	; We couldn't use the interrupt flag, because it would clear as
	; soon as we went below threshold, which would leave some characters
	; in the fifo.  With threshold = 1, that cannot happen.
	call	uart_store_char
	jr	uart_test_interrupt

uart_test_interrupt_done:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uart_store_char - store a character in the receive buffer
;
; This runs from the interrupt service routine with interrupts disabled.
;
; Input none
; Alters AF', HL'
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_store_char:

	ld	a, (uart_rb_count)	; A = number of characters in our receive buffer
	cp	uart_high_water		; Test the high water mark
	jr	C, uart_store_char_not_too_full ; Below high water

	; Above high water - clear RTS so the sender will pause.
	ld	hl, uart_MCR
	res	uart_MCR_RTS_b, (hl)

	; We may of course be way above the high water mark.  See if
	; there is any room in the buffer
	cp	uart_depth
	jp	P, uart_store_char_no_room

uart_store_char_not_too_full:

	; Find the place to store the character.  We use a tricky
	; way to add an 8 and 16 bit register together.
	ld	a, (uart_rb_input)	; offset into buffer
	ld	hl, uart_rb		; start of buffer
	add	a, l			; a = a + l
	ld	l, a			; l = a + l
	adc	a, h			; a = a + l + h + carry
	sub	l			; a = a + h + carry
	ld	h, a			; h = h + carry
	ld	a, (uart_RBR)		; read from the uart
	ld	(hl), a			; store the character

	; Increment the count
	ld	a, (uart_rb_count)
	inc	a
	ld	(uart_rb_count), a

	; Bump the input pointer for next time.
	ld	a, (uart_rb_input)
	inc	a
	and	uart_depth - 1		; keep it in range
	ld	(uart_rb_input), a

	ret

uart_store_char_no_room:
	; There is no room, but we still have to read the character to
	; retire the interrupt.
	ld	a, (uart_RBR)		; read from the uart
	ret

#data RAM

; Circular receive buffer
uart_rb:
	ds	uart_depth

; Input offset into receive buffer.
uart_rb_input:
	ds	1

; Output offset into receive buffer.
uart_rb_output:
	ds	1

; How many bytes are in the receive buffer.
uart_rb_count:
	ds	1

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uart_transmit_string - transmit the string in HL, where B is the length
;
; Input B, HL
; Alters AF, BC, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_transmit_string:

	ld	c, (hl)
	call	uart_transmit		; send a character
	inc	hl
	djnz	uart_transmit_string	; go back for more

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uart_transmit - transmit the character in register C
;
; Input C
; Alters AF
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_transmit:

	ld	a, (uart_LSR)		; read line status
	bit	uart_LSR_THRE_b, a	; wait until uart can accept a byte
	jr	Z, uart_transmit

	ld	a, c
	ld	(uart_THR), a		; write the byte

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uart_initialize - get the uart ready
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_initialize:
	
	; Clear the receive buffer
	xor	a
	ld	(uart_rb_input), a
	ld	(uart_rb_output), a
	ld	(uart_rb_count), a

	; Set an initial baud rate
	call	uart_set_baud

	; Word length 8, 1 stop, no parity
	; (No need to preserve other bits via read-modify-write)
	ld	hl, uart_LCR
	ld	a, uart_LCR_WLS8
	ld	(hl), a
	
	; Reset FIFOs and enable them
	ld	hl, uart_FCR
	ld	a, uart_FCR_INIT
	ld	(hl), a

	; Set the MODEM control bits
	ld	hl, uart_MCR
	ld	a, uart_MCR_INIT
	ld	(hl), a

	; Enable interrupt - we really only care about received characters
	; because we assume we can't type fast enough to overrun the tx
	; buffer.
	ld	hl, uart_IER
	ld	a, uart_IER_INIT
	ld	(hl), a
	
	; Unblock the sender.
	ld	hl, uart_MCR
	set	uart_MCR_RTS_b, (hl)

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; uart_set_baud - set the baud rate based on the dip switches
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_set_baud:

	; Read dip switches into A.
	ld	a, (dipSW)

	; We are using bits 0-3 for the baud rate, so mask out the rest.
	; Put the result into DE.
	and	dipBaudMask
	ld	d, 0
	ld	e, a
	
	; Point to the correct entry - add twice because we need to index
	; into the 16-bit table.
	ld	hl, baud_table
	add	hl, de
	add	hl, de

	; Load the entry into BC.
	ld	c, (hl)
	inc	hl
	ld	b, (hl)

	; Unlock divisor registers.
	ld	hl, uart_LCR
	set	uart_LCR_DLAB_b, (hl)

	; Write the baud rate divisor.
	ld	hl, uart_DLL
	ld	(hl), c

	ld	hl, uart_DLM
	ld	(hl), b

	; Lock divisor registers.
	ld	hl, uart_LCR
	res	uart_LCR_DLAB_b, (hl)

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

