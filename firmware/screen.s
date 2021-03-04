; Dual-ported video memory - 1920 bytes.
screen_base		equ 0x8000				; Physical address
screen_cols		equ 80					; Number of columns
screen_lines		equ 24					; Number of lines
screen_length		equ 1920				; Length of whole screen
screen_end		equ (screen_base + screen_length)	; LWA+1
screen_last_line_start	equ (screen_end - screen_cols)		; Address of col=0, row=23

char_bs			equ 0x08
char_ht			equ 0x09
char_lf			equ 0x0a
char_vt			equ 0x0b
char_ff			equ 0x0c
char_cr			equ 0x0d
char_escape		equ 0x1b
char_del		equ 0x7f

; Escape state machine states.
escape_none_state	equ 0x00			; No escape yet
escape_need_first_state	equ 0x01			; Need first char of sequence
escape_csi_state	equ 0x02			; First char is '['
escape_csi_d_N_state	equ 0x03			; Accumulating group of digits in CSI

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_handler - read from the uart and update the screen
;
; Input none
; Alters AF, B
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handler:
	call	uart_receive
	ld	a, b
	cp	-1		; -1 means "nothing available"
	ret	Z		; No characters in our receive buffer.

	; We first have to determine if we are collecting an escape
	; sequence.
	ld	a, (screen_escape_state)
	cp	escape_none_state
	ld	a, b
	jp	NZ, screen_escape_handler	; We are handling an escape sequence.

	; Not in an escape sequence, so treat it as a normal character.
	;
	; Printing characters run from 0x20 through 0x7f.
	cp	' '			; Space character
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

	; Is it a vertical tab?  This is handled like a line-feed according to a
	; VT102 document I found.
	cp	char_vt
	jp	Z, screen_handle_lf

	; Is it a form feed?  This is handled like a line-feed according to a
	; VT102 document I found.
	cp	char_ff
	jp	Z, screen_handle_lf

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
;
; screen_normal_char - normal printing character.
;
; Input B = new character
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_normal_char:

	; Put the character in B on the screen at the current position.
	; There is one tricky bit.  If the column is 0 through 78, then
	; we place the character and advance the cursor one column.
	;
	; But, if we are in column 79, we don't advance the cursor until
	; we get one more character.  That new character goes into column
	; 0 on the next line, with scrolling if needed, and the cursor
	; winds up in column 1.
	;
	; Before we do anything else, save B on the stack.
	push	bc

	; If the column 79 flag is set, this character needs special
	; handling.
	ld	a, (screen_col79_flag)
	or	a
	jr	NZ, screen_normal_char_col79

	; Find the end of the line, so we don't move too far.
	call	screen_cursor_start_of_line		; HL = FWA of this line
	ld	de, screen_cols - 1			; DE = 79
	add	hl, de					; HL = LWA of this line, clears carry
	ex	de, hl					; DE = LWA of this line
	ld	hl, (screen_cursor_location)		; HL = current location
	sbc	hl, de					; Sets borrow if de (LWA) > hl (curr pos)
	jr	C, screen_normal_char_not_last_col	; We are not at the last column

	; This is the special case.  Instead of placing the character on the
	; screen, we place it in the "save under" buffer.
	pop	bc					; Get the new char back
	ld	a, b					; New character
	ld	(screen_char_under_cursor), a		; Store it.

	; Set a flag so we know we are in the special case.
	ld	a, 1
	ld	(screen_col79_flag), a

	; We don't move the cursor, so we are done.
	ret

screen_normal_char_not_last_col:
	; This is the normal case.  Place the character on the screen and
	; move the cursor.
	pop	bc					; Get the new char back
	ld	hl, (screen_cursor_location)		; HL = current location
	ld	(hl), b
	inc	hl

	; We know that the cursor must still be on this line, so save under,
	; and paint the cursor.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

	ret

screen_normal_char_col79:
	; First, take the hidden character out of the "save under" buffer
	; and place it on the screen.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)		; HL = current location
	ld	(hl), a
	inc	hl					; HL = proposed cursor

	; HL may now be pointing to column 0 of a line on the screen, or
	; it may be pointing to the LWA+1; i.e. off screen  If so, we must
	; scroll up before doing anything further.
	ld	de, hl					; Save potential new cursor position
	or	a					; Clear carry
	ld	bc, screen_end				; LWA+1 of screen memory
	sbc	hl, bc					; Sets borrow if bc > hl
	ld	hl, de					; Restore potential new cursor position
	jr	C, screen_normal_char_new_cursor	; The cursor is still on screen, use it

	; The cursor is off the screen at LWA+1
	call	screen_scroll_up			; Scroll up
	ld	hl, screen_last_line_start		; Cursor now at col=0, row=23

