#define BS (24 * 80)

extern void uart_initialize();
extern void uart_transmit_string(char *pString);

char buf[BS];

void
fillMem()
{
	int i;
	int j;
	int k;
	char *p = buf;

	for(i = 0; i < 24; i++) {
		for(j = 0; j < 8; j++) {
			for(k = 0; k < 10; k++) {
				*p++ = '0' + k;
			}
		}
	}
}

void
copyForward()
{
	int i;
	char *p = buf;

	volatile char *q = (volatile char *)0x8001;

	for(i = 0; i < BS; i++) {
		*q = *p++;
		q += 2;
	}
}

void
copyBackward()
{
	int i;
	char *p = buf;

	volatile char *q = (volatile char *)0x8eff;

	for(i = 0; i < BS; i++) {
		*q = *p++;
		q -= 2;
	}
}

void
main()
{
	int i;
	int sr;

	volatile char *pControl = (volatile char *)0x0000c060;

	// Enable video sync
	*pControl = 1;

	uart_initialize();

	// Read the status register.
	asm(" mov.w %%sr, %0\n\t" : "=r" (sr));
	//printf("sr = %x\n\r", sr);

	// Enable interrupts.
	//asm(" andi.w #~0x0700, %sr");

	uart_transmit_string("test it\n\r");

	fillMem();

	while(1) {
		copyForward();
		for(i = 0; i < 500000; i++) {
			;
		}

		copyBackward();
		for(i = 0; i < 500000; i++) {
			;
		}

	}
}
