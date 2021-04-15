// ANSI Terminal
//
// (c) 2021 Steven A. Falco
//
// This file contains the state machines that process incoming characters
// from the UART, and perform all the escape sequence processing.  We handle
// a subset of the vt100 escape sequences, sufficient to work properly with
// 2.11bsd.
//
// I also tested on Linux with vim, and we behave correctly.

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
static volatile uint16_t	*screen_current_fwa;		// FWA changes with scroll region
static volatile uint16_t	*screen_current_lwa_p1;		// LWA+1 changes with scroll region

static uint8_t	screen_escape_state;		// State machine variable.
static uint8_t	screen_group_0_digits;		// Group 0 accumulated digits (often means row number).
static uint8_t	screen_group_1_digits;		// Group 1 accumulated digits (often means column number).
static uint8_t	*screen_group_pointer;		// Pointer into the group that we are accumulating digits for.
static uint8_t	screen_col79_flag;		// Column 79 flag.
static uint8_t	screen_dec_flag;		// Processing a DEC escape sequence.
static uint8_t	screen_dec_top_margin;		// Prevent scrolling above the top margin.  Range 0-23
static uint8_t	screen_dec_bottom_margin;	// Prevent scrolling below the bottom margin.  Range 0-23
static uint8_t	screen_origin_mode;		// Absolute (0) or Relative (1)

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
	screen_current_fwa = screen_base;
	screen_current_lwa_p1 = screen_end;

	// Start off with absolute origin mode.
	screen_origin_mode = 0;
}

static void
screen_escape_handler_start_csi()
{
	screen_escape_state = escape_csi_state;
}

static void
screen_start_sharp()
{
	screen_escape_state = escape_sharp_state;
}