screen_normal_char_new_cursor:
	; Place the new character in column 0.
	pop	bc					; Get the new char back
	ld	(hl), b
	inc	hl					; HL now in column 1.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a		; Save under
	ld	(screen_cursor_location), hl
	ld	(hl), char_del				; Paint the new cursor

	xor	a
	ld	(screen_col79_flag), a			; Clear the col 79 flag

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_handle_bs - handle a backspace
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_bs:
	
	; We want to move the cursor backwards one position, but we cannot
	; go before col=0 of the row.
	; 
	; Also, if we happen to be in column 79, we will land in column 78,
	; meaning that we must clear the col79 flag.  It is always safe to
	; do this.
	xor	a
	ld	(screen_col79_flag), a			; Clear the col 79 flag
	
	; Find the beginning of the line, so we don't move too far.
	call	screen_cursor_start_of_line		; HL = FWA of this line
	ex	de, hl					; DE = FWA of this line
	ld	hl, (screen_cursor_location)		; HL = current position
	dec	hl					; HL = proposed new position
	xor	a					; Clear carry
	sbc	hl, de					; Sets borrow if DE (FWA) > HL (proposal)
	jr	C, screen_move_cursor_bs_done		; The move is bad, we cannot move

	; The move is good.  Restore the character under the old cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; Back up one position.
	dec	hl

	; Save whatever is under the new cursor position and paint a new cursor.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

screen_move_cursor_bs_done:
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_handle_ht - handle a horizontal tab
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
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
	cp	a, screen_cols		; Did we go too far?
	jr	C, screen_handle_ht_ok	; No, we are ok

	; We went too far.  Instead, we need to stop at column 79.
	ld	l, screen_cols - 1

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
;
; screen_handle_lf - handle a line feed
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_lf:

	; Put back whatever was under the cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; line-feed means we move 80 characters forward, but if that would
	; move us off the screen, then we have to scroll up one line.
	ld	hl, (screen_cursor_location); HL = original position
	ld	bc, screen_cols		; BC = 80
	add	hl, bc			; HL = proposed new position, clears carry
	ld	de, hl			; DE = proposed new position
	ld	bc, screen_end		; BC = LWA+1
	sbc	hl, bc			; Set borrow if BC (LWA+1) > HL (proposed position)
	ld	hl, de			; HL = proposed new position
	jr	C, screen_lf_no_scroll	; proposed new position is ok

	; Now scroll up.
	call	screen_scroll_up
	ld	hl, (screen_cursor_location)

screen_lf_no_scroll:

	; Save whatever is under the new cursor, and paint a cursor over it.
	; And save the location.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(hl), char_del
	ld	(screen_cursor_location), hl

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_handle_cr - handle a carriage return
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_cr:

	; No matter what, we will land in colunm 0, meaning that we must clear
	; the col79 flag.  It is always safe to do this.
	xor	a
	ld	(screen_col79_flag), a			; Clear the col 79 flag

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
;
; screen_scroll_up - scroll up one line
;
; Input none
; Alters F, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_scroll_up:

	; Move 23 lines up.  The top line is lost.
	ld	hl, screen_base	+ screen_cols		; source
	ld	de, screen_base				; destination
	ld	bc, screen_cols * 23			; all 23 lines
	ldir
	
	; Now clear the last line, since it is "new".
	ld	hl, screen_base	+ (23 * screen_cols)
	ld	b, screen_cols
screen_scroll_up_loop:
	ld	(hl), 0
	inc	hl
	djnz	screen_scroll_up_loop

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_scroll_down - scroll down one line
;
; Input none
; Alters F, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_scroll_down:

	; Move 23 lines down.  The bottom line is lost.
	ld	hl, screen_end - 1 - screen_cols	; source
	ld	de, screen_end - 1			; destination
	ld	bc, screen_cols * 23			; all 23 lines
	lddr
	
	; Now clear the first line, since it is "new".
	ld	hl, screen_base
	ld	b, screen_cols
