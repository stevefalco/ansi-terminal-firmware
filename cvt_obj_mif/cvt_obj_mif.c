// ANSI Terminal
//
// (c) 2021 Steven A. Falco
//
// A tool to read a binary file and output it as a MIF file.  This is used
// to convert our Z80 machine code into a ROM image for Quartus.

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#include <fcntl.h>
#include <unistd.h>

#include <sys/stat.h>
#include <sys/types.h>

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
main(int argc, char *argv[])
{
	int opt;

	char *pInFile = 0;
	char *pOutFile = 0;

	int ifd;
	FILE *pOut;

	struct stat statbuf;

	int i;

	uint8_t in;

	while((opt = getopt(argc, argv, "i:o:")) != -1) {
		switch(opt) {
			case 'i':
				pInFile = optarg;
				break;
			case 'o':
				pOutFile = optarg;
				break;

			default: /* '?' */
				fprintf(stderr, "Usage: %s -i input file -o output file\n", argv[0]);
				exit(1);
		}
	}

	if(pInFile == 0 || pOutFile == 0) {
		fprintf(stderr, "Need -i input file and -o output file\n");
		exit(1);
	}

	if((ifd = open(pInFile, O_RDONLY)) == -1) {
		fprintf(stderr, "Cannot open %s\n", pInFile);
		exit(1);
	}

	if((pOut = fopen(pOutFile, "w")) == NULL) {
		fprintf(stderr, "Cannot open/create %s\n", pOutFile);
		exit(1);
	}

	if(fstat(ifd, &statbuf) == -1) {
		fprintf(stderr, "Cannot get status for %s\n", pInFile);
		exit(1);
	}

	// Write preamble.
	fprintf(pOut, "-- begin_signature\n");
	fprintf(pOut, "-- %s\n", pInFile);
	fprintf(pOut, "-- end_signature\n");
	fprintf(pOut, "\n");
	fprintf(pOut, "WIDTH=8;\n");
	fprintf(pOut, "DEPTH=%d;\n", statbuf.st_size);
	fprintf(pOut, "\n");
	fprintf(pOut, "ADDRESS_RADIX=UNS;\n");
	fprintf(pOut, "DATA_RADIX=BIN;\n");
	fprintf(pOut, "\n");
	fprintf(pOut, "CONTENT BEGIN\n");

	for(i = 0; i < statbuf.st_size; i++) {
		if(read(ifd, &in, 1) != 1) {
			fprintf(stderr, "Cannot read %s at byte %d\n", pInFile, i);
			exit(1);
		}

		fprintf(pOut, "%8d : %s; -- %02x\n", i, htob(in), in);
	}

	// Write trailer.
	fprintf(pOut, "\n");
	fprintf(pOut, "END\n");

	exit(0);
}
