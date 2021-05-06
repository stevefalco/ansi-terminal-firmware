// ANSI Terminal
//
// (c) 2021 Steven A. Falco
//
// ANSI Terminal is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// ANSI Terminal is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with ANSI Terminal.  If not, see <https://www.gnu.org/licenses/>.

#ifndef _SPL_H_
#define _SPL_H_

// There is no instruction to just affect the interrupt mask field of the
// status register.  SPL7 and SPL0 are easy - we can directly set the desired
// level.
//
// For SPL1 through SPL6, we first do an OR to mask out all interrupts,
// then do an AND to lower the mask to the desired level.
#define SPL7	asm(" ori.w  # 0x0700, %sr")
#define SPL6	asm(" ori.w  # 0x0700, %sr"); asm(" andi.w #~0x0100, %sr")
#define SPL5	asm(" ori.w  # 0x0700, %sr"); asm(" andi.w #~0x0200, %sr")
#define SPL4	asm(" ori.w  # 0x0700, %sr"); asm(" andi.w #~0x0300, %sr")
#define SPL3	asm(" ori.w  # 0x0700, %sr"); asm(" andi.w #~0x0400, %sr")
#define SPL2	asm(" ori.w  # 0x0700, %sr"); asm(" andi.w #~0x0500, %sr")
#define SPL1	asm(" ori.w  # 0x0700, %sr"); asm(" andi.w #~0x0600, %sr")
#define SPL0	asm(" andi.w #~0x0700, %sr")

#endif // _SPL_H_
