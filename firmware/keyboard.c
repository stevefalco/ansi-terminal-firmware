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
#define keyboard_base		(0xc040)
#define keyboard_SCAN_CODE	(*(volatile uint8_t *)(keyboard_base + 0x00))	// Scan Code register
#define keyboard_STATUS		(*(volatile uint8_t *)(keyboard_base + 0x02))	// Status register

// Keyboard register bits

// STATUS
#define keyboard_Interrupt_b	(0)						// Interrupt received

#define keyboard_Interrupt_v	(1 << keyboard_Interrupt_b)

#define keyboard_depth		(128)						// Buffer depth.

#define KB_NORMAL		(0)
#define KB_NORMAL_GOING_UP	(1)
#define KB_EXTENSION		(2)
#define KB_EXTENSION_GOING_UP	(3)
static int keyboard_state;

static uint8_t keyboard_rb[keyboard_depth];
static int keyboard_rb_input;
static int keyboard_rb_output;
static int keyboard_rb_count;

#define KEY_NOT_FOUND		(0xff)
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
// This runs from the interrupt service routine with interrupts disabled.
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

// Non-ASCII scan codes.  I haven't bothered with the keypad, because my keyboards
// don't have one.  But they would be easy enough to add.
#define CAPS_LOCK	0x58
#define L_SHIFT		0x12
#define L_CTRL		0x14
#define L_GUI		0xe01f
#define L_ALT		0x11
#define R_SHIFT		0x59
#define R_CTRL		0xe014
#define R_GUI		0xe027
#define R_ALT		0xe011
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
#define KEY_UP		0xf0		// not a key - sent when a key is released
#define EXTENSION	0xe0		// first code of an extended sequence

typedef struct {
	uint8_t		ascii_value;
	uint8_t		scan_code;
} SCAN_TABLE;

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

static SCAN_TABLE scan_table_shift[] = {
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
};
#define SCAN_ELEMENTS_CONTROL (sizeof(scan_table_control) / sizeof(SCAN_TABLE))

// Do a linear search through our scan table, looking for an entry with
// the right code and extension flags.
static uint8_t
keyboard_find(uint8_t scan_code)
{
	int i;
	int limit;
	SCAN_TABLE *p;
	SCAN_TABLE *q;

	i = sizeof(SCAN_TABLE);

	switch(keyboard_modifiers) {
		case NO_FLAG:
			p = scan_table_no_modifiers;
			limit = SCAN_ELEMENTS_NO_MODIFIERS;
			break;

		case SHIFT_FLAG:
			p = scan_table_shift;
			limit = SCAN_ELEMENTS_SHIFT;
			break;

		// Control overrides shift, meaning that we effectively
		// ignore shift if control is active.
		case CONTROL_FLAG:
		case CONTROL_FLAG | SHIFT_FLAG:
			p = scan_table_control;
			limit = SCAN_ELEMENTS_CONTROL;
			break;

		default: // Unhandled modifier.
			return KEY_NOT_FOUND;

	}

	for(i = 0; i < limit; i++) {
		q = p + i;
		if(scan_code == q->scan_code) {
			return q->ascii_value;
		}
	}

	return KEY_NOT_FOUND;
}

// State machine to respond to scan codes.  We have to handle both
// key down (make) and key up (break) events so we can correctly
// process control / shift / alt modifiers.
static void
keyboard_decode(uint8_t scan_code)
{
	uint8_t c;

	//dump("scan code", scan_code);

	// Figure out what we got.
	switch(keyboard_state) {
		case KB_NORMAL:
			switch(scan_code) {
				case EXTENSION: // starting extended sequence
					keyboard_state = KB_EXTENSION;
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

				case F1:
					uart_transmit_string("OP");
					break;

				case F2:
					uart_transmit_string("OQ");
					break;

				case F3:
					uart_transmit_string("OR");
					break;

				case F4:
					uart_transmit_string("OS");
					break;

				case F5:
					uart_transmit_string("[15~");
					break;

				case F6:
					uart_transmit_string("[17~");
					break;

				case F7:
					uart_transmit_string("[18~");
					break;

				case F8:
					uart_transmit_string("[19~");
					break;

				case F9:
					uart_transmit_string("[20~");
					break;

				case F10:
					uart_transmit_string("[21~");
					break;

				case F11:
					uart_transmit_string("[22~");
					break;

				case F12:
					uart_transmit_string("[23~");
					break;

					// Everything else can be looked up in the ASCII table.
				default:
					c = keyboard_find(scan_code);
					if(c != KEY_NOT_FOUND) {
						uart_transmit(c);
					}
					break;
			}
			break;

		case KB_EXTENSION:
			switch(scan_code) {
				case KEY_UP: // starting key-up sequence
					keyboard_state = KB_EXTENSION_GOING_UP;
					return;

				case INSERT & 0xff:
					uart_transmit_string("[2~");
					break;

				case HOME & 0xff:
					uart_transmit_string("[H");
					break;

				case PG_UP & 0xff:
					uart_transmit_string("[5~");
					break;

				case DELETE & 0xff:
					uart_transmit(0x7f);
					break;

				case END & 0xff:
					uart_transmit_string("OF");
					break;

				case PG_DOWN & 0xff:
					uart_transmit_string("[6~");
					break;

				case U_ARROW & 0xff:
					uart_transmit_string("OA");
					break;

				case D_ARROW & 0xff:
					uart_transmit_string("OB");
					break;

				case R_ARROW & 0xff:
					uart_transmit_string("OC");
					break;

				case L_ARROW & 0xff:
					uart_transmit_string("OD");
					break;

				case R_CTRL & 0xff:
					keyboard_modifiers |= CONTROL_FLAG;
					break;

				case R_ALT & 0xff:
					keyboard_modifiers |= ALT_FLAG;
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

		case KB_EXTENSION_GOING_UP:
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
	int rv;
	uint8_t scan_code;

	asm(" ori.w #0x0700, %sr");	// Mask interrupts

	// Assume nothing available.
	rv = 0;

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

		// Decode it.
		keyboard_decode(scan_code);
	}

	asm(" andi.w #~0x0700, %sr");	// Unmask interrupts

	return rv;
}
