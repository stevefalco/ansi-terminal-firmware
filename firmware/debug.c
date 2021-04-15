#include "debug.h"
#include "uart.h"

// We cannot afford a full-blown printf.  Instead, just print a string followed
// by a hex dump of a single value.
void
dump(char *prefix, unsigned int c)
{
	int i;
	unsigned char tmp;

	uart_transmit_string(prefix);
	uart_transmit(' ');

	for(i = 7; i >= 0; i--) {
		// Get a nibble.
		tmp = (c >> (4 * i)) & 0xf;

		if(tmp < 10) {
			tmp += '0';
		} else {
			tmp += 'A' - 10;
		}
		uart_transmit(tmp);
	}

	uart_transmit_string("\r\n");
}

// Print a simple string.  We supply the <CR> <LF>.
void
msg(char *str)
{
	uart_transmit_string(str);
	uart_transmit_string("\r\n");
}
