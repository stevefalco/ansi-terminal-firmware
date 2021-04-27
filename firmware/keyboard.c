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

// Keyboard driver.  We receive interrupts, and then store incoming ASCII
// keystrokes in a circular buffer.  We are also called periodically by
// the main loop, and we transmit any characters in the circular buffer
// out via the uart.

#include "keyboard.h"
#include "uart.h"
#include "debug.h"

// Keyboard registers
#define keyboard_base			(0xc040)
#define keyboard_SCAN_CODE		(*(volatile uint8_t *)(keyboard_base + 0x00))	// Scan Code register
#define keyboard_STATUS			(*(volatile uint8_t *)(keyboard_base + 0x02))	// Status register

// Keyboard register bits

// STATUS
#define keyboard_Interrupt_b		(0)						// Interrupt received

#define keyboard_Interrupt_v		(1 << keyboard_Interrupt_b)

#define keyboard_depth			(128)						// Buffer depth.

#define KB_NORMAL			(0)
#define KB_NORMAL_GOING_UP		(1)
#define KB_EXTENSION_E0			(2)
#define KB_EXTENSION_E0_GOING_UP	(3)
#define KB_EXTENSION_E1			(4)
#define KB_EXTENSION_E1_GOT_BREAK_1	(5)
#define KB_EXTENSION_E1_GOING_UP	(6)
static int keyboard_state;

static uint8_t keyboard_rb[keyboard_depth];
static int keyboard_rb_input;
static int keyboard_rb_output;
static int keyboard_rb_count;

static int keyboard_modifiers;

// keyboard_initialize - get the keyboard ready
void
keyboard_initialize()
{
	// Clear the scan code receive buffer.
	keyboard_rb_input = 0;
	keyboard_rb_output = 0;
	keyboard_rb_count = 0;

	// Reset the state machine.
	keyboard_state = KB_NORMAL;
}

// keyboard_test_interrupt - see if the keyboard has posted an interrupt
//
// This runs from the interrupt service routine with interrupts disabled,
// so we want to be quick.
void
keyboard_test_interrupt()
{
	uint8_t scan_code;

	while(1) {
		// Read the status register to see if this interrupt is for us.
		// Bit 0 = 1 indicates a new character is available.
		if(!(keyboard_STATUS & keyboard_Interrupt_v)) {
			return;
		}

		// It is for us.  Get the scan code.
		scan_code = keyboard_SCAN_CODE;

		// Store the scan code if there is room.
		if(keyboard_rb_count < keyboard_depth) {
			keyboard_rb[keyboard_rb_input] = scan_code;

			// One more now available.
			++keyboard_rb_count;

			// Move the input pointer, keeping it in range.
			keyboard_rb_input = (keyboard_rb_input + 1) & (keyboard_depth - 1);
		}
	}
}

// Extension flag bits
#define NO_FLAG		0x00
#define SHIFT_FLAG	0x01
#define CONTROL_FLAG	0x02
#define ALT_FLAG	0x04
#define CAPS_LOCK_FLAG	0x08
#define NUM_LOCK_FLAG	0x10

// Non-ASCII scan codes.
#define CAPS_LOCK	0x58
#define NUM_LOCK	0x77		// Scan code shared with BREAK_2
#define L_SHIFT		0x12
#define L_CTRL		0x14		// Scan code shared with BREAK_1
#define L_GUI		0xe01f
#define L_ALT		0x11
#define R_SHIFT		0x59
#define R_CTRL		0xe014
#define R_GUI		0xe027
#define R_ALT		0xe011
#define BREAK_1		0x14		// Scan code shared with L_CTRL
#define BREAK_2		0x77		// Scan code shared with NUM_LOCK
#define F1		0x05
#define F2		0x06
#define F3		0x04
#define F4		0x0c
#define F5		0x03
#define F6		0x0b
#define F7		0x83
#define F8		0x0a
#define F9		0x01
#define F10		0x09
#define F11		0x78
#define F12		0x07
#define SCROLL_LOCK	0x7e
#define INSERT		0xe070
#define HOME		0xe06c
#define PG_UP		0xe07d
#define DELETE		0xe071
#define END		0xe069
#define PG_DOWN		0xe07a
#define U_ARROW		0xe075
#define L_ARROW		0xe06b
#define D_ARROW		0xe072
#define R_ARROW		0xe074
#define NUM_DIVIDE	0xe04a
#define NUM_ENTER	0xe05a
#define KEY_UP		0xf0		// not a key - sent when a key is released
#define EXTENSION_E0	0xe0		// first code of an extended E0 sequence
#define EXTENSION_E1	0xe1		// first code of an extended E1 sequence

