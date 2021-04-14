// ANSI Terminal
//
// (c) 2021 Steven A. Falco
//
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

void
keyboard_test_interrupt()
{
	uint8_t junk;

	while(1) {
		// Read the status register to see if this interrupt is for us.
		// Bit 0 = 1 indicates a new character is available.
		if(!(keyboard_STATUS & keyboard_Interrupt_v)) {
			return;
		}

		// Store the scan code.
		if(keyboard_rb_count < keyboard_depth) {
			// There is room to store this character.
			keyboard_rb[keyboard_rb_input] = keyboard_SCAN_CODE;

			// One more now available.
			++keyboard_rb_count;

			// Move the input pointer, keeping it in range.
			keyboard_rb_input = (keyboard_rb_input + 1) & (keyboard_depth - 1);
		} else {
			// No room - just flush it.
			junk = keyboard_SCAN_CODE;
		}
	}
}

// Extension flag bits
#define SHIFT_FLAG	0x01
#define CONTROL_FLAG	0x02
#define ALT_FLAG	0x04

// Non-ASCII scan codes
#define CAPS_LOCK	0x58
#define L_SHIFT		0x12
#define L_CTRL		0x14
#define L_GUI		0xe01f
#define L_ALT		0x11
#define R_SHIFT		0x59
#define R_CTRL		0xe014
#define R_GUI		0xe027
#define R_ALT		0xe011
#define ENTER		0x5a
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
#define KEY_UP		0xf0
#define EXTENSION	0xe0

typedef struct {
	uint8_t		ascii_value;
	uint8_t		make_code;
	uint8_t		extension_flags;
} SCAN_TABLE;

