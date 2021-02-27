; Dual-ported video memory - 1920 bytes.
video			equ 0x8000
video_length		equ 1920

video_cursor		equ 0x7f

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handler - read from the uart and update the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handler:
	call	uart_receive
	ld	a, b
	cpl			; -1 means nothing available
	or	a		; set flags
	jp	Z, screen_handler_na

	; Put the character in B on the screen at the current position.
	ld	hl, (screen_cursor_location)
	ld	(hl), b
	inc	hl

	ld	(screen_cursor_location), hl
	ld	(hl), video_cursor

screen_handler_na:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_initialize - clear our working storage.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_initialize:
	; Zero all of video memory.
	ld	hl, video
	ld	bc, video_length
screen_initialize_loop:
	ld	(hl), 0
	inc	hl
	dec	bc
	ld	a, b
	or	c
	jr	nz, screen_initialize_loop
	
	; Initialize the cursor pointer.
	ld	hl, video
	ld	(screen_cursor_location), hl

	; Put up a cursor.
	ld	(hl), video_cursor

	ret

#data RAM

; Pointer into video memory.
screen_cursor_location:
	ds	2

