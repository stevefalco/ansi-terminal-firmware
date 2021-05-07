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

#include "types.h"

#define spl7()		_spl(0x2700)	// Supervisor mode | mask 7
#define spl6()		_spl(0x2600)	// Supervisor mode | mask 6
#define spl5()		_spl(0x2500)	// Supervisor mode | mask 5
#define spl4()		_spl(0x2400)	// Supervisor mode | mask 4
#define spl3()		_spl(0x2300)	// Supervisor mode | mask 3
#define spl2()		_spl(0x2200)	// Supervisor mode | mask 2
#define spl1()		_spl(0x2100)	// Supervisor mode | mask 1
#define spl0()		_spl(0x2000)	// Supervisor mode | mask 0

// Change the current interrupt level, and return the previous level.
//
// Since asm statements are not used that frequently, here are the details
// of the various flags used.  We specify "volatile" to guarantee that the
// compiler won't optimize out or move the asm instructions.
//
// The destination operand is specified as "=&d", where the "=" means that
// we are overwriting the "sr" variable (as opposed to both reading and
// writing the variable).  The "&" means that we use the output ("sr"
// variable), before reading the input ("s" variable), which prevents the
// compiler from putting them in the same register - ordinarily the compiler
// assumes that the inputs are used before the output.  The "d" means "use
// a data register" (as opposed to an address or floating point register).
//
// The source operand is specified as "di", where the "d" means "use a data
// register", and the "i" means an "immediate integer operand" (constant) is
// allowed.
//
// We add a clobber for the condition codes, since they are contained in the
// %sr register.  We add a clobber for memory, to be sure that the data within
// the protected region is actually flushed to memory, and is not sitting in
// a register.
//
// Note that we could be interrupted between the first and second move
// instructions.  That is ok, because the interrupt routine will save and
// restore the interrupt level before returning.
static inline uint16_t
_spl(uint16_t s)
{
	int sr;

	asm volatile (" mov.w %%sr,%0; mov.w %1,%%sr" : "=&d" (sr) : "di" (s) : "cc", "memory");

	return sr;
}

// Restore a previous interrupt level.
//
// The source operand is specified as "di", where the "d" means "use a data
// register", and the "i" means an "immediate integer operand" is allowed.
//
// We add a clobber for the condition codes, since they are contained in the
// %sr register.  We add a clobber for memory, to be sure that the data within
// the protected region is actually flushed to memory, and is not sitting in
// a register.
static inline void
splx(uint16_t s)
{
	asm volatile (" mov.w %0,%%sr" :: "di" (s) : "cc", "memory");
}

#endif // _SPL_H_
