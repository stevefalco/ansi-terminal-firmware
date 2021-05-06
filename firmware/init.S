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

// Bare metal setup

	.section .init
	.align	2
	.globl	_start

	// For some reason, if I try to set a non-zero stack pointer
	// in the reset vector, the code won't run.  I don't know why,
	// but it is simple enough to instead set the stack pointer in
	// the first instruction.
	//
	// We want that anyway, in case we get an unhandled exception,
	// so we can restart properly.

	. = 0x000			// Vector table

	dc.l	0			// Initial Stack Pointer
	dc.l	_start			// Initial Program Counter
	dc.l	_bus_error
	dc.l	_address_error
	dc.l	_illegal_instruction
	dc.l	_divide_by_zero
	dc.l	_chk_instruction
	dc.l	_trapv_instruction
	dc.l	_privilege_violation
	dc.l	_trace_trap
	dc.l	_line_1010_emulator
	dc.l	_line_1111_emulator
	dc.l	_unassigned_c
	dc.l	_unassigned_d
	dc.l	_format_error
	dc.l	_uninitialized_vector
	dc.l	_unassigned_10
	dc.l	_unassigned_11
	dc.l	_unassigned_12
	dc.l	_unassigned_13
	dc.l	_unassigned_14
	dc.l	_unassigned_15
	dc.l	_unassigned_16
	dc.l	_unassigned_17
	dc.l	_spurious_interrupt
	dc.l	_level1
	dc.l	_level2
	dc.l	_level3
	dc.l	_level4
	dc.l	_level5
	dc.l	_level6
	dc.l	_level7
	dc.l	_trap_20
	dc.l	_trap_21
	dc.l	_trap_22
	dc.l	_trap_23
	dc.l	_trap_24
	dc.l	_trap_25
	dc.l	_trap_26
	dc.l	_trap_27
	dc.l	_trap_28
	dc.l	_trap_29
	dc.l	_trap_2a
	dc.l	_trap_2b
	dc.l	_trap_2c
	dc.l	_trap_2d
	dc.l	_trap_2e
	dc.l	_trap_2f
	dc.l	_unassigned_30
	dc.l	_unassigned_31
	dc.l	_unassigned_32
	dc.l	_unassigned_33
	dc.l	_unassigned_34
	dc.l	_unassigned_35
	dc.l	_unassigned_36
	dc.l	_unassigned_37
	dc.l	_unassigned_38
	dc.l	_unassigned_39
	dc.l	_unassigned_3a
	dc.l	_unassigned_3b
	dc.l	_unassigned_3c
	dc.l	_unassigned_3d
	dc.l	_unassigned_3e
	dc.l	_unassigned_3f

	.section .text
	.align	2

// Register usage:
//
// %a6 = fp
// %a7 = sp

_start:
	// Set the real stack pointer to the top of RAM.  The stack
	// pointer pre-decrements so we actually want the LWA+1 here.
	mov.l	#0x00008000, %sp

	// Initialize the C global variables that start off as non-zero.
	//
	// Our linker control file specifies 4-byte alignment of the
	// _sdata and _edata variables, so we know the number of bytes
	// to copy is a multiple of 4.
	//
	// The initial values come at the end of the rodata section and
	// also have a 4-byte alignment.
	mov.l	#_erodata, %a0		// Initial values for data section
	mov.l	#_sdata, %a1		// Start of data section
	mov.l	#_edata, %d0		// End of data section
	sub.l	%a1, %d0		// How many bytes to copy
	beq	initDataDone		// Nothing to do
	lsr.l	#2, %d0			// Divide by 4
	sub.l	#1, %d0			// Compensate dbf (test at bottom of loop)
initDataLoop:
	mov.l	(%a0)+, (%a1)+		// Copy one lword
	dbf	%d0, initDataLoop	// Do them all
initDataDone:

	// Initialize the C global variables that start off as zero.
	//
	// Our linker control file specifies 4-byte alignment of the
	// _sbss and _ebss variables, so we know the number of bytes
	// to copy is a multiple of 4.
	mov.l	#_sbss, %a0		// Start of BSS
	mov.l	#_ebss, %d0		// End of BSS
	sub.l	%a0, %d0		// How many bytes to zero
	beq	initBssDone		// Nothing to do
	lsr.l	#2, %d0			// Divide by 4
	sub.l	#1, %d0			// Compensate dbf (test at bottom of loop)
	mov.l	#0, %d1			// Get a zero
initBssLoop:
	mov.l	%d1, (%a0)+		// Zero one lword
	dbf	%d0, initBssLoop	// Do them all
initBssDone:

	jsr	main

	// Main should never exit, but if it does, we will do a cold restart.
	bra.s	_start

// KB RX interrupt.
_level2:
	// Save all registers on the stack.
	movem.l	%d0-%d7/%a0-%a6, -(%sp)

	// Handle the keyboard interrupt.
	jsr	keyboard_test_interrupt

	// Restore all registers from the stack.
	movem.l	(%sp)+, %d0-%d7/%a0-%a6

	// Return from exception.
	rte

// UART RX interrupt.
_level3:
	// Save all registers on the stack.
	movem.l	%d0-%d7/%a0-%a6, -(%sp)

	// Handle the UART interrupt.
	jsr	uart_test_interrupt

	// Restore all registers from the stack.
	movem.l	(%sp)+, %d0-%d7/%a0-%a6

	// Return from exception.
	rte

// We shouldn't get any of these interrupts, but if we do, we will simply restart.
_bus_error:
_address_error:
_illegal_instruction:
_divide_by_zero:
_chk_instruction:
_trapv_instruction:
_privilege_violation:
_trace_trap:
_line_1010_emulator:
_line_1111_emulator:
_unassigned_c:
_unassigned_d:
_format_error:
_uninitialized_vector:
_unassigned_10:
_unassigned_11:
_unassigned_12:
_unassigned_13:
_unassigned_14:
_unassigned_15:
_unassigned_16:
_unassigned_17:
_spurious_interrupt:
_level1:
_level4:
_level5:
_level6:
_level7:
_trap_20:
_trap_21:
_trap_22:
_trap_23:
_trap_24:
_trap_25:
_trap_26:
_trap_27:
_trap_28:
_trap_29:
_trap_2a:
_trap_2b:
_trap_2c:
_trap_2d:
_trap_2e:
_trap_2f:
_unassigned_30:
_unassigned_31:
_unassigned_32:
_unassigned_33:
_unassigned_34:
_unassigned_35:
_unassigned_36:
_unassigned_37:
_unassigned_38:
_unassigned_39:
_unassigned_3a:
_unassigned_3b:
_unassigned_3c:
_unassigned_3d:
_unassigned_3e:
_unassigned_3f:
	// Modify the exception stack frame to stay in supervisor mode,
	// with all interrupts disabled.  Set the return address to
	// _start.
	mov.w	#0x2700, %sp@
	mov.l	#_start, %sp@(2)
	rte