// Some scan_codes send a single ascii byte.  We keep them separated
// from the scan_codes that send strings, for efficiency.
typedef struct {
	uint8_t		ascii_value;
	uint8_t		scan_code;
} SCAN_TABLE;

// Some scan_codes send a string.   We keep them separated
// from the scan_codes that send single ascii bytes, for efficiency.
typedef struct {
	char		*pString;
	uint8_t		scan_code;
} STRING_TABLE;

// Normal characters.  No modifiers, no strings, no extensions.
static SCAN_TABLE scan_table_no_modifiers[] = {
	{ ' ',  0x29 }, // SPACE BAR
	{ 0x08, 0x66 },	// BACKSPACE
	{ 0x09, 0x0d },	// TAB
	{ 0x0d, 0x5a },	// ENTER
	{ 0x1b, 0x76 },	// ESCAPE
	{ 'a',  0x1c },
	{ 'b',  0x32 },
	{ 'c',  0x21 },
	{ 'd',  0x23 },
	{ 'e',  0x24 },
	{ 'f',  0x2b },
	{ 'g',  0x34 },
	{ 'h',  0x33 },
	{ 'i',  0x43 },
	{ 'j',  0x3b },
	{ 'k',  0x42 },
	{ 'l',  0x4b },
	{ 'm',  0x3a },
	{ 'n',  0x31 },
	{ 'o',  0x44 },
	{ 'p',  0x4d },
	{ 'q',  0x15 },
	{ 'r',  0x2d },
	{ 's',  0x1b },
	{ 't',  0x2c },
	{ 'u',  0x3c },
	{ 'v',  0x2a },
	{ 'w',  0x1d },
	{ 'x',  0x22 },
	{ 'y',  0x35 },
	{ 'z',  0x1a },
	{ '0',  0x45 },
	{ '1',  0x16 },
	{ '2',  0x1e },
	{ '3',  0x26 },
	{ '4',  0x25 },
	{ '5',  0x2e },
	{ '6',  0x36 },
	{ '7',  0x3d },
	{ '8',  0x3e },
	{ '9',  0x46 },
	{ '-',  0x4e },
	{ '=',  0x55 },
	{ '\\', 0x5d },
	{ '`',  0x0e },
	{ '[',  0x54 },
	{ ']',  0x5b },
	{ ';',  0x4c },
	{ '\'', 0x52 },
	{ ',',  0x41 },
	{ '.',  0x49 },
	{ '/',  0x4a },
};
#define SCAN_ELEMENTS_NO_MODIFIERS (sizeof(scan_table_no_modifiers) / sizeof(SCAN_TABLE))

// Shifted characters.
static SCAN_TABLE scan_table_shift[] = {
	{ ' ',  0x29 }, // SPACE BAR
	{ 0x08, 0x66 },	// BACKSPACE
	{ 0x09, 0x0d },	// TAB
	{ 0x0d, 0x5a },	// ENTER
	{ 0x1b, 0x76 },	// ESCAPE
	{ 'A',  0x1c },
	{ 'B',  0x32 },
	{ 'C',  0x21 },
	{ 'D',  0x23 },
	{ 'E',  0x24 },
	{ 'F',  0x2b },
	{ 'G',  0x34 },
	{ 'H',  0x33 },
	{ 'I',  0x43 },
	{ 'J',  0x3b },
	{ 'K',  0x42 },
	{ 'L',  0x4b },
	{ 'M',  0x3a },
	{ 'N',  0x31 },
	{ 'O',  0x44 },
	{ 'P',  0x4d },
	{ 'Q',  0x15 },
	{ 'R',  0x2d },
	{ 'S',  0x1b },
	{ 'T',  0x2c },
	{ 'U',  0x3c },
	{ 'V',  0x2a },
	{ 'W',  0x1d },
	{ 'X',  0x22 },
	{ 'Y',  0x35 },
	{ 'Z',  0x1a },
	{ '!',  0x16 },
	{ '@',  0x1e },
	{ '#',  0x26 },
	{ '$',  0x25 },
	{ '%',  0x2e },
	{ '^',  0x36 },
	{ '&',  0x3d },
	{ '*',  0x3e },
	{ '(',  0x46 },
	{ ')',  0x45 },
	{ '_',  0x4e },
	{ '+',  0x55 },
	{ '|',  0x5d },
	{ '~',  0x0e },
	{ '{',  0x54 },
	{ '}',  0x5b },
	{ ':',  0x4c },
	{ '"',  0x52 },
	{ '<',  0x41 },
	{ '>',  0x49 },
	{ '?',  0x4a },
};
#define SCAN_ELEMENTS_SHIFT (sizeof(scan_table_shift) / sizeof(SCAN_TABLE))

