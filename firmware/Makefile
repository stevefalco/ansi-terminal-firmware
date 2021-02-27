all: ../z80.mif

# The assembler really only deals with one source file.  All the others are
# simply included in main.s.  But we must list them here, since they are
# dependencies.
../z80.mif: main.s uart.s screen.s
	zasm -uwy -i $< -l terminal_fw.list -o terminal_fw.rom
	cvt_obj_mif -i terminal_fw.rom -o $@
