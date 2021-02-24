#include <stdio.h>
#include <math.h>

int baudTable[] = {
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
	double clockStart = 10E6;
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

			printf("baud=%6d dTX=%6d dRX=%6d tA=%f rA=%f tE=%12.2f rE=%12.2f\n",
					baud, divisorTX, divisorRX,
					txActual, rxActual, txError, rxError);
		}
		printf("\n");
	}
}
