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

// Dual-ported video memory - 1920 bytes.
#define screen_base		(0x8000)				// Physical address
#define screen_cols		(80)					// Number of columns
#define screen_lines		(24)					// Number of lines
#define screen_length		(1920)					// Length of whole screen
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

void
screen_initialize()
{
}

void
screen_handler()
{
	int rv;

	if((rv = uart_receive()) == -1) {
		return; // Nothing available.
	}
}
