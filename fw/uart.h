#ifndef _UART_H_
#define _UART_H_

#include "types.h"

extern void uart_initialize();
extern void uart_test_interrupt();
extern void uart_transmit(unsigned char c);
extern void uart_transmit_string(char *pString);
extern int uart_receive();

#endif // _UART_H_