// Control characters.
static SCAN_TABLE scan_table_control[] = {
	{ 0x00, 0x29 },	// ^SPACE
	{ 0x00, 0x1e },	// ^2
	{ 0x01, 0x1c },	// ^A
	{ 0x02, 0x32 },	// ^B
	{ 0x03, 0x21 },	// ^C
	{ 0x04, 0x23 },	// ^D
	{ 0x05, 0x24 },	// ^E
	{ 0x06, 0x2b },	// ^F
	{ 0x07, 0x34 },	// ^G
	{ 0x08, 0x33 },	// ^H
	{ 0x09, 0x43 },	// ^I
	{ 0x0a, 0x3b },	// ^J
	{ 0x0b, 0x42 },	// ^K
	{ 0x0c, 0x4b },	// ^L
	{ 0x0d, 0x3a },	// ^M
	{ 0x0e, 0x31 },	// ^N
	{ 0x0f, 0x44 },	// ^O
	{ 0x10, 0x4d },	// ^P
	{ 0x11, 0x15 },	// ^Q
	{ 0x12, 0x2d },	// ^R
	{ 0x13, 0x1b },	// ^S
	{ 0x14, 0x2c },	// ^T
	{ 0x15, 0x3c },	// ^U
	{ 0x16, 0x2a },	// ^V
	{ 0x17, 0x1d },	// ^W
	{ 0x18, 0x22 },	// ^X
	{ 0x19, 0x35 },	// ^Y
	{ 0x1a, 0x1a },	// ^Z
	{ 0x1b, 0x54 },	// ^[
	{ 0x1c, 0x5d },	// ^BACKSLASH
	{ 0x1d, 0x5b },	// ^]
	{ 0x1e, 0x36 },	// ^6
	{ 0x1e, 0x0e }, // ^`
	{ 0x1f, 0x4e },	// ^-
	{ 0x1f, 0x4a },	// ^/
	{ 0x08, 0x66 },	// BACKSPACE
	{ 0x09, 0x0d },	// TAB
	{ 0x0d, 0x5a },	// ENTER
	{ 0x1b, 0x76 },	// ESCAPE
};
#define SCAN_ELEMENTS_CONTROL (sizeof(scan_table_control) / sizeof(SCAN_TABLE))

// Numeric pad, while NUM_LOCK is engaged.  Single characters, no extensions.
//
// Note that '/' and ENTER are not here, because they have an 0xE0 prefix.
static SCAN_TABLE scan_table_num_pad_num_lock[] = {
	{ '0',  0x70 },
	{ '1',  0x69 },
	{ '2',  0x72 },
	{ '3',  0x7a },
	{ '4',  0x6b },
	{ '5',  0x73 },
	{ '6',  0x74 },
	{ '7',  0x6c },
	{ '8',  0x75 },
	{ '9',  0x7d },
	{ '.',  0x71 },
	{ '+',  0x79 },
	{ '-',  0x7b },
	{ '*',  0x7c },
};
#define SCAN_ELEMENTS_NUM_PAD_NUM_LOCK (sizeof(scan_table_num_pad_num_lock) / sizeof(SCAN_TABLE))

// Numeric pad, without NUM_LOCK:  All send strings.  A few don't really
// need strings, like 5, +, etc, but it is simpler to handle them all
// the same way.
static STRING_TABLE string_table_num_pad_no_num_lock[] = {
	{ "[2~",  0x70 }, // INSERT
	{ "OF",   0x69 }, // END
	{ "OB",   0x72 }, // D_ARROW
	{ "[6~",  0x7a }, // PG_DOWN
	{ "OD",   0x6b }, // L_ARROW
	{ "5",      0x73 }, // 5
	{ "OC",   0x74 }, // R_ARROW
	{ "[H",   0x6c }, // HOME
	{ "OA",   0x75 }, // U_ARROW
	{ "[5~",  0x7d }, // PG_UP
	{ "\x7f",   0x71 }, // DELETE
	{ "+",      0x79 }, // +
	{ "-",      0x7b }, // -
	{ "*",      0x7c }, // *
};
#define STRING_ELEMENTS_NUM_PAD_NO_NUM_LOCK (sizeof(string_table_num_pad_no_num_lock) / sizeof(STRING_TABLE))