static SCAN_TABLE scan_table[] = {
	{ 0x00, 0x1e, CONTROL_FLAG | SHIFT_FLAG },	// ^@
	{ 0x01, 0x1c, CONTROL_FLAG },			// ^A
	{ 0x02, 0x32, CONTROL_FLAG },			// ^B
	{ 0x03, 0x21, CONTROL_FLAG },			// ^C
	{ 0x04, 0x23, CONTROL_FLAG },			// ^D
	{ 0x05, 0x24, CONTROL_FLAG },			// ^E
	{ 0x06, 0x2b, CONTROL_FLAG },			// ^F
	{ 0x07, 0x34, CONTROL_FLAG },			// ^G
	{ 0x08, 0x33, CONTROL_FLAG },			// ^H
	{ 0x08, 0x66, 0x00 },				// BACKSPACE
	{ 0x09, 0x43, CONTROL_FLAG },			// ^I
	{ 0x09, 0x0d, 0x00 },				// TAB
	{ 0x0a, 0x3b, CONTROL_FLAG },			// ^J
	{ 0x0b, 0x42, CONTROL_FLAG },			// ^K
	{ 0x0c, 0x4b, CONTROL_FLAG },			// ^L
	{ 0x0d, 0x3a, CONTROL_FLAG },			// ^M
	{ 0x0e, 0x31, CONTROL_FLAG },			// ^N
	{ 0x0f, 0x44, CONTROL_FLAG },			// ^O
	{ 0x10, 0x4d, CONTROL_FLAG },			// ^P
	{ 0x11, 0x15, CONTROL_FLAG },			// ^Q
	{ 0x12, 0x20, CONTROL_FLAG },			// ^R
	{ 0x13, 0x1b, CONTROL_FLAG },			// ^S
	{ 0x14, 0x2c, CONTROL_FLAG },			// ^T
	{ 0x15, 0x3c, CONTROL_FLAG },			// ^U
	{ 0x16, 0x2a, CONTROL_FLAG },			// ^V
	{ 0x17, 0x1d, CONTROL_FLAG },			// ^W
	{ 0x18, 0x22, CONTROL_FLAG },			// ^X
	{ 0x19, 0x35, CONTROL_FLAG },			// ^Y
	{ 0x1a, 0x1a, CONTROL_FLAG },			// ^Z
	{ 0x1b, 0x76, 0x00 }, 				// ESCAPE
	{ 0x1c, 0x5d, CONTROL_FLAG },			// ^backslash
	{ 0x1d, 0x5b, CONTROL_FLAG },			// ^]
	{ 0x1e, 0x36, CONTROL_FLAG | SHIFT_FLAG },	// ^^
	{ 0x1f, 0x4e, CONTROL_FLAG | SHIFT_FLAG },	// ^_

	{ 'a', 0x1c, 0x00 },
	{ 'b', 0x32, 0x00 },
	{ 'c', 0x21, 0x00 },
	{ 'd', 0x23, 0x00 },
	{ 'e', 0x24, 0x00 },
	{ 'f', 0x2b, 0x00 },
	{ 'g', 0x34, 0x00 },
	{ 'h', 0x33, 0x00 },
	{ 'i', 0x43, 0x00 },
	{ 'j', 0x3b, 0x00 },
	{ 'k', 0x42, 0x00 },
	{ 'l', 0x4b, 0x00 },
	{ 'm', 0x3a, 0x00 },
	{ 'n', 0x31, 0x00 },
	{ 'o', 0x44, 0x00 },
	{ 'p', 0x4d, 0x00 },
	{ 'q', 0x15, 0x00 },
	{ 'r', 0x20, 0x00 },
	{ 's', 0x1b, 0x00 },
	{ 't', 0x2c, 0x00 },
	{ 'u', 0x3c, 0x00 },
	{ 'v', 0x2a, 0x00 },
	{ 'w', 0x1d, 0x00 },
	{ 'x', 0x22, 0x00 },
	{ 'y', 0x35, 0x00 },
	{ 'z', 0x1a, 0x00 },

	{ 'A', 0x1c, SHIFT_FLAG },
	{ 'B', 0x32, SHIFT_FLAG },
	{ 'C', 0x21, SHIFT_FLAG },
	{ 'D', 0x23, SHIFT_FLAG },
	{ 'E', 0x24, SHIFT_FLAG },
	{ 'F', 0x2b, SHIFT_FLAG },
	{ 'G', 0x34, SHIFT_FLAG },
	{ 'H', 0x33, SHIFT_FLAG },
	{ 'I', 0x43, SHIFT_FLAG },
	{ 'J', 0x3b, SHIFT_FLAG },
	{ 'K', 0x42, SHIFT_FLAG },
	{ 'L', 0x4b, SHIFT_FLAG },
	{ 'M', 0x3a, SHIFT_FLAG },
	{ 'N', 0x31, SHIFT_FLAG },
	{ 'O', 0x44, SHIFT_FLAG },
	{ 'P', 0x4d, SHIFT_FLAG },
	{ 'Q', 0x15, SHIFT_FLAG },
	{ 'R', 0x20, SHIFT_FLAG },
	{ 'S', 0x1b, SHIFT_FLAG },
	{ 'T', 0x2c, SHIFT_FLAG },
	{ 'U', 0x3c, SHIFT_FLAG },
	{ 'V', 0x2a, SHIFT_FLAG },
	{ 'W', 0x1d, SHIFT_FLAG },
	{ 'X', 0x22, SHIFT_FLAG },
	{ 'Y', 0x35, SHIFT_FLAG },
	{ 'Z', 0x1a, SHIFT_FLAG },

	{ ' ', 0x29, 0x00 },
	{ '0', 0x45, 0x00 },
	{ '1', 0x16, 0x00 },
	{ '2', 0x1e, 0x00 },
	{ '3', 0x26, 0x00 },
	{ '4', 0x25, 0x00 },
	{ '5', 0x2e, 0x00 },
	{ '6', 0x36, 0x00 },
	{ '7', 0x3d, 0x00 },
	{ '8', 0x3e, 0x00 },
	{ '9', 0x46, 0x00 },

	{ '-',  0x4e, 0x00 },
	{ '=',  0x55, 0x00 },
	{ '\\', 0x5d, 0x00 },
	{ '`',  0x0e, 0x00 },
	{ '[',  0x54, 0x00 },
	{ ']',  0x5b, 0x00 },
	{ ';',  0x4c, 0x00 },
	{ '\'', 0x52, 0x00 },
	{ ',',  0x41, 0x00 },
	{ '.',  0x49, 0x00 },
	{ '/',  0x4a, 0x00 },

	{ '!',  0x16, SHIFT_FLAG },
	{ '@',  0x1e, SHIFT_FLAG },
	{ '#',  0x26, SHIFT_FLAG },
	{ '$',  0x25, SHIFT_FLAG },
	{ '%',  0x2e, SHIFT_FLAG },
	{ '^',  0x36, SHIFT_FLAG },
	{ '&',  0x3d, SHIFT_FLAG },
	{ '*',  0x3e, SHIFT_FLAG },
	{ '(',  0x46, SHIFT_FLAG },
	{ ')',  0x45, SHIFT_FLAG },
	{ '_',  0x4e, SHIFT_FLAG },
	{ '+',  0x55, SHIFT_FLAG },
	{ '|',  0x5d, SHIFT_FLAG },
	{ '~',  0x0e, SHIFT_FLAG },
	{ '{',  0x54, SHIFT_FLAG },
	{ '}',  0x5b, SHIFT_FLAG },
	{ ':',  0x4c, SHIFT_FLAG },
	{ '"',  0x52, SHIFT_FLAG },
	{ '<',  0x41, SHIFT_FLAG },
	{ '>',  0x49, SHIFT_FLAG },
	{ '?',  0x4a, SHIFT_FLAG },
};
#define SCAN_ELEMENTS (sizeof(scan_table) / sizeof(SCAN_TABLE))

