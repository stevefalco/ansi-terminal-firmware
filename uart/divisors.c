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

// This file tries out different clock rates to see how much error we'd
// wind up with in our baud rate generation.
//
// We want to choose the highest speed clock for best CPU performance,
// while still having accurate baud rates.  It turns out that 51.6 MHz
// was a reasonably high frequency that would meet timing with accurate baud
// rates.  We might be able to go a little faster, but 100 MHz failed timing.
//
// See "divtable" for the typical output of this program.

#include <stdio.h>
#include <math.h>

int baudTable[] = {
	110,
	300,
	600,
	1200,
	2400,
	4800,
	9600,
	19200,
	38400,
	57600,
	115200,
};

int
main()
{
	double clockStart = 50E6;
	double clock;
	double txActual;
	double rxActual;
	double txError;
	double rxError;

	int baud;
	int divisorTX;
	int divisorRX;
	int oversample = 16;

	int i;
	int j;

	for(j = 0; j < 100; j++) {
		clock = clockStart + (j * 1E5);
		printf("clock %f\n", clock);
		for(i = 0; i < sizeof(baudTable) / sizeof(int); i++) {
			baud = baudTable[i];

			divisorTX = (int)round(clock / baud);
			divisorRX = (int)round((clock / oversample) / baud);

			txActual = (double)(divisorTX * baud);
			rxActual = (double)(oversample * divisorRX * baud);

			txError = 100.0 * ((txActual - clock) / clock);
			rxError = 100.0 * ((rxActual - clock) / clock);

			printf("baud=%6d dTX=%6d dRX=%6d tA=%10.0f rA=%10.0f tE=%7.2f rE=%7.2f\n",
					baud, divisorTX, divisorRX,
					txActual, rxActual, txError, rxError);
		}
		printf("\n");
	}
}
