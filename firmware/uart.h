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

#ifndef _UART_H_
#define _UART_H_

#include "types.h"

extern void uart_initialize();
extern void uart_test_interrupt();
extern void uart_transmit(unsigned char c);
extern void uart_transmit_string(char *pString);
extern int uart_receive();

#endif // _UART_H_
