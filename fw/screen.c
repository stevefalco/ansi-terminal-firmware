// ANSI Terminal
//
// (c) 2021 Steven A. Falco
//
// This file contains the state machines that process incoming characters
// from the UART, and perform all the escape sequence processing.  We handle
// a subset of the vt100 escape sequences, sufficient to work properly with
// 2.11bsd.
//
// There is a partial implementation of scroll regions, but it is buggy - at
// least on Linux, vim doesn't behave properly.  As a workaround, we have a
// reduced-functionality terminfo file for Linux, which simply eliminates
// the scroll region escape sequences.

#include "screen.h"
#include "uart.h"
#include "debug.h"

// Dual-ported video memory - 1920 shorts.
#define screen_cols		(80)					// Number of columns
#define screen_lines		(24)					// Number of lines
#define screen_length		(screen_cols * screen_lines)		// Length of whole screen
#define screen_end		(screen_base + screen_length)		// LWA+1
#define screen_last_line_start	(screen_end - screen_cols)		// Address of col=0, row=23
#define screen_last_line_end	(screen_end - 1)			// Address of col=79, row=23

#define char_bs			(0x08)
#define char_ht			(0x09)
#define char_lf			(0x0a)
#define char_vt			(0x0b)
#define char_ff			(0x0c)
#define char_cr			(0x0d)
#define char_escape		(0x1b)

// Escape state machine states.
#define escape_none_state	(0x00)			// No escape yet
#define escape_need_first_state	(0x01)			// Need first char of sequence
#define escape_csi_state	(0x02)			// First char is '['
#define escape_csi_d_N_state	(0x03)			// Accumulating group of digits in CSI
#define escape_sharp_state	(0x04)			// First char is '#'

#define null_cursor		(0x80)			// A null character plus cursor

static volatile uint16_t	*screen_base = (volatile uint16_t *)(0x8000);

static volatile uint16_t	*screen_cursor_location;	// Pointer into video memory.
static volatile uint16_t	*screen_cursor_location_save;	// A place to save the cursor for ESC-7 and ESC-8
static uint16_t	*screen_current_fwa;		// FWA changes with scroll region
static uint16_t	*screen_current_lwa_p1;		// LWA+1 changes with scroll region

static uint8_t	screen_escape_state;		// State machine variable.
static uint8_t	screen_group_0_digits;		// Group 0 accumulated digits.
static uint8_t	screen_group_1_digits;		// Group 1 accumulated digits.
static uint8_t	*screen_group_pointer;		// Pointer into the group that we are accumulating digits for.
static uint8_t	screen_col79_flag;		// Column 79 flag.
static uint8_t	screen_dec_flag;		// Processing a DEC escape sequence.
static uint8_t	screen_dec_top_margin;		// Prevent scrolling above the top margin.  Range 0-23
static uint8_t	screen_dec_bottom_margin;	// Prevent scrolling below the bottom margin.

void
screen_initialize()
{
	int i;
	volatile uint16_t *p = screen_base;

	// Zero all of video memory.  The memory is 1920 16-bit words long.
	for(i = 0; i < screen_length; i++) {
		*p++ = 0;
	}

	// Initialize the cursor pointer and light the cursor in position 0,0.
	screen_cursor_location = screen_base;
	screen_cursor_location_save = screen_base;
	screen_base[0] = null_cursor;

	// Not handling an escape sequence.
	screen_escape_state = escape_none_state;
	screen_group_0_digits = 0;
	screen_group_1_digits = 0;
	screen_group_pointer = &screen_group_0_digits;
	

	// Clear the column 79 and DEC flags.
	screen_col79_flag = 0;
	screen_dec_flag = 0;

	// Top margin starts out as 0, bottom margin starts out as 23.
	screen_dec_top_margin = 0;
	screen_dec_bottom_margin = screen_lines - 1;

	// Start off with the screen start and end properly set.
	screen_current_fwa = (uint16_t *)screen_base;
	screen_current_lwa_p1 = (uint16_t *)screen_end;
}

static void
screen_escape_handler_first(uint8_t c)
{
}

