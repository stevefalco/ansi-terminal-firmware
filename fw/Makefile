all: ../cpu_rom.mif test.dump

../cpu_rom.mif: test.bin
	../cvt_obj_mif/cvt_obj_mif -i $< -o $@

test.bin: test
	m68k-linux-gnu-objcopy -O binary $< $@

test.dump: test
	m68k-linux-gnu-objdump -d $< > $@

test: test.s test.ld
	m68k-linux-gnu-gcc -Wl,--build-id=none -Wl,-M -Wl,-T,test.ld -m68000 -nostdlib -o $@ $< > test.map