screen_scroll_down_loop:
	ld	(hl), 0
	inc	hl
	djnz	screen_scroll_down_loop

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_initialize - clear our working storage.
;
; Input none
; Alters AF, BC, HL
; Output none
;
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
	jr	NZ, screen_initialize_loop
	
	; Initialize the cursor pointer.
	ld	hl, screen_base
	ld	(screen_cursor_location), hl
	ld	(screen_cursor_location_save), hl

	; Put up a cursor with a space under it.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(hl), char_del

	; Not handling an escape sequence.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ld	(screen_group_0_digits), a
	ld	(screen_group_1_digits), a
	ld	hl, screen_group_0_digits	; Pointer to the group_0 buffer
	ld	(screen_group_pointer), hl	; Save the pointer

	; Clear the column 79 flag
	xor	a
	ld	(screen_col79_flag), a			; Clear the col 79 flag

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_cursor_in_line - Figure out which line the cursor is in.
;
; Input none
; Alters AF, BC, DE, HL
; Output A = line containing cursor (0 to 23), clears carry
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_cursor_in_line:
	xor	a				; Clear register A

	; Start at the beginning.
	ld	de, screen_cols			; DE = 80 chars per line
	ld	hl, screen_base - 1		; HL = base address of video minus 1
	ld	bc, (screen_cursor_location)	; BC = cursor address in video ram

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
	sbc	hl, bc				; Will set borrow if BC > HL, meaning the
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
;
; screen_cursor_start_of_line - Find the address of the start of the line containing cursor
;
; Input none
; Alters AF, B, DE, HL
; Output HL = FWA of the line containing the cursor, clears carry
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_cursor_start_of_line:

	; Find what line we are on.  The call returns 0 to 23 in register A.
	; As a side effect, it also clears carry.
	call	screen_cursor_in_line			; A = line number

	ld	de, screen_cols				; DE = 80
	call	math_multiply_16x8			; HL = A * DE (0 to 1840)
	ld	de, screen_base				; DE = start of video buffer
	add	hl, de					; HL = start of line

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_handle_escape - handle an escape
;
; Input none
; Alters A
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_escape:

	; An escape sequence is variable length.  We need a state-machine to
	; keep track of where we are in a potential sequence.
	;
	; We have seen an escape character, so we now must wait for the next
	; character to see what it means.
	ld	a, escape_need_first_state
	ld	(screen_escape_state), a
	
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_escape_handler - Run the escape state machine.
;
; Called for each new character until the escape sequence ends.
;
; Input B = new character
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_escape_handler:

	; We are in an escape sequence, and we've gotten the next character
	; of it.

	; FIXME
	;
	; Our UART returns 8-bit characters, and some documents suggest that
	; escape sequence characters might have 0x40 added to them.  For example,
	; a left square bracket might be 0x5b, or it might be 0x9b.  If that
	; turns out to be the case, we may have to make an adjustment and handle
	; both forms here...

	; What state are we in?
	ld	a, (screen_escape_state)

	cp	escape_need_first_state
	jr	Z, screen_escape_handler_first		; Got first char after escape

	cp	escape_csi_state
	jr	Z, screen_escape_handler_in_csi		; Got first char after '['

	cp	escape_csi_d_N_state
	jr	Z, screen_escape_handler_in_csi		; Accumulating d0

	; Eventually there will be more states above.  This is the catch-all,
	; which we shouldn't ever hit.  So, clear the escape state and give
	; up.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_escape_handler_first
;
; We have the first character after an escape.  Based on what we've got,
; change states.
;
; Input B = new character
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_escape_handler_first:
	
	; Clear our working storage.
	xor	a
	ld	(screen_group_0_digits), a
	ld	(screen_group_1_digits), a
	ld	hl, screen_group_0_digits	; Pointer to the group_0 buffer
	ld	(screen_group_pointer), hl	; Save the pointer
	
	; This is the first character after an escape.
	;
	; Test for '[', the so-called CSI
	ld	a, b
	cp	'['
	jr	Z, screen_escape_handler_start_csi

	cp	'7'
	jp	Z, screen_save_cursor_position

	cp	'8'
	jp	Z, screen_restore_cursor_position

	cp	'M'
	jp	Z, screen_handle_reverse_scroll

	; Eventually there may be additional first chars.  This is the
	; catch-all, which we shouldn't ever hit.  So, clear the escape
	; state and give up.

	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_escape_handler_start_csi
