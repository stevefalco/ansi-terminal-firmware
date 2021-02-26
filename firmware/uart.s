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
uart_IER_INIT		equ (uart_IER_ERBFI_v | uart_IER_ETBEI_v | uart_IER_ELSI_v | uart_IER_EDSSI_v)

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

; Baud rate dip switches
dipSW			equ 0xc010

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; uart_transmit - transmit the character in register B
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_transmit:

	ld	hl, uart_LSR		; read line status
	ld	a, (hl)
	bit	uart_LSR_THRE_b, a	; wait until uart can accept a byte
	jr	z, uart_transmit

	ld	hl, uart_THR		; write the byte
	ld	(hl), b

	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; uart_initialize - get the uart ready
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_initialize:
	
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

	; Enable interrupts
	ld	hl, uart_IER
	ld	a, uart_IER_INIT
	ld	(hl), a
	
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; uart_set_baud - set the baud rate based on the dip switches
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

uart_set_baud:

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
	ld	hl, uart_LCR
	set	uart_LCR_DLAB_b, (hl)

	; write the baud rate divisor
	ld	hl, uart_DLL
	ld	(hl), c

	ld	hl, uart_DLM
	ld	(hl), b

	; lock divisor registers
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

