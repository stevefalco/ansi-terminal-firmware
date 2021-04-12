#ifndef _KEYBOARD_H_
#define _KEYBOARD_H_

#include "types.h"

extern void keyboard_initialize();
extern void keyboard_test_interrupt();
extern int keyboard_handler();

#endif // _KEYBOARD_H_
