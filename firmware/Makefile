all: ../z80.mif

../z80.mif: main.s
	zasm -uwy -i $^ -l terminal_fw.list -o terminal_fw.rom
	cvt_obj_mif -i terminal_fw.rom -o $@