;
; We received a '['.
;
; Input none
; Alters A
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_escape_handler_start_csi:

	; Switch to the CSI state.
	ld	a, escape_csi_state
	ld	(screen_escape_state), a

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_escape_handler_in_csi
;
; We received a character following a '['.
;
; Input B = new character
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_escape_handler_in_csi:

	ld	a, b					; A = new character

	; Test for some of the simple commands.
	cp	'A'
	jp	Z, screen_move_cursor_up
	
	cp	'B'
	jp	Z, screen_move_cursor_down

	cp	'C'
	jp	Z, screen_move_cursor_right

	cp	'D'
	jp	Z, screen_move_cursor_left

	cp	'H'
	jp	Z, screen_move_cursor_numeric

	cp	'J'
	jp	Z, screen_clear_to_end_of_screen

	cp	'K'
	jp	Z, screen_clear_to_end_of_line

	; If it is a semicolon, we have collected all the digits in an argument.
	; Note that there may be no digits before the semicolon, which implies zero.
	cp	';'
	jp	Z, screen_next_argument

	; If this is a digit, go to an "accumulating digits" state, until we
	; see a non-digit.
	cp	'0'
	jr	C, screen_bad_sequence			; < '0' character
	cp	'9' + 1
	jr	C, screen_got_group_N_digit		; <= '9' character

screen_bad_sequence:

	; This is not a sequence we handle yet.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_got_group_N_digit
;
; Input B = new digit
; Alters AF, C, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_got_group_N_digit:

	; We have a digit.  Go into the group N digits state.
	ld	a, escape_csi_d_N_state
	ld	(screen_escape_state), a

	; Find the buffer we are using.
	ld	hl, (screen_group_pointer)

	; Save this digit.  First, multiply the previous digits, if any, by 10.
	ld	a, (hl)
	call	math_multiply_10
	add	a, b					; Add the new digit as ASCII
	sub	'0'					; Correct it to be numeric
	ld	(hl), a		; Save the result

	ret
	
#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_move_cursor_up
;
; Input none
; Alters HL, BC, DE, AF
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_move_cursor_up:

	; If we are still in the escape_csi_state state, we didn't get any
	; digits, so we just move the cursor up one line.  Start by assuming
	; that.
	ld	b, 1					; B = 1 line
	push	bc					; Save the assumed value
	
	;  Test the assumption.
	ld	a, (screen_escape_state)
	cp	escape_csi_state			; Were there any digits?
	jr	Z, screen_move_cursor_up_do		; No, assumption was correct

	; Assumption was wrong; get the distance to move up.  This is tricky
	; because 0 or 1 means 1.
	pop	bc					; Discard the assumed value
	ld	a, (screen_group_0_digits)		; A = number of lines to move
	or	a					; Set flags
	jr	NZ, screen_move_cursor_up_ready		; Non zero - use it directly
	inc	a					; Change A = 0 to A = 1
screen_move_cursor_up_ready:
	ld	b, a
	push	bc					; Save the corrected value

screen_move_cursor_up_do:

	; Move the cursor 80 characters backwards, but if that would
	; move us off the screen, then do nothing.
	or	a					; Clear carry
	ld	hl, (screen_cursor_location)
	ld	bc, screen_cols				; BC = 80
	sbc	hl, bc					; HL = proposed new location (clears carry)
	ld	de, hl					; DE = proposed new location
	ld	bc, screen_base				; BC = FWA of screen memory
	sbc	hl, bc					; will set borrow if BC (FWA) > HL (proposed location)
	jr	C, screen_move_cursor_up_cannot

	; We have room to move the cursor.  Replace what was under the cursor.
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

	; See if we are done.  We cannot use djnz because b gets trashed in the loop.
	pop	bc					; Retrieve the count
	dec	b
	push	bc
	jr	NZ, screen_move_cursor_up_do		; Move up another line.

screen_move_cursor_up_cannot:
	pop	bc					; Clean up stack

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_move_cursor_down
;
; Input none
; Alters HL, BC, DE, AF
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_move_cursor_down:

	; If we are still in the escape_csi_state state, we didn't get any
	; digits, so we just move the cursor down one line.  Start by assuming
	; that.
	ld	b, 1					; B = 1 line
	push	bc					; Save the assumed value
	
	;  Test the assumption.
	ld	a, (screen_escape_state)
	cp	escape_csi_state			; Were there any digits?
	jr	Z, screen_move_cursor_down_do		; No, assumption was correct

	; Assumption was wrong; get the distance to move up.  This is tricky
	; because 0 or 1 means 1.
	pop	bc					; Discard the assumed value
	ld	a, (screen_group_0_digits)		; A = number of lines to move
	or	a					; Set flags
	jr	NZ, screen_move_cursor_down_ready	; Non zero - use it directly
	inc	a					; Change A = 0 to A = 1
