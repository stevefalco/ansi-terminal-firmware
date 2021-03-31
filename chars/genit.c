#include <stdio.h>

#include "flattenedchars.h"

#define SKIP	32
#define MOD	64

char *names[] = {
	"NUL",
	"SOH",
	"STX",
	"ETX",
	"EOT",
	"ENQ",
	"ACK",
	"BEL",
	"BS",
	"HT",
	"LF",
	"VT",
	"FF",
	"CR",
	"SO",
	"SI",
	"DLE",
	"DC1",
	"DC2",
	"DC3",
	"DC4",
	"NAK",
	"SYN",
	"ETB",
	"CAN",
	"EM",
	"SUB",
	"ESC",
	"FS",
	"GS",
	"RS",
	"US",
	"SPACE",
	"!",
	"\"",
	"#",
	"$",
	"%",
	"&",
	"\'",
	"(",
	")",
	"*",
	"+",
	",",
	"-",
	".",
	"/",
	"0",
	"1",
	"2",
	"3",
	"4",
	"5",
	"6",
	"7",
	"8",
	"9",
	":",
	";",
	"<",
	"=",
	">",
	"?",
	"@",
	"A",
	"B",
	"C",
	"D",
	"E",
	"F",
	"G",
	"H",
	"I",
	"J",
	"K",
	"L",
	"M",
	"N",
	"O",
	"P",
	"Q",
	"R",
	"S",
	"T",
	"U",
	"V",
	"W",
	"X",
	"Y",
	"Z",
	"[",
	"\\",
	"]",
	"^",
	"_",
	"`",
	"a",
	"b",
	"c",
	"d",
	"e",
	"f",
	"g",
	"h",
	"i",
	"j",
	"k",
	"l",
	"m",
	"n",
	"o",
	"p",
	"q",
	"r",
	"s",
	"t",
	"u",
	"v",
	"w",
	"x",
	"y",
	"z",
	"{",
	"|",
	"}",
	"~",
	"DEL"
};

int
main()
{
	FILE *p;
	int i, j, k, n, m;
	int s = sizeof(MagickImage);

	printf("-- begin_signature\n");
	printf("-- char\n");
	printf("-- end_signature\n");
	printf("\n");
	printf("WIDTH=16;\n");
	printf("DEPTH=8192;\n");
	printf("\n");
	printf("ADDRESS_RADIX=UNS;\n");
	printf("DATA_RADIX=BIN;\n");
	printf("\n");
	printf("CONTENT BEGIN\n");

	// Do this twice - the first set has no cursor, the second set does.
	k = 0;
	for(m = 0; m < 2; m++) {

		// Emit 32 control chars - just blanks.
		for(n = 0; n < 32; n++) {
			for(i = 0; i < 32; i++) {
				if(i == 0) {
					printf("%4d : %s; -- %s\n", k++, (m == 1) ? "1111111111111111" : "0000000000000000", names[n]);
				} else {
					printf("%4d : %s;\n", k++, (m == 1) ? "1111111111111111" : "0000000000000000");
				}
			}
			printf("\n");
		}

		// Emit the printable characters.
		for(j = SKIP; j < s; j += 2) {
			printf("%4d : ", k++);
			for(i = 0; i < 8; i++) {
				if((MagickImage[j] >> (7 - i)) & 1) {
					printf("%d", (m == 1) ? 0 : 1);
				} else {
					printf("%d", (m == 1) ? 1 : 0);
				}
			}
			for(i = 0; i < 8; i++) {
				if((MagickImage[j+1] >> (7 - i)) & 1) {
					printf("%d", (m == 1) ? 0 : 1);
				} else {
					printf("%d", (m == 1) ? 1 : 0);
				}
			}
			printf("; -- ");
			for(i = 0; i < 8; i++) {
				if((MagickImage[j] >> (7 - i)) & 1) {
					printf("%c", (m == 1) ? '.' : '@');
				} else {
					printf("%c", (m == 1) ? '@' : '.');
				}
			}
			for(i = 0; i < 8; i++) {
				if((MagickImage[j+1] >> (7 - i)) & 1) {
					printf("%c", (m == 1) ? '.' : '@');
				} else {
					printf("%c", (m == 1) ? '@' : '.');
				}
			}

			// Label the first line of each character.
			if(((j - SKIP) % MOD) == 0) {
				printf(" %s\n", names[n++]);
			} else {
				printf("\n");
			}

			// Blank line after each character.
			if(((j - SKIP) % MOD) == (MOD - 2)) {
				printf("\n");
			}
		}

		printf("\n");
	}

	printf("END;\n");
}
