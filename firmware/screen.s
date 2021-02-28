; Dual-ported video memory - 1920 bytes.
screen_base		equ 0x8000				; Physical address
screen_line		equ 80					; Length of one line
screen_length		equ 1920				; Length of whole screen
screen_end		equ (screen_base + screen_length)	; LWA+1
screen_last_line_start	equ (screen_end - screen_line)		; Address of col=0, row=23

char_bs			equ 0x08
char_ht			equ 0x09
char_lf			equ 0x0a
char_vt			equ 0x0b
char_ff			equ 0x0c
char_cr			equ 0x0d
char_escape		equ 0x1b
char_space		equ 0x20
char_del		equ 0x7f

; Escape state machine states.
escape_none		equ 0x00
escape_next		equ 0x01

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handler - read from the uart and update the screen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handler:
	call	uart_receive
	ld	a, b
	cp	-1		; -1 means "nothing available"
	ret	Z		; No characters in our receive buffer.

	; We first have to determine if we are collecting an escape
	; sequence.
	ld	a, (screen_escape_state)
	cp	escape_none
	ld	a, b
	jp	NZ, screen_escape_handler	; We are handling an escape sequence.

	; Not in an escape sequence, so treat it as a normal character.
	;
	; Printing characters run from 0x20 through 0x7f.
	cp	char_space
	jp	P, screen_normal_char	; Positive means >=

	; There are not too many special characters, so we won't bother
	; with a jump table.

	; Is it a backspace?
	cp	char_bs
	jr	Z, screen_handle_bs

	; Is it a horizontal tab?
	cp	char_ht
	jr	Z, screen_handle_ht

	; Is it a line feed?
	cp	char_lf
	jr	Z, screen_handle_lf

	; Is it a vertical tab?  This is handled like a line-feed according to a
	; VT102 document I found.
	cp	char_vt
	jr	Z, screen_handle_lf

	; Is it a form feed?  This is handled like a line-feed according to a
	; VT102 document I found.
	cp	char_ff
	jr	Z, screen_handle_lf

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

	; See if hl is now off screen.  If so, we must scroll up before
	; placing the cursor.
	push	hl				; Save potential new cursor position
	or	a				; Clear carry
	ld	bc, screen_end			; LWA+1 of screen memory
	sbc	hl, bc				; Sets borrow if bc > hl
	pop	hl				; Restore potential new cursor position
	jr	C, screen_normal_char_new_cursor; The cursor is still on screen, use it

	; The cursor is off the screen at LWA+1
	call	screen_scroll_up		; Scroll up
	ld	hl, screen_last_line_start	; Cursor now at col=0, row=23

screen_normal_char_new_cursor:
	; Paint a new cursor, but first save whatever is there.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_bs - handle a backspace
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_bs:
	
	; We want to move the cursor backwards one position, but we cannot
	; go before col=0, row=0.

	; See if it is legal to move back.
	or	a				; Clear carry
	ld	hl, (screen_cursor_location)	; Current position
	ld	bc, screen_base			; FWA
	sbc	hl, bc				; Sets Z flag if hl == bc
	jr	Z, screen_handle_bs_at_fwa	; Cannot move before FWA
	
	; Restore the character under the old cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; Move back one position, save under the position, and draw the new cursor.
	dec	hl
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

screen_handle_bs_at_fwa:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_ht - handle a horizontal tab
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_ht:

	; Move the cursor to the next modulo-8 position on the line.
	;
	; First, get the starting address of the line in hl.
	; The routine also clears carry.
	call	screen_cursor_start_of_line

	ld	de, (screen_cursor_location)	; DE = current position, HL = start of line
	ex	de, hl				; HL = current position, DE = start of line

	; Put back the saved character.
	ld	a, (screen_char_under_cursor)
	ld	(hl), a
	
	; Find the new location.  Note that we must stay in this line, so we
	; must not go past column 79.
	sbc	hl, de			; HL = column number, range 0 to 79
	ld	a, l			; A = column number, range 0 to 79
	add	a, 8			; Move forward 8 positions
	and	a, 0xf8			; Clear three LSBs

	; Now we need to make sure we didn't run off the end of the line.
	ld	l, a			; Save the column into L
	cp	a, screen_line		; Did we go too far?
	jr	C, screen_handle_ht_ok	; No, we are ok

	; We went too far.  Instead, we need to stop at column 79.
	ld	l, screen_line - 1