screen_move_cursor_down_ready:
	ld	b, a
	push	bc					; Save the corrected value

screen_move_cursor_down_do:

	; Move cursor 80 characters forward, but if that would
	; move us off the screen, then do nothing.
	ld	hl, (screen_cursor_location)		; HL = current position
	ld	bc, screen_cols				; BC = 80
	add	hl, bc					; HL = proposed new location (clears carry)
	ld	de, hl					; DE = proposed new location
	ld	bc, screen_end				; BC = LWA+1 of screen memory
	sbc	hl, bc					; Sets borrow if BC (LWA+1) > HL (proposed location)
	jr	NC, screen_move_cursor_down_cannot

	; We have room to move the cursor.  Replace what was under the cursor.
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

	; See if we are done.  We cannot use djnz because b gets trashed in the loop.
	pop	bc					; Retrieve the count
	dec	b
	push	bc
	jr	NZ, screen_move_cursor_down_do		; Move down another line.

screen_move_cursor_down_cannot:
	pop	bc					; Clean up stack

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_move_cursor_right
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_move_cursor_right:

	; Restore the character under the old cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; If we are still in the escape_csi_state state, we didn't get any
	; digits, so we just move the cursor right one character.  Start
	; by assuming that.
	xor	a
	ld	b, a
	ld	c, 1
	
	;  Test the assumption.
	ld	a, (screen_escape_state)
	cp	escape_csi_state
	jr	Z, screen_move_cursor_right_do		; Assumption was correct

	; Assumption was wrong; get the distance to move right.  This is tricky
	; because 0 or 1 means 1.
	;
	; Note that B is still zero from above.
	ld	a, (screen_group_0_digits)		; Get the value
	or	a					; Set flags
	jr	NZ, screen_move_cursor_right_ready	; Non zero - use it directly
	inc	a					; Change 0 to 1
screen_move_cursor_right_ready:
	ld	c, a

screen_move_cursor_right_do:

	; HL still contains the current position.  Increment HL to the proposed
	; new position and save it on the stack.  We will pop it into DE.
	add	hl, bc
	push	hl					; push proposal

	; Find the end of the line, so we don't move too far.
	call	screen_cursor_start_of_line		; HL = FWA of this line
	ld	de, screen_cols - 1			; DE = 79
	add	hl, de					; HL = LWA of this line, clears carry

	; Retrieve the proposed location and see if we can move that far.
	pop	de					; DE = proposal
	push	hl					; push LWA
	sbc	hl, de					; Sets borrow if DE (proposal) > HL (LWA)
	pop	hl					; HL = LWA
	jr	C, screen_move_cursor_right_go		; The move is bad, use LWA, alread in HL

	; The proposed move is good.  Get it into HL.
	ex	de, hl

screen_move_cursor_right_go:

	; Save whatever is under the new cursor position and paint a new cursor.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret
	
#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_move_cursor_left
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_move_cursor_left:

	; No matter what, we cannot land in colunm 79, meaning that we must clear
	; the col79 flag.  It is always safe to do this.
	xor	a
	ld	(screen_col79_flag), a			; Clear the col 79 flag

	; Restore the character under the old cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; If we are still in the escape_csi_state state, we didn't get any
	; digits, so we just move the cursor left one character.  Start
	; by assuming that.
	xor	a
	ld	b, a
	ld	c, 1
	
	;  Test the assumption.
	ld	a, (screen_escape_state)
	cp	escape_csi_state
	jr	Z, screen_move_cursor_left_do		; Assumption was correct

	; Assumption was wrong; get the distance to move left.  This is tricky
	; because 0 or 1 means 1.
	;
	; Note that B is still zero from above.
	ld	a, (screen_group_0_digits)		; Get the value
	or	a					; Set flags
	jr	NZ, screen_move_cursor_left_ready	; Non zero - use it directly
	inc	a					; Change 0 to 1
