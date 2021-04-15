#include "debug.h"
#include "keyboard.h"
#include "screen.h"
#include "uart.h"

static int inactive = 0;
static int blanked = 0;

// Initialize the world and go into a loop handling whatever comes in from
// the keyboard and uart.  Also, run the screen-saver timer.
void
main()
{
	int i;
	int sr;

	volatile char *pControl = (volatile char *)0x0000c060;

	// Enable video sync
	*pControl = 1;

	uart_initialize();
	screen_initialize(1);
	keyboard_initialize();

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

		// Should be about 15 minutes.
		if(inactive > 40000000) {
			// We've been inactive too long.  Blank the screen.
			*pControl = 0;
			blanked = 1;
		}
	}
}
