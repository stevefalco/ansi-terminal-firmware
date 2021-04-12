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

static volatile uint16_t *screen_base = (volatile uint16_t *)(0x8000);

static uint16_t	screen_cursor_location;		// Pointer into video memory.
static uint16_t	screen_cursor_location_save;	// A place to save the cursor for ESC-7 and ESC-8
static uint16_t	screen_group_pointer;		// Pointer into the group that we are accumulating digits for.
static uint16_t	screen_current_fwa;		// FWA changes with scroll region
static uint16_t	screen_current_lwa_p1;		// LWA+1 changes with scroll region
static uint8_t	screen_escape_state;		// State machine variable.
static uint8_t	screen_group_0_digits;		// Group 0 accumulated digits.
static uint8_t	screen_group_1_digits;		// Group 1 accumulated digits.
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
#if 0
	ld	hl, screen_base
	ld	bc, screen_length
screen_initialize_loop:
	ld	(hl), 0
	inc	hl
	dec	bc
	ld	a, b
	or	c
	jr	NZ, screen_initialize_loop

	// Initialize the cursor pointer.
	ld	hl, screen_base
	ld	(screen_cursor_location), hl
	ld	(screen_cursor_location_save), hl
	set	7, (hl)

	// Not handling an escape sequence.
	ld	a, escape_none_state
	ld	(screen_escape_state), a
	ld	(screen_group_0_digits), a
	ld	(screen_group_1_digits), a
	ld	hl, screen_group_0_digits	// Pointer to the group_0 buffer
	ld	(screen_group_pointer), hl	// Save the pointer

	// Clear the column 79 and DEC flags.
	xor	a
	ld	(screen_col79_flag), a		// Clear the col 79 flag
	ld	(screen_dec_flag), a		// Clear the DEC flag

	// Top margin starts out as 0, bottom margin starts out as 23.
	//
	// A is still zero from above.
	ld	(screen_dec_top_margin), a
	ld	a, screen_lines - 1
	ld	(screen_dec_bottom_margin), a

	// Start off with the screen start and end properly set.
	ld	hl, screen_base
	ld	(screen_current_fwa), hl
	ld	hl, screen_end
	ld	(screen_current_lwa_p1), hl

	ret
#endif // 0

}

void
screen_handler()
{
	int rv;

	if((rv = uart_receive()) == -1) {
		return; // Nothing available.
	}
}