screen_handle_ht_ok:

	add	hl, de			; HL = new position

	; Save under and paint a new cursor.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_lf - handle a line feed
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_lf:

	; line-feed means we move 80 characters forward, but if that would
	; move us off the screen, then we have to scroll up one line.
	ld	hl, (screen_cursor_location)
	ld	bc, screen_line		; bc = 80
	add	hl, bc			; this will clear carry
	ld	de, hl			; save the result
	ld	bc, screen_end		; LWA + 1
	sbc	hl, bc			; will set borrow if bc > hl
	jr	C, screen_lf_no_scroll

	; We have to scroll up.  First, put back whatever was under the cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; Now scroll up.
	call	screen_scroll_up

	; Finally, repaint the cursor.  The new line is blank, so save the
	; space under the cursor.
	ld	hl, (screen_cursor_location)
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(hl), char_del

	ret

screen_lf_no_scroll:

	; Just move the cursor.  First, replace whatever was under the cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; Now save whatever is under the new cursor, and paint a cursor over it.
	; And save the location.
	ld	hl, de
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(hl), char_del
	ld	(screen_cursor_location), hl

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_cr - handle a carriage return
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_cr:

	; Replace the existing cursor with whatever should be under it.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a
	
	; Find the start of whatever line the cursor is on.  The pointer is
	; returned in HL.
	call	screen_cursor_start_of_line

	; Save under, then put the cursor there.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(hl), char_del
	ld	(screen_cursor_location), hl

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_handle_escape - handle an escape
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_escape:

	; An escape sequence is variable length.  We need a state-machine to
	; keep track of where we are in a potential sequence.
	;
	; We have seen an escape character, so we now must wait for the next
	; character to see what it means.
	ld	a, escape_next
	ld	(screen_escape_state), a
	
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_scroll_up - scroll up one line
;
; Uses af, bc, de, hl
;
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

	; Put up a cursor with a space under it.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(hl), char_del

	; Not handling an escape sequence.
	xor	a
	ld	(screen_escape_state), a

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_cursor_in_line - figure out which line the cursor is in.
;
; Uses af, bc, de, hl
;
; Result in register A, carry will be clear at the end of this routine.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_cursor_in_line:
	xor	a				; Clear register A

	; Start at the beginning.
	ld	de, screen_line			; de = 80 chars per line
	ld	hl, screen_base - 1		; hl = base address of video minus 1
	ld	bc, (screen_cursor_location)	; bc = cursor address in video ram

	; Save the screen base for use in the loop.
	push	hl

screen_cursor_in_line_again:
	; Calculate the end of a line and place it into HL.  HL will contain
	; the address of the end of the line, thus it should always refer to
	; column 79.
	pop	hl
	add	hl, de				; Side effect: clears carry for sbc below.
	push	hl

	; See if we are past it.
	sbc	hl, bc				; Will set borrow if bc > hl, meaning the
						; cursor is past the end of this line.
	jr	NC, screen_cursor_in_line_found	; No borrow.  Cursor is in this line.

	; Next line
	inc	a
	jr	screen_cursor_in_line_again

screen_cursor_in_line_found:
	; Undo the initial push.
	pop	hl

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_cursor_start_of_line - Find the address of the start of the line containing cursor
;
; Uses af, bc, de, hl
;
; Result in register HL, carry will be clear at the end of this routine.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_cursor_start_of_line:

	; Find what line we are on.  The call returns 0 to 23 in register A.
	; As a side effect, it also clears carry.
	call	screen_cursor_in_line

	; Bump A so we can use sub below.
	add	a, 1					; Can't set carry
	ld	hl, screen_base - screen_line		; hl = imaginary line before buffer
	ld	bc, screen_line				; bc = 80

	; We essentially need to add (A * 80) to hl.  Since there is no
	; multiply instruction, we just repeatedly add.
screen_cursor_start_of_line_again:
	add	hl, bc					; hl = start of next line, no carry
	sub	1					; Won't set borrow (carry)
	jr	NZ, screen_cursor_start_of_line_again

	; HL contains pointer to the first byte of the line.
	ret

char_lsb		equ '['

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; screen_escape_handler - Run the escape state machine.
;
; New character is in both registers A and B
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_escape_handler:
	cp	char_lsb
	ret

#data RAM

; Pointer into video memory.
screen_cursor_location:
	ds	2

screen_char_under_cursor:
	ds	1

screen_escape_state:
	ds	1