// These are the scan_codes that are prefixed with the 0xE0 extension.
// They mostly result in strings, but a few don't.  We handle them all
// together for simplicity.
static STRING_TABLE string_table_e0[] = {
	{ "[2~",	INSERT		& 0xff },
	{ "[H",	HOME		& 0xff },
	{ "[5~",	PG_UP		& 0xff },
	{ "OF",	END		& 0xff },
	{ "[6~",	PG_DOWN		& 0xff },
	{ "OA",	U_ARROW		& 0xff },
	{ "OB",	D_ARROW		& 0xff },
	{ "OC",	R_ARROW		& 0xff },
	{ "OD",	L_ARROW		& 0xff },
	{ "/",		NUM_DIVIDE	& 0xff },
	{ "\r",		NUM_ENTER	& 0xff },
	{ "\x7f",	DELETE		& 0xff },
};
#define STRING_ELEMENTS_E0 (sizeof(string_table_e0) / sizeof(STRING_TABLE))

// Function keys all send strings.
static STRING_TABLE string_table_func[] = {
	{ "OP",	F1  },
	{ "OQ",	F2  },
	{ "OR",	F3  },
	{ "OS",	F4  },
	{ "[15~",	F5  },
	{ "[17~",	F6  },
	{ "[18~",	F7  },
	{ "[19~",	F8  },
	{ "[20~",	F9  },
	{ "[21~",	F10 },
	{ "[22~",	F11 },
	{ "[23~",	F12 },
};
#define STRING_ELEMENTS_FUNC (sizeof(string_table_func) / sizeof(STRING_TABLE))

// Do a linear search through the given table, looking for an entry with
// the right scan_code.
//
// Return 1 if found, 0 if not found.
static int
keyboard_search_table(
		uint8_t		scan_code,
		SCAN_TABLE	*pTable,
		int		limit
		)
{
	int i;

	for(i = 0; i < limit; i++) {
		if(scan_code == pTable[i].scan_code) {
			uart_transmit(pTable[i].ascii_value, UART_WAIT);
			return 1;
		}
	}

	return 0;
}

// Do a linear search through the given table, looking for an entry with
// the right scan_code.
//
// Return 1 if found, 0 if not found.
static int
keyboard_search_string(
		uint8_t		scan_code,
		STRING_TABLE	*pTable,
		int		limit
		)
{
	int i;

	for(i = 0; i < limit; i++) {
		if(scan_code == pTable[i].scan_code) {
			uart_transmit_string(pTable[i].pString, UART_WAIT);
			return 1;
		}
	}

	return 0;
}

// Do a linear search through the various scan tables, looking for an
// entry with the right code and extension flags.
static void
keyboard_find_scan(uint8_t scan_code)
{
	int limit;
	SCAN_TABLE *p;

	// We first deal with the most common keys: alphabetic, numeric, control.
	//
	// First, figure out which table to search, based on the modifiers.
	switch(keyboard_modifiers & (SHIFT_FLAG | CONTROL_FLAG | CAPS_LOCK_FLAG)) {
		// Shift reverses Caps Lock.  In other words, if Caps Lock
		// is on, then the shift key brings you back to the unshifted
		// state.  If Caps Lock is off, then the shift key selects the
		// shifted state.
		case NO_FLAG:
		case CAPS_LOCK_FLAG | SHIFT_FLAG:
			p = scan_table_no_modifiers;
			limit = SCAN_ELEMENTS_NO_MODIFIERS;
			break;

		case SHIFT_FLAG:
		case CAPS_LOCK_FLAG:
			p = scan_table_shift;
			limit = SCAN_ELEMENTS_SHIFT;
			break;

		// Control overrides shift, meaning that we effectively
		// ignore shift if control is active.  The same is true
		// for caps lock.
		case CONTROL_FLAG:
		case CONTROL_FLAG | SHIFT_FLAG:
		case CONTROL_FLAG | CAPS_LOCK_FLAG:
		case CONTROL_FLAG | SHIFT_FLAG | CAPS_LOCK_FLAG:
			p = scan_table_control;
			limit = SCAN_ELEMENTS_CONTROL;
			break;

		default: // Unhandled modifier.
			return;
	}

	// Search the chosen table.  Again, these are the most common single
	// ASCII characters.
	if(keyboard_search_table(scan_code, p, limit)) {
		// The code was found, and it has been transmitted; we are
		// done.
		return;
	}

	// The code was not found above, but it might be a function key.
	// We keep those separate because they all send strings.
	if(keyboard_search_string(scan_code, string_table_func, STRING_ELEMENTS_FUNC)) {
		// The code was found, and the string has been transmitted;
		// we are done.
		return;
	}

	// The code was not found above, but it might be on the numeric
	// pad.  We keep those separate, because they either send a single
	// character or a string, mostly depending on the NUM_LOCK state.
	//
	// This is the last chance for this scan_code.
	if(keyboard_modifiers & NUM_LOCK) {
		// Try for single characters.
		keyboard_search_table(
				scan_code,
				scan_table_num_pad_num_lock,
				SCAN_ELEMENTS_NUM_PAD_NUM_LOCK);
	} else {
		// Try for strings.
		keyboard_search_string(
				scan_code,
				string_table_num_pad_no_num_lock,
				STRING_ELEMENTS_NUM_PAD_NO_NUM_LOCK);
	}

	return;
}

