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

// Main program.

#include "debug.h"
#include "keyboard.h"
#include "screen.h"
#include "uart.h"

static int inactive = 0;
static int blanked = 0;

// Initialize the world and go into a loop handling whatever comes in from
// the keyboard and uart.  Also, run the screen-saver timer.
int
main()
{
	volatile char *pControl = (volatile char *)0x0000c060;

	// Enable video sync
	*pControl = 1;

	uart_initialize();
	screen_initialize(1);
	keyboard_initialize();

#if 0
	{
		uint32_t sr;

		// Read and display the status register.
		asm(" mov.w %%sr, %0\n\t" : "=r" (sr));
		dump("sr =", sr);
	}
#endif

	// Enable interrupts.
	asm(" andi.w #~0x0700, %sr");

	while(1) {
		// Get any waiting uart characters and process them.
		screen_handler();

		// Get any waiting keyboard characters and process them.
		if(!keyboard_handler()) {
			// Nothing received from the keyboard.  Keep a
			// count so we can blank the screen if we go
			// too long without activity.
			//
			// Only increment when not blanked, else the
			// counter might overflow and turn the screen
			// back on.
			if(!blanked) {
				inactive++;
			}
		} else {
			// Got something from the keyboard.  Reset
			// flags and turn screen back on.
			blanked = 0;
			inactive = 0;
			*pControl = 1;
		}

		// Based on our CPU clock of 88.5 MHz, I've found that this
		// value should give about 15 minutes before inactivity
		// timeout and blanking of the monitor.
		if(inactive > 70000000) {
			// We've been inactive too long.  Blank the screen.
			*pControl = 0;
			blanked = 1;
		}

		// If the uart is currently sending a line break, decrement
		// its timer.  When the timer hits zero, we stop the line
		// break;
		if(uart_break_timer != 0) {
			--uart_break_timer;
			if(uart_break_timer == 0) {
				uart_stop_break();
			}
		}
	}

	return 0;
}
