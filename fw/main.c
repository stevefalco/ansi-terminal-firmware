#define BS (24 * 80)

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
	int j;
	int k;
	char *p = buf;

	volatile short *q = (volatile short *)0x8000;

	for(i = 0; i < 24; i++) {
		for(j = 0; j < 8; j++) {
			for(k = 0; k < 10; k++) {
				*q++ = *p++;
			}
		}
	}
}

void
copyBackward()
{
	int i;
	int j;
	int k;
	char *p = buf;

	volatile short *q = (volatile short *)0x8efe;

	for(i = 0; i < 24; i++) {
		for(j = 0; j < 8; j++) {
			for(k = 0; k < 10; k++) {
				*q-- = *p++;
			}
		}
	}
}

void
main()
{
	int i;

	volatile char *pControl = (volatile char *)0x0000c060;

	// Enable video sync
	*pControl = 1;

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
