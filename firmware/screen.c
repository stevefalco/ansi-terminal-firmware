// ANSI Terminal
//
// (c) 2021 Steven A. Falco
//
// ANSI Terminal is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// ANSI Terminal is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with ANSI Terminal.  If not, see <https://www.gnu.org/licenses/>.

// This file contains the state machines that process incoming characters
// from the UART, and perform all the escape sequence processing.  We handle
// a subset of the vt100 escape sequences, sufficient to work properly with
// 2.11bsd.
//
// I also tested on Linux with vim, and we behave correctly.

#include "screen.h"
#include "uart.h"
#include "debug.h"
#include "parser/vtparse.h"
#include "build/version.h"

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

static vtparse_t		screen_parser;		// Parses all received uart characters

static volatile uint16_t	*screen_base = (volatile uint16_t *)(0x8000);

static volatile uint16_t	*screen_cursor_location;	// Pointer into video memory.
static volatile uint16_t	*screen_cursor_location_save;	// A place to save the cursor for ESC-7 and ESC-8
static volatile uint16_t	*screen_current_fwa;		// FWA changes with scroll region
static volatile uint16_t	*screen_current_lwa_p1;		// LWA+1 changes with scroll region

static uint8_t	screen_col79_flag;		// Column 79 flag.
static uint8_t	screen_dec_top_margin;		// Prevent scrolling above the top margin.  Range 0-23
static uint8_t	screen_dec_bottom_margin;	// Prevent scrolling below the bottom margin.  Range 0-23
static uint8_t	screen_origin_mode;		// Absolute (0) or Relative (1)
static uint8_t	screen_autowrap_mode;		// 1 = autowrap, 0 = no autowrap

// Forward references:
static void screen_announce();
static void screen_save_cursor_position();
static void screen_restore_cursor_position();
static int screen_cursor_in_line();
static int screen_cursor_in_column();
static volatile uint16_t *screen_cursor_start_of_line();
static void screen_scroll_up();
static void screen_scroll_down();
static void screen_handle_lf();
static void screen_handle_cr();
static void screen_handle_esc_lf();
static void screen_handle_esc_cr_lf();
static void screen_handle_reverse_scroll();
static void screen_handle_bs();
static void screen_handle_ht();
static void screen_send_primary_device_attributes();
static void screen_move_cursor_numeric(vtparse_t *parser);
static void screen_set_margins(vtparse_t *parser);
static void screen_num_to_uart(int n);
static void screen_report(vtparse_t *parser);
static void screen_move_cursor_up(vtparse_t *parser);
static void screen_move_cursor_down(vtparse_t *parser);
static void screen_move_cursor_right(vtparse_t *parser);
static void screen_move_cursor_left(vtparse_t *parser);
static void screen_clear_rows(vtparse_t *parser);
static void screen_clear_columns(vtparse_t *parser);
static void screen_escape_in_sharp(uint8_t c);
static void screen_normal_char(uint8_t c);
static void screen_control_char(uint8_t c);
static void screen_simple_escape(uint8_t c);
static void screen_parse_ansi_csi_command(vtparse_t *parser, uint8_t c);
static void screen_parse_dec_csi_command(vtparse_t *parser, uint8_t c);
static void screen_csi_escape(vtparse_t *parser, uint8_t c);
static void screen_non_csi_escape(vtparse_t *parser, uint8_t c);
static void screen_parser_callback(vtparse_t *parser, vtparse_action_t action, unsigned char c);

// Announce our information on the screen - only for cold-start.
static void
screen_announce()
{
	char *p;

	static char line0[] = "ANSI Terminal (c) 2021 Falco Engineering";
	static char line1[] = "Version: ";

	for(p = line0; *p; p++) {
		screen_normal_char(*p);
	}
	screen_handle_lf();
	screen_handle_cr();

	for(p = line1; *p; p++) {
		screen_normal_char(*p);
	}
	for(p = VERSION; *p; p++) {
		screen_normal_char(*p);
	}
	for(p = GIT_STATE; *p; p++) {
		screen_normal_char(*p);
	}
	screen_handle_lf();
	screen_handle_lf();
	screen_handle_cr();
}