screen_move_cursor_left_ready:
	ld	c, a

screen_move_cursor_left_do:

	; HL still contains the current position.  Decrement HL to the proposed
	; new position and save it on the stack.  We will pop it into DE.
	or	a					; Clear carry
	sbc	hl, bc
	push	hl					; push proposal

	; Find the beginning of the line, so we don't move too far.
	call	screen_cursor_start_of_line		; HL = FWA of this line

	; Retrieve the proposed location and see if we can move that far.
	pop	de					; DE = proposal
	push	de					; push proposal
	ex	de, hl					; DE = FWA, HL = proposal
	sbc	hl, de					; Sets borrow if DE (FWA) > HL (proposal)
	ex	de, hl					; HL = FWA, DE = garbage
	pop	de					; DE = proposal
	jr	C, screen_move_cursor_left_go		; The move is bad, use FWA, alread in HL

	; The proposed move is good.  Get it into HL.
	ex	de, hl

screen_move_cursor_left_go:

	; Save whatever is under the new cursor position and paint a new cursor.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_clear_to_end_of_screen
;
; Input none
; Alters AF, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_clear_to_end_of_screen:

	; Clear the character under the cursor
	xor	a					; Clear A
	ld	(screen_char_under_cursor), a

	ld	hl, (screen_cursor_location)		; HL = cursor location
	ld	de, screen_end				; DE = LWA+1

	; We will clear with nulls.
	xor	a

screen_clear_to_end_of_screen_loop:
	inc	hl					; Next position to clear

	; Make sure we haven't gone off the end.
	or	a					; Clear carry
	push	hl					; Save HL on the stack
	sbc	hl, de					; Sets borrow if DE > HL
	pop	hl					; HL = position to clear
	jr	NC, screen_clear_to_end_of_screen_done
	ld	(hl), a					; Clear the character
	jr	screen_clear_to_end_of_screen_loop

screen_clear_to_end_of_screen_done:

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_clear_to_end_of_screen
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_clear_to_end_of_line:

	; Clear the character under the cursor
	xor	a					; Clear A
	ld	(screen_char_under_cursor), a

	; Find the end of the line, so we don't move too far.
	call	screen_cursor_start_of_line		; HL = FWA of this line
	ld	de, screen_cols				; DE = 80
	add	hl, de					; HL = LWA+1 of this line, clears carry
	ex	de, hl					; DE = LWA+1, HL=80
	ld	hl, (screen_cursor_location)		; HL = cursor location

	; We will clear with nulls.
	xor	a

screen_clear_to_end_of_line_loop:
	inc	hl					; Next position to clear

	; Make sure we haven't gone off the end.  Carry is already clear.
	or	a					; Clear carry
	push	hl					; Save HL on the stack
	sbc	hl, de					; Sets borrow if DE > HL
	pop	hl					; HL = position to clear
	jr	NC, screen_clear_to_end_of_line_done
	ld	(hl), a					; Clear the character
	jr	screen_clear_to_end_of_line_loop

screen_clear_to_end_of_line_done:

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_next_argument - we got a semicolon, so there may be a second argument
;
; Input none
; Alters HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_next_argument:

	; We only handle up to two arguments.  So, just switch to group 1.
	ld	hl, screen_group_1_digits		; Pointer to the group_1 buffer
	ld	(screen_group_pointer), hl		; Save the pointer

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_move_cursor_numeric
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_move_cursor_numeric:

	; There may be digits or not, but it doesn't matter.  If there are
	; no digits, our numeric buffers have 0,0 which means the same thing
	; as if there were no digits; i.e. go to the upper left corner.
	;
	; HOWEVER, in VT100 escape sequences, the lines and columns are
	; numbered from 1, and the spec says that both 0 and 1 are to be
	; interpreted as 1.  We number lines and columns from 0, so we need
	; to make some adjustments.
	;
	; Basically, we have to decrement the parameters to make them 0-based,
	; but we must not go below zero.

	; Restore the character under the old cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; Zero D for use when we multiply and add.
	xor	a
	ld	d, a

	; Get the line parameter, and multiply it by 80.
	ld	a, (screen_group_0_digits)
	or	a					; First see if it needs adjustment
	jr	Z, screen_move_cursor_numeric_no_decrement_group_0 ; No, leave it zero
	dec	a					; Yes - convert to 0-based