static void
screen_save_cursor_position()
{
	screen_cursor_location_save = screen_cursor_location;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_restore_cursor_position()
{
	// Remove the old cursor.
	*screen_cursor_location &= ~null_cursor;

	// Restore the cursor position
	screen_cursor_location = screen_cursor_location_save;

	// Make the new position a cursor.
	*screen_cursor_location |= null_cursor;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
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

	// Calculate the starting destination line FWA.
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
screen_scroll_down()
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

	// Calculate the starting destination line LWA.  This is a bit
	// tricky.  We calculate the FWA of the line below the bottom
	// margin (the part in the parens), which is also the LWA+1 of
	// the bottom margin.  Then we subtract one, which gives us the
	// LWA of the bottom margin, and that is the destination.
	destination = screen_base + ((screen_dec_bottom_margin + 1) * screen_cols) - 1;
	source = destination - screen_cols;
	for(i = 0; i < to_move; i++) {
		*destination-- = *source--;
	}

	// Now clear the top line, since it is "new".
	destination = screen_base + (screen_dec_top_margin * screen_cols);
	for(i = 0; i < screen_cols; i++) {
		*destination++ = 0;
	}
}

static void
screen_handle_lf()
{
	int curr_line;
	int new_line;
	volatile uint16_t *proposed_new_position;

	// There are two cases.  If we are within the scroll region, we move
	// down or scroll.  But if we are not within the scroll region, we
	// do an absolute move.
	curr_line = screen_cursor_in_line();
	if(curr_line < screen_dec_top_margin || curr_line > screen_dec_bottom_margin) {
		// Absolute move, bounded by screen dimensions.  No scrolling.
		new_line = curr_line + 1;
		if(new_line > (screen_lines - 1)) {
			// We would land past the last row - do nothing.
			return;
		}

		// This position is no longer a cursor.
		*screen_cursor_location &= ~null_cursor;

		// Find new position - known good.
		screen_cursor_location += screen_cols;

		// The new position is a cursor.
		*screen_cursor_location |= null_cursor;

		return;
	}

	// This position is no longer a cursor.
	*screen_cursor_location &= ~null_cursor;

	// We are within the scroll region.  In this case, line-feed means we
	// move 80 characters forward, but if that would move us out of the
	// scroll region, then we have to scroll up one line.
	proposed_new_position = screen_cursor_location + screen_cols;
	if(proposed_new_position >= screen_current_lwa_p1) {
		// Must scroll up.
		screen_scroll_up();
	} else {
		screen_cursor_location = proposed_new_position;
	}

	// The new position is a cursor.
	*screen_cursor_location |= null_cursor;
}

static void
screen_handle_cr()
{
	// No matter what, we will land in colunm 0, meaning that we must clear
	// the col79 flag.  It is always safe to do this.
	screen_col79_flag = 0;

	// No longer a cursor.
	*screen_cursor_location &= ~null_cursor;
	
	// Find the start of whatever line the cursor is on.
	screen_cursor_location = screen_cursor_start_of_line();

	// The new position is a cursor.
	*screen_cursor_location |= null_cursor;
}

static void
screen_handle_esc_lf()
{
	//This seems to be like <LF>
	screen_handle_lf();

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_handle_esc_cr_lf()
{
	// This seems to be like <CR><LF>
	screen_handle_cr();
	screen_handle_lf();

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_handle_reverse_scroll()
{
	volatile uint16_t *proposed_new_position;

	// Current position is not a cursor.
	*screen_cursor_location &= ~null_cursor;

	// reverse-scroll means we move 80 characters backward, but if that would
	// move us above the scroll region, then we have to scroll down one line.
	proposed_new_position = screen_cursor_location - screen_cols;
	if(proposed_new_position < screen_current_fwa) {
		// We have to scroll down.
		screen_scroll_down();
	} else {
		screen_cursor_location = proposed_new_position;
	}

	// The new position is a cursor.
	*screen_cursor_location |= null_cursor;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_escape_handler_first(uint8_t c)
{
	// Clear our working storage.
	screen_group_0_digits = 0;
	screen_group_1_digits = 0;
	screen_group_pointer = &screen_group_0_digits;

	// This is the first character after an escape.
	switch(c) {
		case '[':
			screen_escape_handler_start_csi();
			break;

		case '#':
			screen_start_sharp();
			break;

		case '7':
			screen_save_cursor_position();
			break;

		case '8':
			screen_restore_cursor_position();
			break;

		case 'D':
			screen_handle_esc_lf();
			break;

		case 'E':
			screen_handle_esc_cr_lf();
			break;

		case 'M':
			screen_handle_reverse_scroll();
			break;

		// Eventually there may be additional first chars.  This is the
		// catch-all, which we shouldn't ever hit.  So, clear the escape
		// state and give up.
		default:
			screen_escape_state = escape_none_state;
			break;
	}
}

static void
screen_got_csi_group_N_digit(uint8_t c)
{
	uint8_t	*p;

	// We have a digit.  Go into the group N digits state.
	screen_escape_state = escape_csi_d_N_state;

	// Find the buffer we are using.
	p = screen_group_pointer;

	// Save this digit.  First, multiply the previous digits, if any, by 10.
	// Then merge in the new digit.
	*p = (*p * 10) + (c - '0');
}

static void
screen_parse_dec_command(uint8_t c)
{
	// We don't handle most of these, but DECCOLM has the side-effect of
	// reinitializing the screen, and we need that to pass vttest.
	switch(screen_group_0_digits) {
		case 3:
			// Sets the number of columns, but we don't support 132-column mode,
			// so we don't care if the last character is "l" or 'h'.
			//
			// Instead, we just reset everything.
			screen_initialize();
			break;

		case 6:
			// Sets the origin mode.  'h' means relative origin, and
			// 'l' means absolute origin.
			if(c == 'l') {
				screen_origin_mode = 0;
			} else if(c == 'h') {
				screen_origin_mode = 1;
			}
			break;

		default:
			break;
	}

	// Clear the DEC flag.
	screen_dec_flag = 0;
	
	// Done with this escape sequence
	screen_escape_state = escape_none_state;
	return;
}

static void
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

static void
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

static void
screen_begin_escape()
{
	// An escape sequence is variable length.  We need a state-machine to
	// keep track of where we are in a potential sequence.
	//
	// We have seen an escape character, so we now must wait for the next
	// character to see what it means.
	screen_escape_state = escape_need_first_state;
}

static void
screen_next_argument()
{
	// We only handle up to two arguments.  So, just switch to group 1.
	screen_group_pointer = &screen_group_1_digits;
}

static void
screen_send_primary_device_attributes()
{
	// This is a request for our attributes.  Claim that we are a VT100.
	uart_transmit_string("1;2c");
	
	screen_escape_state = escape_none_state;
}

static void
screen_move_cursor_numeric()
{
	int digits0;
	int digits1;

	// There may be digits or not, but it doesn't matter.  If there are
	// no digits, our numeric buffers have 0,0 which means the same thing
	// as if there were no digits; i.e. go to the upper left corner.
	//
	// HOWEVER, in VT100 escape sequences, the lines and columns are
	// numbered from 1, and the spec says that both 0 and 1 are to be
	// interpreted as 1.  We number lines and columns from 0, so we need
	// to make some adjustments.
	//
	// Basically, we have to decrement the parameters to make them 0-based,
	// but we must not go below zero.

	// The current position is no longer a cursor.
	*screen_cursor_location &= ~null_cursor;

	// Get the line parameter, and map it to our notation.
	digits0 = screen_group_0_digits;
	if(digits0 != 0) {
		--digits0; // Convert to 0-based.
	}

	// Bound it to stay on screen.
	if(digits0 >= screen_lines) {
		digits0 = (screen_lines - 1);
	}

	// If we are in relative mode, we have to bias down from the top margin
	// value, and we have to limit to the bottom margin value.
	if(screen_origin_mode == 1) {
		digits0 += screen_dec_top_margin;
		if(digits0 > screen_dec_bottom_margin) {
			digits0 = screen_dec_bottom_margin;
		}
	}

	// Get the column parameter, and map it to our notation.
	digits1 = screen_group_1_digits;
	if(digits1 != 0) {
		--digits1; // Convert to 0-based.
	}

	// Bound it to stay on screen.
	if(digits1 >= screen_cols) {
		digits1 = (screen_cols - 1);
	}

	// Set the new cursor position.
	screen_cursor_location = screen_base + (digits0 * screen_cols) + digits1;

	// The new position is a cursor.
	*screen_cursor_location |= null_cursor;

	// Any move means we must clear the col79 flag.
	screen_col79_flag = 0;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_set_margins()
{
	int digits0;
	int digits1;

	// Special case - if screen_group_0_digits and screen_group_1_digits
	// are both zero, set the full range.
	//
	// Do this test first; it is the only time A = B is allowed - i.e. when
	// A and B are both zero.
	if(screen_group_0_digits == 0 && screen_group_1_digits == 0) {
		// Reset top margin to 0, bottom margin to 23.
		screen_dec_top_margin = 0;
		screen_dec_bottom_margin = screen_lines - 1;

		// Reset FWA and LWA+1
		screen_current_fwa = screen_base;
		screen_current_lwa_p1 = screen_end;

	} else if(screen_group_0_digits < screen_group_1_digits) {
		// For all other cases, the top margin must be strictly less than the bottom margin.
		// Good - we can proceed.
	
		// Get top row number.  Note that row numbers are 1-based, so we have 
		// to decrement, but cannot go below zero.
		digits0 = screen_group_0_digits;
		if(digits0 != 0) {
			--digits0; // Convert to 0-based.
		}

		// Set the top margin.
		screen_dec_top_margin = digits0;
		screen_current_fwa = screen_base + (screen_dec_top_margin * screen_cols);
		
		// Get bottom row number.  Note that row numbers are 1-based, so we have 
		// to decrement, but cannot go below zero.
		digits1 = screen_group_1_digits;
		if(digits1 != 0) {
			--digits1; // Convert to 0-based.
		}

		// Set the bottom margin.  We note that the lwa+1 is the same as the fwa
		// of the following row.  Hence, increase the bottom margin by 1 when doing
		// the calculation.
		screen_dec_bottom_margin = digits1;
		screen_current_lwa_p1 = screen_base + ((screen_dec_bottom_margin + 1) * screen_cols);
	}

	// The old position is not a cursor.
	*screen_cursor_location &= ~null_cursor;

	// Move the cursor to the upper left.
	screen_cursor_location = screen_base;

	// The new position is a cursor.
	*screen_cursor_location |= null_cursor;

	// Any move means we must clear the col79 flag.
	screen_col79_flag = 0;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_move_cursor_up()
{
	int i;
	int to_move;
	volatile uint16_t *limit;
	volatile uint16_t *proposed_new_position;

	// If we are still in the escape_csi_state state, we didn't get any
	// digits, so we just move the cursor up one line.  Start by assuming
	// that.
	to_move = 1;

	// If we are in relative mode, the upper limit depends on the scroll region.
	limit = screen_base;
	if(screen_origin_mode == 1) {
		limit = screen_base + (screen_dec_top_margin * screen_cols);
	}
	
	//  Test the assumption.
	if(screen_escape_state != escape_csi_state) {
		// Assumption was wrong; get the distance to move up.  This is tricky
		// because 0 or 1 means 1.
		to_move = screen_group_0_digits;
		if(to_move == 0) {
			to_move = 1;
		}
	}

	for(i = 0; i < to_move; i++) {
		// Move cursor 80 characters backwards, but if that would
		// move us off the screen (or out of the scroll region),
		// then do nothing.
		proposed_new_position = screen_cursor_location - screen_cols;
		if(proposed_new_position < limit) {
			// No room.
			break;
		}

		// We have room to move the cursor.  The current position is no longer a cursor.
		*screen_cursor_location &= ~null_cursor;

		// The new position is a cursor.
		screen_cursor_location = proposed_new_position;
		*screen_cursor_location |= null_cursor;
	}

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_move_cursor_down()
{
	int i;
	int to_move;
	volatile uint16_t *limit;
	volatile uint16_t *proposed_new_position;

	// If we are still in the escape_csi_state state, we didn't get any
	// digits, so we just move the cursor down one line.  Start by assuming
	// that.
	to_move = 1;
	
	// If we are in relative mode, the lower limit depends on the scroll region.
	limit = screen_end;
	if(screen_origin_mode == 1) {
		limit = screen_end - (((screen_lines - 1) - screen_dec_bottom_margin) * screen_cols);
	}
	
	//  Test the assumption.
	if(screen_escape_state != escape_csi_state) {
		// Assumption was wrong; get the distance to move down.  This is tricky
		// because 0 or 1 means 1.
		to_move = screen_group_0_digits;
		if(to_move == 0) {
			to_move = 1;
		}
	}

	for(i = 0; i < to_move; i++) {
		// Move cursor 80 characters forward, but if that would
		// move us off the screen (or out of the scroll region),
		// then do nothing.
		proposed_new_position = screen_cursor_location + screen_cols;
		if(proposed_new_position >= limit) {
			// No room.
			break;
		}

		// We have room to move the cursor.  The current position is no longer a cursor.
		*screen_cursor_location &= ~null_cursor;

		// The new position is a cursor.
		screen_cursor_location = proposed_new_position;
		*screen_cursor_location |= null_cursor;
	}

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_move_cursor_right()
{
	int to_move;
	volatile uint16_t *start_of_line;
	volatile uint16_t *end_of_line;
	volatile uint16_t *proposed_new_position;

	// If we are still in the escape_csi_state state, we didn't get any
	// digits, so we just move the cursor right one character.  Start
	// by assuming that.
	to_move = 1;
	
	//  Test the assumption.
	if(screen_escape_state != escape_csi_state) {
		// Assumption was wrong; get the distance to move right.  This is tricky
		// because 0 or 1 means 1.
		to_move = screen_group_0_digits;
		if(to_move == 0) {
			to_move = 1;
		}
	}

	// FInd the start and end of the current line.
	start_of_line = screen_cursor_start_of_line();
	end_of_line = start_of_line + (screen_cols - 1);

	// See how far we'd like to move.
	proposed_new_position = screen_cursor_location + to_move;

	// If we would move too far, limit the movement.
	if(proposed_new_position > end_of_line) {
		proposed_new_position = end_of_line;
	}

	// The current position is no longer a cursor.
	*screen_cursor_location &= ~null_cursor;

	// The new position is a cursor.
	screen_cursor_location = proposed_new_position;
	*screen_cursor_location |= null_cursor;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_move_cursor_left()
{
	int to_move;
	volatile uint16_t *start_of_line;
	volatile uint16_t *proposed_new_position;

	// If we are still in the escape_csi_state state, we didn't get any
	// digits, so we just move the cursor left one character.  Start
	// by assuming that.
	to_move = 1;
	
	//  Test the assumption.
	if(screen_escape_state != escape_csi_state) {
		// Assumption was wrong; get the distance to move left.  This is tricky
		// because 0 or 1 means 1.
		to_move = screen_group_0_digits;
		if(to_move == 0) {
			to_move = 1;
		}
	}

	// FInd the start of the current line.
	start_of_line = screen_cursor_start_of_line();

	// See how far we'd like to move.
	proposed_new_position = screen_cursor_location - to_move;

	// If we would move too far, limit the movement.
	if(proposed_new_position < start_of_line) {
		proposed_new_position = start_of_line;
	}

	// The current position is no longer a cursor.
	*screen_cursor_location &= ~null_cursor;

	// The new position is a cursor.
	screen_cursor_location = proposed_new_position;
	*screen_cursor_location |= null_cursor;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_clear_rows()
{
	volatile uint16_t *p;

	// There are three subsets:
	// 0 = erase below
	// 1 = erase above
	// 2 = erase all
	switch(screen_group_0_digits) {
		case 0: // erase below
			for(p = screen_cursor_location; p < screen_end; p++) {
				*p = 0;
			}
			break;

		case 1: // erase above
			for(p = screen_cursor_location; p >= screen_base; p--) {
				*p = 0;
			}
			break;

		case 2: // erase all
			for(p = screen_base; p < screen_end; p++) {
				*p = 0;
			}
			break;

		default:
			break;
	}

	// Put the cursor back on screen.
	*screen_cursor_location |= null_cursor;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_clear_columns()
{
	volatile uint16_t *p;
	volatile uint16_t *line_start;
	volatile uint16_t *line_end;

	line_start = screen_cursor_start_of_line();
	line_end = line_start + screen_cols;

	// There are three subsets:
	// 0 = erase to the right
	// 1 = erase to the left
	// 2 = erase the whole line
	switch(screen_group_0_digits) {
		case 0: // erase right
			for(p = screen_cursor_location; p < line_end; p++) {
				*p = 0;
			}
			break;

		case 1: // erase left
			for(p = screen_cursor_location; p >= line_start; p--) {
				*p = 0;
			}
			break;

		case 2: // erase line
			for(p = line_start; p < line_end; p++) {
				*p = 0;
			}
			break;

		default:
			break;

	}

	// Put the cursor back on screen.
	*screen_cursor_location |= null_cursor;

	// Escape sequence complete.
	screen_escape_state = escape_none_state;
}

static void
screen_set_dec_flag()
{
	// Mark that this is a special DEC sequence
	screen_dec_flag = 1;
}

static void
screen_escape_handler_in_csi(uint8_t c)
{
	// If a control character appears in the middle of an escape sequence,
	// we simply execute it.  This is an error recovery behavior, and should
	// not be sent by an OS.
	switch(c) {
		case char_bs:
			screen_handle_bs();
			return;

		case char_ht:
			screen_handle_ht();
			return;

		case char_lf:
			screen_handle_lf();
			return;

		case char_vt:
			screen_handle_lf();
			return;

		case char_ff:
			screen_handle_lf();
			return;

		case char_cr:
			screen_handle_cr();
			return;

		// An escape while handing an escape is also an error condition.  Terminate
		// the previous sequence and begin a new one.
		case char_escape:
			screen_begin_escape();
			return;
		
		// Semicolon and digits are common to DEC and ANSI, so handle them
		// before checking the DEC flag.

		// If it is a semicolon, we have collected all the digits in an argument.
		// Note that there may be no digits before the semicolon, which implies zero.
		case ';':
			screen_next_argument();
			return;

		// If this is a digit, go to an "accumulating digits" state, until we
		// see a non-digit.
		case '0':
		case '1':
		case '2':
		case '3':
		case '4':
		case '5':
		case '6':
		case '7':
		case '8':
		case '9':
			screen_got_csi_group_N_digit(c);
			return;
			
		default:
			if(screen_dec_flag) {
				// If the DEC flag is set, go to an alternate parser.
				screen_parse_dec_command(c);
				return;
			} else {
				switch(c) {
					// Test for some of the simple commands.
					case 'c':
						screen_send_primary_device_attributes();
						return;

					case 'f':
						screen_move_cursor_numeric();
						return;

					case 'r':
						screen_set_margins();
						return;

					case 'A':
						screen_move_cursor_up();
						return;
					
					case 'B':
						screen_move_cursor_down();
						return;

					case 'C':
						screen_move_cursor_right();
						return;

					case 'D':
						screen_move_cursor_left();
						return;

					case 'H':
						screen_move_cursor_numeric();
						return;

					case 'J':
						screen_clear_rows();
						return;

					case 'K':
						screen_clear_columns();
						return;

					case '?':
						screen_set_dec_flag();
						return;

					default:
						// This is not a sequence we handle yet.
						break;
				}
			}
			break;
	}
		
	screen_escape_state = escape_none_state;
	return;
}

static void
screen_escape_in_sharp(uint8_t c)
{
	volatile uint16_t *p;
	int i;

	switch(c) {
		case '8':
			// Fill the screen with the letter 'E'.
			p = screen_base;
			for(i = 0; i < screen_length; i++) {
				*p++ = 'E';
			}

			// Initialize the cursor pointer.
			screen_cursor_location = screen_base;
			*screen_cursor_location |= null_cursor;
			break;

		default:
			break;
	}

	screen_escape_state = escape_none_state;
	return;
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
			screen_escape_handler_first(c); // Got first char after escape
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
screen_handler()
{
	int rv;

	if((rv = uart_receive()) == -1) {
		return; // Nothing available.
	}

	// We first have to determine if we are collecting an escape
	// sequence.
	if(screen_escape_state != escape_none_state) {
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
