/* ANSI Terminal
 *
 * (c) 2021 Steven A. Falco
 *
 * ANSI Terminal is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * ANSI Terminal is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with ANSI Terminal.  If not, see <https://www.gnu.org/licenses/>.
 */

ENTRY(_start)

__DYNAMIC = 0;

MEMORY {
	/* Note: init is a magic name - nothing else seems to work.
	 * RAM length is actually 0x4000, but I specify 0x3800 here,
	 * because the stack is at the top of RAM.  Thus, we are
	 * allowing 2 kbytes for the stack.  There is no good way
	 * to detect a violation, because we don't have an MMU.
	 */
	init (rx) : ORIGIN = 0x00000000, LENGTH = 0x00000100
	rom (rx)  : ORIGIN = 0x00000100, LENGTH = 0x00003F00
	ram (!rx) : ORIGIN = 0x00004000, LENGTH = 0x00003800
}

SECTIONS {
	.init : {
		* (.init)
	} > init

	.text : {
		. = ALIGN(4);
		_stext = .;
		* (.text*)
		. = ALIGN(4);
		_etext = .;
	} > rom

	.rodata : {
		. = ALIGN(4);
		_srodata = .;
		* (.rodata .rodata* .gnu.linkonce.r.*)
		. = ALIGN(4);
		_erodata = .;
	} > rom

	.bss (NOLOAD) : {
		. = ALIGN(4);
		_sbss = .;
		* (.bss*)
		* (COMMON)
		. = ALIGN(4);
		_ebss = .;
	} > ram

	.data : AT (ADDR(.rodata) + SIZEOF(.rodata)) {
		. = ALIGN(4);
		_sdata = .;
		* (.data*);
		. = ALIGN(4);
		_edata = .;
	} > ram

	/DISCARD/ : {
		* (.comment)
	}
}

