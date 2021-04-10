OBJ = test.o main.o

all: ../cpu_rom.mif test.dump

../cpu_rom.mif: test.bin
	../cvt_obj_mif/cvt_obj_mif -i $^ -o $@

test.bin: test
	m68k-linux-gnu-objcopy -O binary $^ $@

test.dump: test
	m68k-linux-gnu-objdump -d $^ > $@

test: $(OBJ)
	m68k-linux-gnu-gcc \
		-Wl,--build-id=none \
		-Wl,-M -Wl,-T,test.ld \
		-m68000 -nostdlib \
		-o $@ $^ \
		-lgcc \
		> test.map

%.o: %.s
	m68k-linux-gnu-gcc -m68000 -c $^ -o $@

%.o: %.c
	m68k-linux-gnu-gcc -m68000 -c $^ -o $@

clean:
	rm -f *.o test test.bin test.dump test.map
