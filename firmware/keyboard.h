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

#ifndef _KEYBOARD_H_
#define _KEYBOARD_H_

#include "types.h"

extern void keyboard_initialize();
extern void keyboard_test_interrupt();
extern int keyboard_handler();

#endif // _KEYBOARD_H_
