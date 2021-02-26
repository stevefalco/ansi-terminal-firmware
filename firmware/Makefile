all: ../z80.mif

../z80.mif: terminal_fw.rom
	cvt_obj_mif -i $^ -o $@

terminal_fw.rom: terminal_fw.asm
	zasm -uwy -i $^ -l terminal_fw.list -o $@