static void
screen_escape_handler_in_csi(uint8_t c)
{
}

static void
screen_escape_in_sharp(uint8_t c)
{
}

static void
screen_scroll_up()
{
	int to_scroll;
	int to_move;
	int i;
	volatile uint16_t *destination;
	volatile uint16_t *source;

	// We have to respect the scroll regions.  Figure out how many
	// lines are to be scrolled.
	//
	// If we are unlimited, the top line is 0, the bottom line is 23.
	// and the difference is 23, which is the correct number of lines
	// to scroll.
	to_scroll = screen_dec_bottom_margin - screen_dec_top_margin;

	// Calculate the number of cells to move.
	to_move = to_scroll * screen_cols;

	// Calculate the starting destination line FWA.  The top line number
	// is still in C, and DE still has 80.
	destination = screen_base + (screen_dec_top_margin * screen_cols);
	source = destination + screen_cols;
	for(i = 0; i < to_move; i++) {
		*destination++ = *source++;
	}

	// Now clear the last line, since it is "new".
	destination = screen_base + (screen_dec_bottom_margin * screen_cols);
	for(i = 0; i < screen_cols; i++) {
		*destination++ = 0;
	}
}

static void
screen_escape_handler(uint8_t c)
{
	// We are in an escape sequence, and we've gotten the next character
	// of it.

	// FIXME
	//
	// Our UART returns 8-bit characters, and some documents suggest that
	// escape sequence characters might have 0x40 added to them.  For example,
	// a left square bracket might be 0x5b, or it might be 0x9b.  If that
	// turns out to be the case, we may have to make an adjustment and handle
	// both forms here...

	// What state are we in?
	switch(screen_escape_state) {
		case escape_need_first_state:
			screen_escape_handler_first(c); //Got first char after escape
			break;

		case escape_csi_state:
			screen_escape_handler_in_csi(c); // Got first char after '['
			break;

		case escape_csi_d_N_state:
			screen_escape_handler_in_csi(c); // Accumulating d0 or d1
			break;

		case escape_sharp_state:
			screen_escape_in_sharp(c); // Got first char after '#'
			break;

		default:
			// Eventually there may be more states above.  This is the catch-all,
			// which we shouldn't ever hit.  So, clear the escape state and give
			// up.
			screen_escape_state = escape_none_state;
			break;
	}
}

static int
screen_cursor_in_line()
{
	int diff = screen_cursor_location - screen_base;
	int line = 0;

	// I tried using modulo here, but the program crashes.  There must be some sort of
	// exception generated.
	while(diff >= screen_cols) {
		++line;
		diff -= screen_cols;
	}

	return line;
}

static volatile uint16_t *
screen_cursor_start_of_line()
{
	volatile uint16_t *tmp;

	// Find what line we are on.  The call returns 0 to 23 in register A.
	// As a side effect, it also clears carry.
	tmp = screen_base + (screen_cursor_in_line() * screen_cols);

	return tmp;
}

static void
screen_normal_char(uint8_t c)
{
	volatile uint16_t *p;

	// Put the character on the screen at the current position.
	// There is one tricky bit.  If the column is 0 through 78, then
	// we place the character and advance the cursor one column.
	//
	// But, if we are in column 79, we don't advance the cursor until
	// we get one more character.  That new character goes into column
	// 0 on the next line, with scrolling if needed, and the cursor
	// winds up in column 1.
	//
	// If the column 79 flag is set, this character needs special
	// handling.
	if(screen_col79_flag) {
		msg("flag 79");

		// This column is no longer a cursor.  Clear the flag and
		// bump to the proposed new cursor location.
		*screen_cursor_location++ &= ~null_cursor;

		// We may now be pointing to column 0 of a line on the screen, or
		// we may be pointing to the LWA+1; i.e. off screen  If so, we must
		// scroll up before doing anything further.
		if(screen_cursor_location >= screen_end) {
			// The cursor is off the screen at LWA+1.
			//
			// Scroll up, cursor now at col=0, row=23.
			screen_scroll_up();
			screen_cursor_location = screen_last_line_start;
		}

		// Put the character on screen.
		*screen_cursor_location++ = c;

		// Make the new position a cursor.
		*screen_cursor_location |= null_cursor;

		// Clear the col 79 flag
		screen_col79_flag = 0;

		return;
	}

	// Find the end of the line, so we don't move too far.
	p = screen_cursor_start_of_line() + (screen_cols - 1);
	if(screen_cursor_location < p) {
		// This is the normal case.  Place the character on the screen and
		// move the cursor.
		*screen_cursor_location++ = c;

		// Make the new position a cursor.
		*screen_cursor_location |= null_cursor;
		return;
	}

	// This is the special case.  Put it on screen, and make it a cursor, but
	// then set a flag rather than moving the cursor.
	*screen_cursor_location = c | null_cursor;
	screen_col79_flag = 1;

	// We don't move the cursor, so we are done.
	return;
}

