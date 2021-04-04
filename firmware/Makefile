# ANSI Terminal
#
# (c) 2021 Steven A. Falco
#
# The assembler only deals with one source file - in our case, main.s.  All
# the other source files are then included by main.s.  But we must list all
# the source files as dependencies, because we need to run the assembler
# whenever any one of the files changes.
#
# The assembler can produce various output formats; I just use the raw binary
# format, and I've written a simple tool that converts it to a MIF file for
# Quartus to initialize the Z80 program ROM.

all: ../z80.mif

../z80.mif: main.s uart.s screen.s keyboard.s math.s debug.s
	zasm -uwy -i $< -l terminal_fw.list -o terminal_fw.rom
	cvt_obj_mif -i terminal_fw.rom -o $@
