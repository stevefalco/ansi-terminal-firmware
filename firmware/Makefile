# ANSI Terminal
#
# (c) 2021 Steven A. Falco

BUILD_DIR = build

A_SRC = init.s
C_SRC = main.c screen.c keyboard.c uart.c debug.c

OBJ = $(A_SRC:%.s=$(BUILD_DIR)/%.o)
OBJ += $(C_SRC:%.c=$(BUILD_DIR)/%.o)

DEP = $(C_SRC:%.c=$(BUILD_DIR)/%.d)

all: $(BUILD_DIR) version ../cpu_rom.mif $(BUILD_DIR)/fw.dump

../cpu_rom.mif: $(BUILD_DIR)/fw.bin
	../cvt_obj_mif/cvt_obj_mif -i $^ -o $@

$(BUILD_DIR)/fw.bin: $(BUILD_DIR)/fw
	m68k-linux-gnu-objcopy -O binary $^ $@

$(BUILD_DIR)/fw.dump: $(BUILD_DIR)/fw
	m68k-linux-gnu-objdump -d $^ > $@

$(BUILD_DIR)/fw: $(OBJ) lib/build/lib.a
	m68k-linux-gnu-gcc \
		-Wl,--build-id=none \
		-Wl,-M -Wl,-T,fw.ld \
		-m68000 -nostdlib \
		-o $@ $^ \
		> $(BUILD_DIR)/fw.map

-include $(DEP)

$(BUILD_DIR)/%.o: %.S
	m68k-linux-gnu-gcc -m68000 -c $< -o $@

$(BUILD_DIR)/%.o: %.s
	m68k-linux-gnu-gcc -m68000 -c $< -o $@

$(BUILD_DIR)/%.o: %.c
	m68k-linux-gnu-gcc -MMD -O1 -m68000 -c $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY:
lib/build/lib.a:
	cd lib ; make

.PHONY: version
version:
	@git describe | sed -e 's/.*/#define VERSION "&"/' > $(BUILD_DIR)/new_version.h
	@if [ -z "`git status -s`" ] ; then echo '#define STATE "-clean"' >> $(BUILD_DIR)/new_version.h ; else echo '#define STATE "-dirty"' >> $(BUILD_DIR)/new_version.h ; fi
	@cmp -s $(BUILD_DIR)/new_version.h $(BUILD_DIR)/version.h || mv -f $(BUILD_DIR)/new_version.h $(BUILD_DIR)/version.h
	@rm -f $(BUILD_DIR)/new_version.h

.PHONY: clean
clean:
	rm -fr $(BUILD_DIR)
	cd lib ; make clean