static uint8_t
keyboard_find(uint8_t scan_code)
{
	int i;
	SCAN_TABLE *p;

	for(i = 0; i < SCAN_ELEMENTS; i++) {
		p = scan_table + i;
		if((scan_code == p->make_code) && (keyboard_modifiers == p->extension_flags)) {
			return p->ascii_value;
		}
	}

	return KEY_NOT_FOUND;
}

int
keyboard_handler()
{
	int rv;
	uint8_t s;
	uint8_t c;

	asm(" ori.w #0x0700, %sr");	// Mask interrupts

	rv = 0; // Assume failure.

	// Get the character - but it may be invalid.
	s = keyboard_rb[keyboard_rb_output];

	// We depend on the order of operations.  If rb_count is zero,
	// then we won't evaluate the character.
	if(keyboard_rb_count != 0 && s != 0) {
		// Good character.  Flag it.
		rv = 1;

		// One less now available.
		--keyboard_rb_count;

		// Move the output pointer, keeping it in range.
		keyboard_rb_output = (keyboard_rb_output + 1) & (keyboard_depth - 1);

		//dump("scan code", s);

		// Figure out what we got.
		switch(keyboard_state) {
			case KB_NORMAL:
				switch(s) {
					case EXTENSION: // starting extended sequence
						keyboard_state = KB_EXTENSION;
						break;

					case KEY_UP: // starting key-up sequence
						keyboard_state = KB_NORMAL_GOING_UP;
						break;

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

					// Everything else can be looked up in the ASCII table.
					default:
						c = keyboard_find(s);
						if(c != KEY_NOT_FOUND) {
							uart_transmit(c);
						}
						break;
				}
				break;

			case KB_EXTENSION:
				switch(s) {
					case KEY_UP: // starting key-up sequence
						keyboard_state = KB_EXTENSION_GOING_UP;
						break;

					case INSERT & 0xff:
						break;

					case HOME & 0xff:
						break;

					case PG_UP & 0xff:
						break;

					case DELETE & 0xff:
						break;

					case END & 0xff:
						break;

					case PG_DOWN & 0xff:
						break;

					case U_ARROW & 0xff:
						break;

					case L_ARROW & 0xff:
						break;

					case D_ARROW & 0xff:
						break;

					case R_ARROW & 0xff:
						break;

					case R_CTRL & 0xff:
						keyboard_modifiers |= CONTROL_FLAG;
						break;

					case R_ALT & 0xff:
						keyboard_modifiers |= ALT_FLAG;
						break;
				}
				keyboard_state = KB_NORMAL;

			case KB_NORMAL_GOING_UP:
				// I don't really care what the key going up is,
				// unless it is a modifier going away.
				// Dump everything else on the floor.
				switch(s) {
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
				switch(s) {
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

	asm(" andi.w #~0x0700, %sr");	// Unmask interrupts

	return rv;
}