void
screen_handle_bs()
{
	volatile uint16_t *start_of_line;
	volatile uint16_t *proposed_new_position;

	// We want to move the cursor backwards one position, but we cannot
	// go before col=0 of the row.
	// 
	// Also, if we happen to be in column 79, we will land in column 78,
	// meaning that we must clear the col79 flag.  It is always safe to
	// do this.
	screen_col79_flag = 0;
	
	// Find the beginning of the line, so we don't move too far.
	start_of_line = screen_cursor_start_of_line();
	proposed_new_position = screen_cursor_location - 1;
	if(proposed_new_position >= start_of_line) {
		// The move is good.  The current position is no longer a cursor.
		*screen_cursor_location &= ~null_cursor;

		// Back up one position.
		screen_cursor_location = proposed_new_position;

		// The new position is a cursor.
		*screen_cursor_location |= null_cursor;
	}
}

void
screen_handle_ht()
{
	volatile uint16_t *p;
	int col_number;

	// Move the cursor to the next modulo-8 position on the line.
	//
	// First, get the starting address of the line.
	p = screen_cursor_start_of_line();

	// This position is no longer a cursor.
	*screen_cursor_location &= ~null_cursor;
	
	// Find the new location.  Note that we must stay in this line, so we
	// must not go past column 79.
	col_number = screen_cursor_location - p;

	col_number += 8;	// Move forward 8 positions
	col_number &= ~7;	// Clear three LSBs

	// Now we need to make sure we didn't run off the end of the line.
	if(col_number > 79) {
		// We went too far.  Instead, we need to stop at column 79.
		col_number = screen_cols - 1;
	}

	// Move to the new position.
	screen_cursor_location = p + col_number;
	
	// The new position is a cursor.
	*screen_cursor_location |= null_cursor;
}

void
screen_handle_lf()
{
}

void
screen_handle_cr()
{
}

void
screen_begin_escape()
{
}

void
screen_handler()
{
	int rv;

	if((rv = uart_receive()) == -1) {
		return; // Nothing available.
	}

	// We first have to determine if we are collecting an escape
	// sequence.
	if(screen_escape_state != escape_none_state) {
		msg("handling escape");
		screen_escape_handler(rv & 0xff); // We are handling an escape sequence.
		return;
	}

	// Not in an escape sequence, so treat it as a normal character.
	//
	// Printing characters run from 0x20 through 0x7f.
	if(rv >= ' ') {
		screen_normal_char(rv);
		return;
	}

	switch(rv) {
		// Is it a backspace?
		case char_bs:
			screen_handle_bs();
			break;

		// Is it a horizontal tab?
		case char_ht:
			screen_handle_ht();
			break;

		// Is it a line feed?
		case char_lf:
			screen_handle_lf();
			break;

		// Is it a vertical tab?  This is handled like a line-feed according to a
		// VT102 document I found.
		case char_vt:
			screen_handle_lf();
			break;

		// Is it a form feed?  This is handled like a line-feed according to a
		// VT102 document I found.
		case char_ff:
			screen_handle_lf();
			break;

		// Is it a carriage return?
		case char_cr:
			screen_handle_cr();
			break;

		// Is it an escape?
		case char_escape:
			screen_begin_escape();
			break;

		// Nothing we care about.  Toss it.
		default:
			break;
	}
}