// State machine to respond to scan codes.  We have to handle both
// key down (make) and key up (break) events so we can correctly
// process control / shift / alt modifiers.
static void
keyboard_decode(uint8_t scan_code)
{
	//dump("scan code", scan_code);

	// Figure out what we got.
	switch(keyboard_state) {
		case KB_NORMAL:
			switch(scan_code) {
				case EXTENSION_E0: // starting extended 0xE0 sequence
					keyboard_state = KB_EXTENSION_E0;
					return;

				case EXTENSION_E1: // starting extended 0xE1 sequence
					keyboard_state = KB_EXTENSION_E1;
					return;

				case KEY_UP: // starting key-up sequence
					keyboard_state = KB_NORMAL_GOING_UP;
					return;

				case L_CTRL:
					keyboard_modifiers |= CONTROL_FLAG;
					break;

				case L_ALT:
					keyboard_modifiers |= ALT_FLAG;
					break;

				case L_SHIFT:
				case R_SHIFT:
					keyboard_modifiers |= SHIFT_FLAG;
					break;

				case CAPS_LOCK:
					if(keyboard_modifiers & CAPS_LOCK_FLAG) {
						// CAPS_LOCK is on.  Turn it off.
						keyboard_modifiers &= ~CAPS_LOCK_FLAG;
					} else {
						// CAPS_LOCK is off.  Turn it on.
						keyboard_modifiers |= CAPS_LOCK_FLAG;
					}
					break;

				case NUM_LOCK:
					if(keyboard_modifiers & NUM_LOCK_FLAG) {
						// NUM_LOCK is on.  Turn it off.
						keyboard_modifiers &= ~NUM_LOCK_FLAG;
					} else {
						// NUM_LOCK is off.  Turn it on.
						keyboard_modifiers |= NUM_LOCK_FLAG;
					}
					break;

				default:
					// Everything else can be looked up in a table.
					//
					// We will try several tables in turn, until
					// we find the scan_code, or run out of
					// possibilities.
					keyboard_find_scan(scan_code);
					break;
			}
			break;

		case KB_EXTENSION_E0:
			switch(scan_code) {
				case KEY_UP: // starting key-up sequence
					keyboard_state = KB_EXTENSION_E0_GOING_UP;
					return;

				case R_CTRL & 0xff:
					keyboard_modifiers |= CONTROL_FLAG;
					break;

				case R_ALT & 0xff:
					keyboard_modifiers |= ALT_FLAG;
					break;

				default:
					// Everything else can be looked up in the E0 table.
					keyboard_search_string(
							scan_code,
							string_table_e0,
							STRING_ELEMENTS_E0);
					break;
			}
			keyboard_state = KB_NORMAL;
			break;

		case KB_EXTENSION_E1:
			switch(scan_code) {
				// There is not much here - we are really just trying
				// to detect a BREAK key.
				//
				// This one is hard...  The complete scan_code sequence
				// for the BREAK key is:
				//
				// 0xE1 0x14 0x77 0xE1 0xF0 0x14 0xF0 0x77
				//
				// where the first three scan_codes are: extension code
				// 0xE1, then L_CTRL and NUM_LOCK.  The last five
				// scan_codes are extension code 0xE1, followed by
				// KEY_UP for the L_CTRL and NUM_LOCK.
				//
				// I've aliased L_CTRL to BREAK_1, and NUM_LOCK to
				// BREAK_2.  Perhaps that makes things a bit more
				// readable.

				case KEY_UP: // starting key-up sequence
					keyboard_state = KB_EXTENSION_E1_GOING_UP;
					return;

				case BREAK_1:
					// So far, we've seen 0xE1 0x14.  Move to the
					// KB_EXTENSION_E1_GOT_BREAK_1 state, where
					// we expect to get the BREAK_2 code.
					//
					// Note that all 8 scan_codes are sent when the BREAK
					// key is initially pressed.  This is different from
					// every other key, where the KEY_UP part comes when
					// the key is released.  There is no way to detect when
					// the BREAK key is released.
					keyboard_state = KB_EXTENSION_E1_GOT_BREAK_1;
					return;

				default:
					// If we get anything else, this sequence is bad.
					break;
			}
			keyboard_state = KB_NORMAL;
			break;

		case KB_EXTENSION_E1_GOT_BREAK_1:
			switch(scan_code) {
				case BREAK_2:
					// We've got the BREAK_2 code.  Start sending BREAK.
					//
					// Note that BREAK is 100 ms long, so a timer is used
					// to stop sending BREAK.
					uart_start_break();
					break;

				default:
					break;
			}
			keyboard_state = KB_NORMAL;
			break;

		case KB_EXTENSION_E1_GOING_UP:
			switch(scan_code) {
				case BREAK_1:
					// We've gotten the KEY_UP of the BREAK_1 scan_code.
					// We prefer to go back to the KB_EXTENSION_E1 state,
					// because we are still expecting a KEY_UP of the
					// BREAK_2 scan_code, and we won't get another 0xE1.
					//
					// We could just go back to KB_NORMAL, since it would
					// discard the remaining KEY_UP, but this is slightly
					// cleaner.
					keyboard_state = KB_EXTENSION_E1;
					return;

				case BREAK_2:
					// We've gotten the KEY_UP of the BREAK_2 scan code.
					//
					// This is the final scan_code of the sequence.  There
					// is nothing further to do.
					break;

				default:
					break;
			}
			keyboard_state = KB_NORMAL;
			break;

		case KB_NORMAL_GOING_UP:
			// I don't really care what the key going up is,
			// unless it is a modifier going away.
			// Dump everything else on the floor.
			switch(scan_code) {
				case L_CTRL:
					keyboard_modifiers &= ~CONTROL_FLAG;
					break;

				case L_ALT:
					keyboard_modifiers &= ~ALT_FLAG;
					break;

				case L_SHIFT:
				case R_SHIFT:
					keyboard_modifiers &= ~SHIFT_FLAG;
					break;

				default:
					break;
			}
			keyboard_state = KB_NORMAL;
			break;

		case KB_EXTENSION_E0_GOING_UP:
			// I don't really care what the key going up is,
			// unless it is a modifier going away.
			// Dump everything else on the floor.
			switch(scan_code) {
				case R_CTRL & 0xff:
					keyboard_modifiers &= ~CONTROL_FLAG;
					break;

				case R_ALT & 0xff:
					keyboard_modifiers &= ~ALT_FLAG;
					break;

				default:
					break;
			}
			keyboard_state = KB_NORMAL;
			break;

		default:
			break;
	}
}