// screen_initialize - clear our working storage.
void
screen_initialize(int cold)
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

	// Clear the column 79.
	screen_col79_flag = 0;

	// Autowrap defaults to on.
	screen_autowrap_mode = 1;

	// Top margin starts out as 0, bottom margin starts out as 23.
	screen_dec_top_margin = 0;
	screen_dec_bottom_margin = screen_lines - 1;

	// Start off with the screen start and end properly set.
	screen_current_fwa = screen_base;
	screen_current_lwa_p1 = screen_end;

	// Start off with absolute origin mode.
	screen_origin_mode = 0;

	// On a cold-start, print our version info to the screen.
	if(cold) {
		screen_announce();
	}

	// Set up the parser.
	vtparse_init(&screen_parser, screen_parser_callback);
}

// screen_save_cursor_position - esc-7
static void
screen_save_cursor_position()
{
	screen_cursor_location_save = screen_cursor_location;
}

// screen_restore_cursor_position - esc-8
static void
screen_restore_cursor_position()
{
	// Remove the old cursor.
	*screen_cursor_location &= ~null_cursor;

	// Restore the cursor position
	screen_cursor_location = screen_cursor_location_save;

	// Make the new position a cursor.
	*screen_cursor_location |= null_cursor;
}

// screen_cursor_in_column - Figure out which column the cursor is in.
//
// Return the cursor column number in the range of 0 to 79.
static int
screen_cursor_in_column()
{
	// We work with pointers.  Find the difference between the current
	// position and the start of the screen.
	int diff = screen_cursor_location - screen_base;

	// Columns run from 0 to 79, so we can find the column number as
	// "diff modulo 80".
	int column = diff % screen_cols;

	return column;
}

// screen_cursor_in_line - Figure out which line the cursor is in.
//
// Return the cursor line number in the range of 0 to 23.
static int
screen_cursor_in_line()
{
	// We work with pointers.  Find the difference between the current
	// position and the start of the screen.
	int diff = screen_cursor_location - screen_base;

	// Columns run from 0 to 79, so we can find the line number as
	// "diff / 80".
	int line = diff / screen_cols;

	return line;
}

// screen_cursor_start_of_line - Find the address of the start of the line containing cursor
//
// Return the FWA of the line containing the cursor.
static volatile uint16_t *
screen_cursor_start_of_line()
{
	volatile uint16_t *tmp;

	// Find what line we are on, scale up by the number of columns per line,
	// then add that to the screen base address.
	tmp = screen_base + (screen_cursor_in_line() * screen_cols);

	return tmp;
}

// screen_scroll_up - scroll up one line.
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

// screen_scroll_down - scroll down one line
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

// screen_handle_lf - handle a line feed
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

// screen_handle_cr - handle a carriage return
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

// screen_handle_esc_lf - ESC D
static void
screen_handle_esc_lf()
{
	//This seems to be like <LF>
	screen_handle_lf();
}

// screen_handle_esc_cr_lf - ESC E
static void
screen_handle_esc_cr_lf()
{
	// This seems to be like <CR><LF>
	screen_handle_cr();
	screen_handle_lf();
}

// screen_handle_reverse_scroll - ESC M
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
}

// screen_parse_ansi_csi_command
static void
screen_parse_ansi_csi_command(vtparse_t *parser, uint8_t c)
{
	switch(c) {
		case 'c': // DA
			screen_send_primary_device_attributes();
			break;

		case 'f': // HVP
			screen_move_cursor_numeric(parser);
			break;

		case 'n':
			screen_report(parser);
			break;

		case 'r': // DECSTBM
			screen_set_margins(parser);
			break;

		case 'A': // CUU
			screen_move_cursor_up(parser);
			break;

		case 'B': // CUD
			screen_move_cursor_down(parser);
			break;

		case 'C': // CUF
			screen_move_cursor_right(parser);
			break;

		case 'D': // CUB
			screen_move_cursor_left(parser);
			break;

		case 'H': // CUP
			screen_move_cursor_numeric(parser);
			break;

		case 'J': // ED
			screen_clear_rows(parser);
			break;

		case 'K': // EL
			screen_clear_columns(parser);
			break;

		default:
			// This is not a sequence we handle.
			break;
	}
}

