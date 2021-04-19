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

// UART driver.  We respond to UART receiver interrupts, and store the
// characters in a circular buffer.  If our circular buffer becomes too
// full, we deassert the RTS signal to stop the sender (assuming the
// sender supports hardware flow control).
//
// 2.11bsd as implemented via Sytse's FPGA runs the console at 9600
// baud, and we can keep up with that, even without flow control.  That
// is good, because by default, Sytse's FPGA doesn't implement hardware
// flow control, although it can be turned on in his VHDL if needed.

#include "uart.h"
#include "debug.h"

// UART registers
#define uart_base		(0xc000)
#define uart_RBR		(*(volatile uint8_t *)(uart_base + 0x00))	// Receiver Buffer Register - read-only
#define uart_THR		(*(volatile uint8_t *)(uart_base + 0x00))	// Transmitter Holding Register - write-only
#define uart_IER		(*(volatile uint8_t *)(uart_base + 0x02))	// Interrupt Enable Register
#define uart_IIR		(*(volatile uint8_t *)(uart_base + 0x04))	// Interrupt Identification Register - read-only
#define uart_FCR		(*(volatile uint8_t *)(uart_base + 0x04))	// FIFO Control Register - write-only
#define uart_LCR		(*(volatile uint8_t *)(uart_base + 0x06))	// Line Control Register
#define uart_MCR		(*(volatile uint8_t *)(uart_base + 0x08))	// Modem Control Register
#define uart_LSR		(*(volatile uint8_t *)(uart_base + 0x0a))	// Line Status Register
#define uart_MSR		(*(volatile uint8_t *)(uart_base + 0x0c))	// Modem Status Register
#define uart_SCR		(*(volatile uint8_t *)(uart_base + 0x0e))	// Scratch Register
#define uart_DLL		(*(volatile uint8_t *)(uart_base + 0x00))	// Divisor Latch Low Byte (only when DLAB=1)
#define uart_DLM		(*(volatile uint8_t *)(uart_base + 0x02))	// Divisor Latch High Byte (only when DLAB=1)

// UART register bits

// IER
#define uart_IER_ERBFI_b	(0)						// Enable Received Data Available Interrupt
#define uart_IER_ETBEI_b	(1)						// Enable Transmitter Holding Register Empty Interrupt
#define uart_IER_ELSI_b		(2)						// Enable Receiver Line Status Interrupt
#define uart_IER_EDSSI_b	(3)						// Enable Model Status Interrupt

// IER bits as values
#define uart_IER_ERBFI_v	(1 << uart_IER_ERBFI_b)
#define uart_IER_ETBEI_v	(1 << uart_IER_ETBEI_b)
#define uart_IER_ELSI_v		(1 << uart_IER_ELSI_b)
#define uart_IER_EDSSI_v	(1 << uart_IER_EDSSI_b)

// IER convenience
#define uart_IER_INIT		(uart_IER_ERBFI_v)

// IIR
#define uart_IIR_PENDING_b	(0)						// Interrupt pending when 0

// IIR bits as values
#define uart_IIR_PENDING_v	(1 << uart_IIR_PENDING_b)

// FCR
#define uart_FCR_FEN_b		(0)						// FIFO Enable
#define uart_FCR_RFR_b		(1)						// Receive FIFO Reset
#define uart_FCR_XFR_b		(2)						// Transmit FIFO Reset

// FCR bits as values
#define uart_FCR_FEN_v		(1 << uart_FCR_FEN_b)
#define uart_FCR_RFR_v		(1 << uart_FCR_RFR_b)
#define uart_FCR_XFR_v		(1 << uart_FCR_XFR_b)

// FCR convenience
#define uart_FCR_INIT		(uart_FCR_FEN_v | uart_FCR_RFR_v | uart_FCR_XFR_v)

// LCR
#define uart_LCR_WLS0_b		(0)						// Word Length Select Bit 0
#define uart_LCR_WLS1_b		(1)						// Word Length Select Bit 1
#define uart_LCR_STB_b		(2)						// Number of Stop Bits
#define uart_LCR_PEN_b		(3)						// Parity Enable
#define uart_LCR_EPS_b		(4)						// Even Parity Select
#define uart_LCR_SBRK_b		(6)						// Set Break
#define uart_LCR_DLAB_b		(7)						// Divisor Latch Access Bit