// keyboard_handler - process any keystrokes we may have received.
//
// Return 0 if nothing available, for use by our screen-saver.
// Return 1 if we processed a new scan code.
int
keyboard_handler()
{
	// Assume nothing available.
	int rv = 0;

	// I shouldn't need to initialize scan_code here, because rv != 0 protects
	// the call to keyboard_decode().  But gcc gives an "uninitialized variable"
	// warning.
	uint8_t scan_code = 0;

	asm(" ori.w #0x0700, %sr");	// Mask interrupts

	// See if there is anything waiting to be processed.
	if(keyboard_rb_count != 0) {
		// We have a new scan code.  Flag it for use by the screensaver
		// timeout logic.  Note that just pressing "shift" or "control"
		// will wake the screensaver, and that is exactly the behavior
		// that we want.
		rv = 1;

		// Get the scan code.
		scan_code = keyboard_rb[keyboard_rb_output];

		// One less now available.
		--keyboard_rb_count;

		// Move the output pointer, keeping it in range.
		keyboard_rb_output = (keyboard_rb_output + 1) & (keyboard_depth - 1);
	}

	asm(" andi.w #~0x0700, %sr");	// Unmask interrupts

	// We want to do the decode outside of the interrupt mask, because this process
	// can be slow, especially if we have to wait for the uart when sending a
	// keystroke.
	if(rv != 0) {
		// Decode it.
		keyboard_decode(scan_code);
	}

	return rv;
}