// screen_parse_dec_csi_command
static void
screen_parse_dec_csi_command(vtparse_t *parser, uint8_t c)
{
	// We don't handle most of these, but DECCOLM has the side-effect of
	// reinitializing the screen, and we need that to pass vttest.
	//
	// Similarly, we need to support "origin mode".  That one is important
	// on Linux, because vim uses scroll regions.
	//
	// We need exactly one parameter, in order to process this.
	if(parser->num_params != 1) {
		return;
	}

	switch(parser->params[0]) {
		case 3: // DECCOLM
			// Sets the number of columns, but we don't support 132-column mode,
			// so we don't care if the last character is "l" or 'h'.
			//
			// Instead, we just reset everything.
			screen_initialize(0);
			break;

		case 6: // DECOM
			// Sets the origin mode.  'h' means relative origin, and
			// 'l' means absolute origin.
			if(c == 'l') {
				screen_origin_mode = 0;
			} else if(c == 'h') {
				screen_origin_mode = 1;
			}
			break;

		case 7: // DECAWM
			// Sets autowrap mode.  'h' means autowrap is on, and 'l'
			// means autowrap is off.
			if(c == 'h') {
				screen_autowrap_mode = 1;
			} else if(c == 'l') {
				screen_autowrap_mode = 0;
			}
			screen_col79_flag = 0;
			break;

		default:
			// This is not a sequence we handle.
			break;
	}

	return;
}

// screen_handle_bs - handle a backspace
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

// screen_handle_ht - handle a horizontal tab
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

// screen_send_primary_device_attributes Esc [ c
static void
screen_send_primary_device_attributes()
{
	// This is a request for our attributes.  Claim that we are a VT100.
	uart_transmit_string("[?1;0c", UART_WAIT);
}

// screen_move_cursor_numeric - ESC [ H or ESC [ f
static void
screen_move_cursor_numeric(vtparse_t *parser)
{
	int digits0 = parser->params[0];
	int digits1 = parser->params[1];

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
}

// Send a number out the uart as a base-10 string.
// We use this for position reports, so we don't
// need much range.
#define NUM_PLACES 3
static void
screen_num_to_uart(int n)
{
	int i;
	int suppress;
	int result[NUM_PLACES];

	// Work from right to left, extracting digits from n.
	for(i = (NUM_PLACES - 1); i >= 0; i--) {
		// Get this digit.
		result[i] = n % 10;

		// Divide n by 10 to move to the next place.
		n /= 10;
	}

	// Work from left to right, printing digits.  We suppress
	// leading zero digits.
	//
	// If n is zero, we will print a single '0' character.
	suppress = 1;
	for(i = 0; i < NUM_PLACES; i++) {
		// If we are still suppressing, and this column contains zero, and
		// it is not the units column...
		if((suppress == 1) && (result[i] == 0) && (i != (NUM_PLACES - 1))) {
			// then drop the leading zero.
			continue;
		}

		// Send this digit out.
		uart_transmit('0' + result[i], UART_WAIT);
		
		// Once we print something, we are no longer suppressing
		// leading zeros.
		suppress = 0;
	}
}

// screen_report - ESC [ n
static void
screen_report(vtparse_t *parser)
{
	int line = screen_cursor_in_line() + 1;
	int column = screen_cursor_in_column() + 1;

	// There are various report requests, as selected by the
	// first parameter.
	switch(parser->params[0]) {
		case 6: // Cursor position report.
			uart_transmit_string("[", UART_WAIT);
			screen_num_to_uart(line);
			uart_transmit(';', UART_WAIT);
			screen_num_to_uart(column);
			uart_transmit('R', UART_WAIT);
			break;

		default:
			break;
	}
}

