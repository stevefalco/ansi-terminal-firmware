# ANSI Terminal
#
# (c) 2021 Steven A. Falco

BUILD_DIR = build

C_SRC = ashldi3.c ashrdi3.c lshrdi3.c muldi3.c
L_SRC = divsi3.S  modsi3.S  mulsi3.S  udivsi3.S  umodsi3.S

OBJ = $(L_SRC:%.S=$(BUILD_DIR)/%.o)
OBJ += $(C_SRC:%.c=$(BUILD_DIR)/%.o)

DEP = $(C_SRC:%.c=$(BUILD_DIR)/%.d)

all: $(BUILD_DIR) $(BUILD_DIR)/lib.a

$(BUILD_DIR)/lib.a: $(OBJ)
	m68k-linux-gnu-ar -r $@ $^

-include $(DEP)

$(BUILD_DIR)/%.o: %.S
	m68k-linux-gnu-gcc -m68000 -c $< -o $@

$(BUILD_DIR)/%.o: %.c
	m68k-linux-gnu-gcc -MMD -O1 -m68000 -c $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: clean
clean:
	rm -fr $(BUILD_DIR)