screen_move_cursor_numeric_no_decrement_group_0:

	; We also need to limit the line parameter to a maximum of 23.
	cp	screen_lines				; sets borrow if A = 23 or less
	jr	C, screen_move_cursor_numeric_no_overflow_group_0 ; Good
	ld	a, screen_lines - 1			; Overflow, so limit it
screen_move_cursor_numeric_no_overflow_group_0:
	ld	e, a					; D still 0, E = new row
	ld	a, screen_cols				; A = 80
	call	math_multiply_16x8			; HL = new row * 80

	; Get the column parameter and add it in.
	ld	a, (screen_group_1_digits)
	or	a					; First see if it needs adjustment
	jr	Z, screen_move_cursor_numeric_no_decrement_group_1
	dec	a					; Yes - convert to 0-based
screen_move_cursor_numeric_no_decrement_group_1:

	; We also need to limit the column parameter to a maximum of 79.
	cp	screen_cols - 1				; sets borrow if A = 78 or less
	jr	NC, screen_move_cursor_numeric_col79_group_1

	; We are moving to a column other than 79.  We must clear the flag.
	push	af
	xor	a
	ld	(screen_col79_flag), a			; Clear the col 79 flag
	pop	af

screen_move_cursor_numeric_col79_group_1:
	cp	screen_cols				; sets borrow if A = 79 or less
	jr	C, screen_move_cursor_numeric_no_overflow_group_1
	ld	a, screen_cols - 1			; Overflow, so limit it
screen_move_cursor_numeric_no_overflow_group_1:
	ld	e, a					; D still 0, E = new column
	add	hl, de					; HL = (new row * 80) + new column

	; Get the start of the screen and combine.
	ld	de, screen_base				; DE = video FWA
	add	hl, de					; HL = new address in video ram

	; Paint a new cursor, but first save whatever is there.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(screen_cursor_location), hl
	ld	(hl), char_del

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_save_cursor_position
;
; Input none
; Alters A, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_save_cursor_position:

	; Save the cursor position
	ld	hl, (screen_cursor_location)
	ld	(screen_cursor_location_save), hl

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_restore_cursor_position
;
; Input none
; Alters A, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_restore_cursor_position:

	; Restore the character under the old cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; Restore the cursor position
	ld	hl, (screen_cursor_location_save)
	ld	(screen_cursor_location), hl

	; Paint a new cursor, but first save whatever is there.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(hl), char_del

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; screen_handle_reverse_scroll
;
; Input none
; Alters AF, BC, DE, HL
; Output none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

screen_handle_reverse_scroll:

	; First, put back whatever was under the cursor.
	ld	a, (screen_char_under_cursor)
	ld	hl, (screen_cursor_location)
	ld	(hl), a

	; reverse-scroll means we move 80 characters backward, but if that would
	; move us off the screen, then we have to scroll down one line.
	ld	hl, (screen_cursor_location)		; HL = current position
	ld	bc, screen_cols				; BC = 80
	or	a					; Clear carry
	sbc	hl, bc					; HL = proposed new position
	ld	de, hl					; DE = proposed new position
	ld	bc, screen_base				; BC = FWA
	sbc	hl, bc					; Set borrow if BC (FWA) > HL (proposed position)
	ld	hl, de					; HL = proposed new position
	jr	NC, screen_reverse_no_scroll		; No borrow, so no scroll is needed

	; We have to scroll down.
	call	screen_scroll_down
	ld	hl, (screen_cursor_location)		; HL = original position

screen_reverse_no_scroll:

	; Save whatever is under the new cursor, and paint a cursor over it.
	ld	a, (hl)
	ld	(screen_char_under_cursor), a
	ld	(hl), char_del
	ld	(screen_cursor_location), hl

	; Escape sequence complete.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ret

#data RAM

; Pointer into video memory.
screen_cursor_location:
	ds	2

; A place to save the cursor for ESC-7 and ESC-8
screen_cursor_location_save:
	ds	2

; Pointer into the group that we are accumulating digits for.
screen_group_pointer:
	ds	2

; Preserved character under the cursor so we can replace it when the cursor moves.
screen_char_under_cursor:
	ds	1

; State machine variable.
screen_escape_state:
	ds	1

; Group 0 accumulated digits.
screen_group_0_digits:
	ds	1

; Group 1 accumulated digits.
screen_group_1_digits:
	ds	1

; Column 79 flag.
screen_col79_flag:
	ds	1