// LCR bits as values
#define uart_LCR_WLS0_v		(1 << uart_LCR_WLS0_b)
#define uart_LCR_WLS1_v		(1 << uart_LCR_WLS1_b)
#define uart_LCR_STB_v		(1 << uart_LCR_STB_b)
#define uart_LCR_PEN_v		(1 << uart_LCR_PEN_b)
#define uart_LCR_EPS_v		(1 << uart_LCR_EPS_b)
#define uart_LCR_SBRK_v		(1 << uart_LCR_SBRK_b)
#define uart_LCR_DLAB_v		(1 << uart_LCR_DLAB_b)

// LCR convenience
#define uart_LCR_WLS5		(0)
#define uart_LCR_WLS6		(uart_LCR_WLS0_v)
#define uart_LCR_WLS7		(uart_LCR_WLS1_v)
#define uart_LCR_WLS8		(uart_LCR_WLS0_v | uart_LCR_WLS1_v)

// MCR
#define uart_MCR_DTR_b		(0)						// Data Terminal Ready
#define uart_MCR_RTS_b		(1)						// Request To Send

// MCR bits as values
#define uart_MCR_DTR_v		(1 << uart_MCR_DTR_b)
#define uart_MCR_RTS_v		(1 << uart_MCR_RTS_b)

// MCR convenience
#define uart_MCR_INIT		(uart_MCR_DTR_v | uart_MCR_RTS_v)

// LSR
#define uart_LSR_THRE_b		(5)						// Transmitter Holding Register Empty

// LSR bits as values
#define uart_LSR_THRE_v		(1 << uart_LSR_THRE_b)

// Baud rate, etc. dip switches
#define dipSW			(*(volatile uint8_t *)(0xc020))
#define dipBaudMask		(0x0f)
#define dipFlowMask		(0x10)						// 0 = RTS/CTS, 1 = XON/XOFF

#define uart_depth		(128)						// SW receiver fifo depth
#define uart_high_water		(64)

#define XON			(0x11)						// ^Q (DC1)
#define XOFF			(0x13)						// ^S (DC3)
#define HW_FLOW			(0)
#define SW_FLOW			(1)

static int uart_flow;
static int uart_flow_state;							// 1 if paused, else 0

// These divisors are based on our 88.5 MHz CPU clock.
static uint16_t baud_table[] = {
	50284,	// sw=0 for 110 baud
	18438,	// sw=1 for 300 baud
	9219,	// sw=2 for 600 baud
	4609,	// sw=3 for 1200 baud
	2305,	// sw=4 for 2400 baud
	1152,	// sw=5 for 4800 baud
	576,	// sw=6 for 9600 baud
	288,	// sw=7 for 19200 baud
	144,	// sw=8 for 38400 baud
	96,	// sw=9 for 57600 baud
	48,	// sw=10 for 115200 baud
	24,	// sw=11 for 230400 baud
	12,	// sw=12 for 460800 baud
	6,	// sw=13 for 921600 baud
	6,	// sw=14 for 921600 baud
	6,	// sw=15 for 921600 baud
};

// uart_set_baud - set the baud rate based on the dip switches
static void
uart_set_baud()
{
	uint8_t switches = dipSW;

	// We are using bits 0-3 for the baud rate, so mask out the rest.
	uint16_t divisor = baud_table[switches & dipBaudMask];

	// Unlock divisor registers.
	uart_LCR |= uart_LCR_DLAB_v;

	// Write the baud rate divisor.
	uart_DLL = divisor & 0xff;
	uart_DLM = (divisor >> 8) & 0xff;

	// Lock divisor registers.
	uart_LCR &= ~uart_LCR_DLAB_v;

	// Determine the flow-control type.
	uart_flow = !!(switches & dipFlowMask);
}

static uint8_t uart_rb[uart_depth];
static int uart_rb_input;
static int uart_rb_output;
static int uart_rb_count;

