all: terminal.rom

terminal.rom: terminal.asm
	zasm -uwy-o $^
