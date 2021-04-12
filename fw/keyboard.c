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

// Keyboard registers
#define keyboard_base		(0xc040)
#define keyboard_SCAN_CODE	(*(volatile uint8_t *)(keyboard_base + 0x00))	// Scan Code register
#define keyboard_ASCII_CODE	(*(volatile uint8_t *)(keyboard_base + 0x02))	// ASCII Code register
#define keyboard_STATUS		(*(volatile uint8_t *)(keyboard_base + 0x04))	// Status register

// Keyboard register bits

// STATUS
#define keyboard_Shift_Key_b	(0)						// Shift key depressed
#define keyboard_Key_Released_b	(1)						// Key has been released
#define keyboard_Extended_b	(2)						// Extended code prefix
#define keyboard_Interrupt_b	(3)						// Interrupt received

#define keyboard_Shift_Key_v	(1 << keyboard_Shift_Key_b)
#define keyboard_Key_Released_v	(1 << keyboard_Key_Released_b)
#define keyboard_Extended_v	(1 << keyboard_Extended_b)
#define keyboard_Interrupt_v	(1 << keyboard_Interrupt_b)

#define keyboard_depth		(128)						// Buffer depth.

typedef struct {
	uint8_t status;
	uint8_t ascii_code;
	uint8_t scan_code;
} KB_BUF;

static KB_BUF keyboard_rb[keyboard_depth];
static int keyboard_rb_input;
static int keyboard_rb_output;
static int keyboard_rb_count;

void
keyboard_initialize()
{
	// Clear the scan code receive buffer
	keyboard_rb_input = 0;
	keyboard_rb_output = 0;
	keyboard_rb_count = 0;
}

static void
keyboard_store_char()
{
	uint8_t junk;
	KB_BUF *p;

	if(keyboard_rb_count < keyboard_depth) {
		// There is room to store this character.
		p = &keyboard_rb[keyboard_rb_input];

		p->status = keyboard_STATUS;
		p->ascii_code = keyboard_ASCII_CODE;
		p->scan_code = keyboard_SCAN_CODE;	// Must be read last - retires interrupt

		// One more now available.
		++keyboard_rb_count;
		
		// Move the input pointer, keeping it in range.
		keyboard_rb_input = (keyboard_rb_input + 1) & (keyboard_depth - 1);
	} else {
		// No room - just flush it.
		junk = keyboard_SCAN_CODE;
	}
}

void
keyboard_test_interrupt()
{
	uint8_t junk;

	while(1) {
		// Read the status register to see if this interrupt is for us.
		// Bit 3 = 1 indicates a new character is available.
		if(!(keyboard_STATUS & keyboard_Interrupt_v)) {
			return;
		}

		// Bit 1 = 1 indicates that this is a key release event, which
		// we don't need to store.  But we still have to access the scan
		// code register to clear the interrupt.
		if(keyboard_STATUS & keyboard_Key_Released_v) {
			// Flush the key release event.
			junk = keyboard_SCAN_CODE;
		} else {
			// Store the character.
			keyboard_store_char();
		}
	}
}

int
keyboard_handler()
{
	int rv;
	KB_BUF *p;

	asm(" ori.w #0x0700, %sr");	// Mask interrupts

	rv = 0; // Assume failure.

	// Load the pointer - but it may be invalid.
	p = &keyboard_rb[keyboard_rb_output];

	// We depend on the order of operations.  If rb_count is zero,
	// then we won't dereference the invalid pointer.
	if(keyboard_rb_count != 0 && p->ascii_code != 0) {
		// Good character.  Flag and transmit it.
		rv = 1;
		uart_transmit(p->ascii_code);

		// One less now available.
		--keyboard_rb_count;

		// Move the output pointer, keeping it in range.
		keyboard_rb_output = (keyboard_rb_output + 1) & (keyboard_depth - 1);
	}

	asm(" andi.w #~0x0700, %sr");	// Unmask interrupts

	return rv;
}
