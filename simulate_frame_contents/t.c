#include <stdio.h>
#include <stdint.h>

char *
htob(uint32_t v)
{
	int i;
	static char b[32];

	for(i = 0; i < 8; i++) {
		b[i] = ((v >> (7 - i)) & 1) ? '1' : '0';
	}

	return b;
}

int
main()
{
	int i;
	int j;
	int chr;
	int addr;

	printf("-- begin_signature\n");
	printf("-- char\n");
	printf("-- end_signature\n");
	printf("\n");
	printf("WIDTH=8;\n");
	printf("DEPTH=1920;\n");
	printf("\n");
	printf("ADDRESS_RADIX=UNS;\n");
	printf("DATA_RADIX=BIN;\n");
	printf("\n");
	printf("CONTENT BEGIN\n");

	addr = 0;
	for(j = 0; j < 24; j++) {
		for(i = 0; i < 80; i++) {
			chr = 0x7f - (j + i);
			printf("%4d : %s; -- %c\n", addr++, htob(chr), chr);
		}
		printf("\n");
	}

	printf("END;\n");
}
