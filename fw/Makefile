all: ../cpu_rom.mif test.dump

../cpu_rom.mif: test.srec
	srec_cat $< -Output $@ -Memory_Initialization_File 16

test.srec: test
	m68k-linux-gnu-objcopy -O srec $< $@

test.dump: test
	m68k-linux-gnu-objdump -d $< > $@

test: test.s test.ld
	m68k-linux-gnu-gcc -Wl,--build-id=none -Wl,-M -Wl,-T,test.ld -m68000 -nostdlib -o $@ $< > test.map
