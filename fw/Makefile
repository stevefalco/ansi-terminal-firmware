# ANSI Terminal
#
# (c) 2021 Steven A. Falco

OBJ = init.o main.o uart.o

all: ../cpu_rom.mif fw.dump

../cpu_rom.mif: fw.bin
	../cvt_obj_mif/cvt_obj_mif -i $^ -o $@

fw.bin: fw
	m68k-linux-gnu-objcopy -O binary $^ $@

fw.dump: fw
	m68k-linux-gnu-objdump -d $^ > $@

fw: $(OBJ)
	m68k-linux-gnu-gcc \
		-Wl,--build-id=none \
		-Wl,-M -Wl,-T,fw.ld \
		-m68000 -nostdlib \
		-o $@ $^ \
		-lgcc \
		> fw.map

%.o: %.s
	m68k-linux-gnu-gcc -m68000 -c $^ -o $@

%.o: %.c
	m68k-linux-gnu-gcc -O1 -m68000 -c $^ -o $@

clean:
	rm -f *.o fw fw.bin fw.dump fw.map