// screen_set_margins - ESC [ r
static void
screen_set_margins(vtparse_t *parser)
{
	int digits0 = parser->params[0];
	int digits1 = parser->params[1];

	// Special case - if parameter 0 and parameter 1 are both zero,
	// set the full range.
	//
	// Do this test first; it is the only time A = B is allowed - i.e. when
	// A and B are both zero.
	if(digits0 == 0 && digits1 == 0) {
		// Reset top margin to 0, bottom margin to 23.
		screen_dec_top_margin = 0;
		screen_dec_bottom_margin = screen_lines - 1;

		// Reset FWA and LWA+1
		screen_current_fwa = screen_base;
		screen_current_lwa_p1 = screen_end;

	} else if(digits0 < digits1) {
		// For all other cases, the top margin must be strictly less than the bottom margin.
		// Good - we can proceed.
	
		// Get top row number.  Note that row numbers are 1-based, so we have 
		// to decrement, but cannot go below zero.
		if(digits0 != 0) {
			--digits0; // Convert to 0-based.
		}

		// Set the top margin.
		screen_dec_top_margin = digits0;
		screen_current_fwa = screen_base + (screen_dec_top_margin * screen_cols);
		
		// Get bottom row number.  Note that row numbers are 1-based, so we have 
		// to decrement, but cannot go below zero.
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
}

// screen_move_cursor_up - ESC [ A
static void
screen_move_cursor_up(vtparse_t *parser)
{
	int i;
	int to_move = parser->params[0];
	volatile uint16_t *limit;
	volatile uint16_t *proposed_new_position;

	// If we are in relative mode, the upper limit depends on the scroll region.
	limit = screen_base;
	if(screen_origin_mode == 1) {
		limit = screen_base + (screen_dec_top_margin * screen_cols);
	}
	
	// A movement of 0 really means 1.
	if(to_move == 0) {
		to_move = 1;
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
}

// screen_move_cursor_down - ESC [ B
static void
screen_move_cursor_down(vtparse_t *parser)
{
	int i;
	int to_move = parser->params[0];
	volatile uint16_t *limit;
	volatile uint16_t *proposed_new_position;

	// If we are in relative mode, the lower limit depends on the scroll region.
	limit = screen_end;
	if(screen_origin_mode == 1) {
		limit = screen_end - (((screen_lines - 1) - screen_dec_bottom_margin) * screen_cols);
	}
	
	// A movement of 0 really means 1.
	if(to_move == 0) {
		to_move = 1;
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
}

// screen_move_cursor_right - ESC [ C
static void
screen_move_cursor_right(vtparse_t *parser)
{
	int to_move = parser->params[0];
	volatile uint16_t *start_of_line;
	volatile uint16_t *end_of_line;
	volatile uint16_t *proposed_new_position;

	// A movement of 0 really means 1.
	if(to_move == 0) {
		to_move = 1;
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
}

// screen_move_cursor_left - ESC [ D
static void
screen_move_cursor_left(vtparse_t *parser)
{
	int to_move = parser->params[0];
	volatile uint16_t *start_of_line;
	volatile uint16_t *proposed_new_position;

	// A movement of 0 really means 1.
	if(to_move == 0) {
		to_move = 1;
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
}

// screen_clear_rows - ESC [ J
static void
screen_clear_rows(vtparse_t *parser)
{
	volatile uint16_t *p;

	// There are several subsets:
	// 0 = erase below
	// 1 = erase above
	// 2 = erase all
	// 3 = erase all including scrollback (which we don't have)
	//
	// Linux uses ESC [ 3 J to clear the screen, so we will support it.
	switch(parser->params[0]) {
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
		case 3: // erase all including scrollback
			for(p = screen_base; p < screen_end; p++) {
				*p = 0;
			}
			break;

		default:
			break;
	}

	// Put the cursor back on screen.
	*screen_cursor_location |= null_cursor;
}

// screen_clear_columns - ESC [ K
static void
screen_clear_columns(vtparse_t *parser)
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
	switch(parser->params[0]) {
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
}

// screen_escape_in_sharp - got the first char after ESC #
static void
screen_escape_in_sharp(uint8_t c)
{
	volatile uint16_t *p;
	int i;

	switch(c) {
		case '8': // DECALN
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

	return;
}

// screen_normal_char - handle a normal printing character.
static void
screen_normal_char(uint8_t c)
{
	volatile uint16_t *p;

	// Put the character on the screen at the current position.
	// There is one tricky bit.  If the column is 0 through 78, then
	// we place the character and advance the cursor one column.
	//
	// But, if we are in column 79, and we are in autowrap mode,
	// we don't advance the cursor until we get one more character.
	// That new character goes into column 0 on the next line, with
	// scrolling if needed, and the cursor winds up in column 1.
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

	// This is the special case.  Put it on screen, and make it a cursor.  If
	// autowrap mode is on, then set a flag rather than moving the cursor.  If
	// autowrap mode is off, don't set the flag.  We'll stay locked in this row.
	*screen_cursor_location = c | null_cursor;
	if(screen_autowrap_mode) {
		screen_col79_flag = 1;
	}

	// We don't move the cursor, so we are done.
	return;
}

// screen_handler - read from the uart and update the screen
void
screen_handler()
{
	int rv;
	unsigned char c;

	if((rv = uart_receive()) != -1) {
		// We process one character at a time.
		c = rv & 0xff;
		if(c >= 0xa0) {
			c -= 0x80;
		}
		vtparse(&screen_parser, &c, 1);
	}

	return;
}

static void
screen_control_char(uint8_t c)
{
	// For now, we are just handling a few C0 controls.
	switch(c) {
		case char_bs:
			// Backspace
			screen_handle_bs();
			break;

		case char_ht:
			// Horizontal tab
			screen_handle_ht();
			break;

		case char_lf:
			// Line feed
			screen_handle_lf();
			break;

		case char_vt:
			// Vertical tab is handled like line feed
			screen_handle_lf();
			break;

		case char_ff:
			// Form feed is handled like line feed
			screen_handle_lf();
			break;

		case char_cr:
			// Carriage return
			screen_handle_cr();
			break;

		default:
			break;
	}
}

static void
screen_simple_escape(uint8_t c)
{
	switch(c) {
		case '7': // DECSC
			screen_save_cursor_position();
			break;

		case '8': // DECRC
			screen_restore_cursor_position();
			break;

		case 'D': // IND
			screen_handle_esc_lf();
			break;

		case 'E': // NEL
			screen_handle_esc_cr_lf();
			break;

		case 'M': // RI
			screen_handle_reverse_scroll();
			break;

		case 'c': // RIS
			screen_initialize(1);
			break;

		default:
			// No idea what to do with this case.
			break;
	}
}

static void
screen_csi_escape(vtparse_t *parser, uint8_t c)
{
	// The only intermediate character we expect here is '?'.
	switch(parser->num_intermediate_chars) {
		case 0:
			// These are ANSI escapes.
			screen_parse_ansi_csi_command(parser, c);
			break;

		case 1:
			// Handle a DEC private '?' sequence.  Ignore other
			// intermediate characters.
			if(parser->intermediate_chars[0] == '?') {
				screen_parse_dec_csi_command(parser, c);
			}
			break;

		default:
			// No idea what to do with this case.
			break;
	}
}

static void
screen_non_csi_escape(vtparse_t *parser, uint8_t c)
{
	// The only intermediate character we expect here is '#'.
	switch(parser->num_intermediate_chars) {
		case 0:
			// These are generally single-character escapes.
			screen_simple_escape(c);
			break;

		case 1:
			// Handle a sharp sequence.  Ignore other
			// intermediate characters.
			if(parser->intermediate_chars[0] == '#') {
				screen_escape_in_sharp(c);
			}
			break;

		default:
			// No idea what to do with this case.
			break;
	}
}

static void
screen_parser_callback(
		vtparse_t		*parser,
		vtparse_action_t	action,
		unsigned char		c
		)
{
	switch(action) {
		// Some states are handled internally by the parser.  These
		// are the only ones that are sent to this callback.
		case VTPARSE_ACTION_PRINT:
			// Normal character to be printed on the screen.
			screen_normal_char(c);
			break;

		case VTPARSE_ACTION_EXECUTE:
			// This is a C0 or C1 (control) character.
			screen_control_char(c);
			break;

		case VTPARSE_ACTION_CSI_DISPATCH:
			// This is an escape sequence of the CSI type.
			screen_csi_escape(parser, c);
			break;

		case VTPARSE_ACTION_ESC_DISPATCH:
			// This is a non-CSI escape sequence.
			screen_non_csi_escape(parser, c);
			break;

		case VTPARSE_ACTION_HOOK:
		case VTPARSE_ACTION_PUT:
		case VTPARSE_ACTION_UNHOOK:
			// These are associated with DCS, which we don't implement.
			break;

		case VTPARSE_ACTION_OSC_START:
		case VTPARSE_ACTION_OSC_PUT:
		case VTPARSE_ACTION_OSC_END:
			// These are associated with OSC, which we don't implement.
			break;

		case VTPARSE_ACTION_ERROR:
		default:
			// Not sure what to do here yet.
			break;
	}
}
