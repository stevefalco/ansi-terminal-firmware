#include <stdio.h>
#include <stdint.h>

int
main()
{
	int row;
	int line;
	int mod20;

	line = 0;
	mod20 = 0;
	for(row = 0; row < 525; row++) {
		if(mod20 >= 20) {
			mod20 = 0;
		}

		printf("row=%x(%d) mod20=%x(%d) line=%x(%d)\n",
			       	row, row, mod20, mod20, line, line);
		
		if(mod20 < 16) {
			line++;
		}
		if(row >= 480) {
			line = 0;
		}

		mod20++;
	}
}
