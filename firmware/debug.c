#include "debug.h"
#include "uart.h"

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

void
msg(char *str)
{
	uart_transmit_string(str);
	uart_transmit_string("\r\n");
}