// uart_initialize - get the uart ready
void
uart_initialize()
{
	// Clear the receive buffer
	uart_rb_input = 0;
	uart_rb_output = 0;
	uart_rb_count = 0;

	// Set an initial baud rate
	uart_set_baud();

	// Word length 8, no parity, 1 stop bit, i.e. 8-N-1.
	// We could add other modes, selectable by dip-switch,
	// but I've never seen a need...
	uart_LCR = uart_LCR_WLS8;

	// Reset FIFOs and enable them
	uart_FCR = uart_FCR_INIT;

	// Set the MODEM control bits
	uart_MCR = uart_MCR_INIT;

	// Enable interrupt - we really only care about received characters
	// because we assume we can't type fast enough to overrun the tx
	// buffer.
	uart_IER = uart_IER_INIT;

	// Unblock the sender.  We always set the RTS bit, because that is
	// harmless.  We only send XON when using software flow control.
	//
	// Remember the state for later.
	uart_MCR |= uart_MCR_RTS_v;
	if(uart_flow == SW_FLOW) {
		uart_transmit(XON);
	}
	uart_flow_state = 0;
}

// uart_store_char - store a character in the receive buffer
//
// This runs from the interrupt service routine with interrupts disabled.
static void
uart_store_char()
{
	// Read the character - we have to do this even if there is no
	// room to store it, because reading clears the interrupt.
	uint8_t val = uart_RBR;

	if(uart_rb_count > uart_high_water) {
		if(uart_flow == HW_FLOW) {
			// Above high water - clear RTS so the sender will pause.
			uart_MCR &= ~uart_MCR_RTS_v;
		} else {
			// Above high water - send XOFF so the sender will pause.
			uart_transmit(XOFF);
		}
		uart_flow_state = 1; // Remember that we are paused.
	}

	if(uart_rb_count < uart_depth) {
		uart_rb[uart_rb_input] = val;

		// One more now available.
		++uart_rb_count;
		
		// Move the input pointer, keeping it in range.
		uart_rb_input = (uart_rb_input + 1) & (uart_depth - 1);
	}
}

// uart_test_interrupt - see if the uart has posted an interrupt
//
// This runs from the interrupt service routine with interrupts disabled.
void
uart_test_interrupt()
{
	// Interrupt-pending bit is active-low.
	// (Bit_0 = 1) means no interrupt
	//
	// Read characters and store them until the uart is empty.  This
	// is ugly because we really cannot tell how much data is in the
	// fifo.  However, we have set the threshold to "1", so when the
	// interrupt clears, the fifo must be empty.  If we had set any
	// other threshold, we'd have to burst "threshold" characters out.
	// We couldn't use the interrupt flag, because it would clear as
	// soon as we went below threshold, which would leave some characters
	// in the fifo.  With threshold = 1, that cannot happen.
	while(!(uart_IIR & uart_IIR_PENDING_v)) {
		uart_store_char();
	}
}

// uart_transmit - transmit a character
void
uart_transmit(unsigned char c)
{
	while(!(uart_LSR & uart_LSR_THRE_v)) {
		; // Wait for the transmit buffer to be free.
	}

	uart_THR = c;
}

// uart_transmit - transmit a null-terminated string
void
uart_transmit_string(char *pString)
{
	char *p = pString;

	while(*p != 0) {
		uart_transmit(*p++);
	}
}

// uart_receive - get a character from the receiver queue
//
// We have to disable interrupts for mutual exclusion with the
// uart_test_interrupt routine.
//
// Return the next character in our buffer, or -1 if nothing available.
int
uart_receive()
{
	asm(" ori.w #0x0700, %sr");	// Mask interrupts

	int rv = -1;

	if(uart_rb_count) {
		// Something available.
		rv = uart_rb[uart_rb_output];

		// One less now available.
		--uart_rb_count;
		
		// Move the output pointer, keeping it in range.
		uart_rb_output = (uart_rb_output + 1) & (uart_depth - 1);
	} else {
		// If there is nothing available, make sure we haven't blocked
		// the sender.
		if(uart_flow_state) {
			if(uart_flow == HW_FLOW) {
				uart_MCR |= uart_MCR_RTS_v;
			} else {
				uart_transmit(XON);
			}
			uart_flow_state = 0; // No longer paused
		}
	}

	asm(" andi.w #~0x0700, %sr");	// Unmask interrupts

	return rv;
}

