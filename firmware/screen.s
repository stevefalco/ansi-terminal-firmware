; Dual-ported video memory - 1920 bytes.
screen_base		equ 0x8000
screen_length		equ 1920
screen_end		equ (screen_base + screen_length)

char_bs			equ 0x08
char_ht			equ 0x09
char_lf			equ 0x0a
char_vt			equ 0x0b
char_ff			equ 0x0c
char_cr			equ 0x0d
char_escape		equ 0x1b
char_space		equ 0x20
char_del		equ 0x7f

screen_line		equ 80

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handler - read from the uart and update the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handler:
	call	uart_receive
	ld	a, b
	cp	-1		; -1 means "nothing available"
	jp	NZ, screen_handler_got_one
	ret

screen_handler_got_one:

	; Printing characters run from 0x20 through 0x7f.
	cp	char_space
	jp	P, screen_normal_char	; Positive means >=

	; There are not too many special characters, so we won't bother
	; with a jump table.

	; Is it a backspace?
	cp	char_bs
	jp	Z, screen_handle_bs

	; Is it a horizontal tab?
	cp	char_ht
	jp	Z, screen_handle_ht

	; Is it a line feed?
	cp	char_lf
	jp	Z, screen_handle_lf

	; Is it a vertical tab?
	cp	char_vt
	jp	Z, screen_handle_vt

	; Is it a form feed?
	cp	char_ff
	jp	Z, screen_handle_ff

	; Is it a carriage return?
	cp	char_cr
	jp	Z, screen_handle_cr

	; Is it an escape?
	cp	char_escape
	jp	Z, screen_handle_escape

	; Nothing we care about.  Toss it.
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_normal_char - normal printing character.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_normal_char:

	; Put the character in B on the screen at the current position.
	ld	hl, (screen_cursor_location)
	ld	(hl), b
	inc	hl

	; Paint a new cursor.
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_bs - handle a backspace
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_bs:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_ht - handle a horizontal tab
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_ht:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_lf - handle a line feed
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_lf:

	; line-feed means we move 80 characters forward, but if that would
	; move us off the screen, then we have to scroll up one line.
	ld	hl, (screen_cursor_location)
	ld	bc, screen_line
	add	hl, bc			; this will clear carry
	ld	de, hl			; save the result
	ld	bc, screen_end
	sbc	hl, bc			; will set borrow if bc > hl
	jr	C, screen_lf_no_scroll

	; We have to scroll up.  First, clear the old cursor.
	ld	hl, (screen_cursor_location)
	ld	(hl), char_space

	; Now scroll up.
	call	screen_scroll_up

	; Finally, repaint the cursor.
	ld	hl, (screen_cursor_location)
	ld	(hl), char_del

	ret

screen_lf_no_scroll:

	; Just move the cursor.  First, clear under the cursor.
	ld	hl, (screen_cursor_location)
	ld	(hl), char_space

	; Now paint a new cursor and save the location.
	ld	hl, de
	ld	(hl), char_del
	ld	(screen_cursor_location), hl

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_vt - handle a vertical tab
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_vt:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_ff - handle a form feed
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_ff:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_cr - handle a carriage return
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_cr:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_escape - handle an escape
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_escape:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_scroll_up - scroll up one line
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_scroll_up:

	; Move 23 lines up.  The top line is lost.
	ld	hl, screen_base	+ screen_line		; source
	ld	de, screen_base				; destination
	ld	bc, screen_line * 23			; all 23 lines
	ldir
	
	; Now clear the last line, since it is "new".
	ld	hl, screen_base	+ (23 * screen_line)
	ld	bc, screen_line
screen_scroll_loop:
	ld	(hl), 0
	inc	hl
	dec	bc
	ld	a, b
	or	c
	jr	nz, screen_scroll_loop

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_initialize - clear our working storage.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_initialize:
	; Zero all of video memory.
	ld	hl, screen_base
	ld	bc, screen_length
screen_initialize_loop:
	ld	(hl), 0
	inc	hl
	dec	bc
	ld	a, b
	or	c
	jr	nz, screen_initialize_loop
	
	; Initialize the cursor pointer.
	ld	hl, screen_base
	ld	(screen_cursor_location), hl

	; Put up a cursor.
	ld	(hl), char_del

	ret

#data RAM

; Pointer into video memory.
screen_cursor_location:
	ds	2

