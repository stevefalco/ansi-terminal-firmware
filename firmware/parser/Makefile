# ANSI Terminal
#
# (c) 2021 Steven A. Falco
#
# ANSI Terminal is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ANSI Terminal is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ANSI Terminal.  If not, see <https://www.gnu.org/licenses/>.

BUILD_DIR = build

RUBY_GENERATION_FILES = vtparse_gen_c_tables.rb vtparse_tables.rb

C_SRC = vtparse.c

GEN_SRC = $(BUILD_DIR)/vtparse_table.c

OBJ = $(C_SRC:%.c=$(BUILD_DIR)/%.o)
OBJ += $(GEN_SRC:$(BUILD_DIR)/%.c=$(BUILD_DIR)/%.o)

DEP = $(C_SRC:%.c=$(BUILD_DIR)/%.d)
DEP += $(GEN_SRC:$(BUILD_DIR)/%.c=$(BUILD_DIR)/%.d)

all: $(BUILD_DIR) $(GEN_SRC) $(BUILD_DIR)/parser.a

$(BUILD_DIR)/parser.a: $(OBJ)
	m68k-linux-gnu-ar -r $@ $^

$(BUILD_DIR)/vtparse_table.c $(BUILD_DIR)/vtparse_table.h: $(RUBY_GENERATION_FILES)
	cd build && ruby ../vtparse_gen_c_tables.rb

-include $(DEP)

$(BUILD_DIR)/%.o: %.c
	m68k-linux-gnu-gcc -Wall -Werror -MMD -O1 -m68000 -c $< -o $@

$(BUILD_DIR)/%.o: $(BUILD_DIR)/%.c
	m68k-linux-gnu-gcc -Wall -Werror -MMD -O1 -m68000 -c $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: clean
clean:
	rm -fr $(BUILD_DIR)
