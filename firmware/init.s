| ANSI Terminal
|
| (c) 2021 Steven A. Falco
|
| Bare metal setup

	.section .init
	.align	2
	.globl	_start

	| For some reason, if I try to set a non-zero stack pointer
	| in the reset vector, the code won't run.  I don't know why,
	| but it is simple enough to instead set the stack pointer in
	| the first instruction.

	. = 0x000	| Reset vector
	dc.l	0	| Initial Stack Pointer
	dc.l	_start	| Initial Program Counter
	
	. = 0x060	| Start of interrupt vectors
	dc.l	_spurious
	dc.l	_level1
	dc.l	_level2
	dc.l	_level3
	dc.l	_level4
	dc.l	_level5
	dc.l	_level6
	dc.l	_level7

	.section .text
	.align	2

| Register usage:
|
| %a6 = fp
| %a7 = sp

_start:
	| Set the real stack pointer to the top of RAM.  The stack
	| pointer pre-decrements so we actually want the LWA+1 here.
	mov.l	#0x00008000, %sp

	| Initialize the C global variables that start off as non-zero.
	|
	| Our linker control file specifies 4-byte alignment of the
	| _sdata and _edata variables, so we know the number of bytes
	| to copy is a multiple of 4.
	|
	| The initial values come at the end of the rodata section and
	| also have a 4-byte alignment.
	mov.l	#_erodata, %a0		| Initial values for data section
	mov.l	#_sdata, %a1		| Start of data section
	mov.l	#_edata, %d0		| End of data section
	sub.l	%a1, %d0		| How many bytes to copy
	beq	initDataDone		| Nothing to do
	lsr.l	#2, %d0			| Divide by 4
	sub.l	#1, %d0			| Compensate dbf (test at bottom of loop)
initDataLoop:
	mov.l	(%a0)+, (%a1)+		| Copy one lword
	dbf	%d0, initDataLoop	| Do them all
initDataDone:

	| Initialize the C global variables that start off as zero.
	|
	| Our linker control file specifies 4-byte alignment of the
	| _sbss and _ebss variables, so we know the number of bytes
	| to copy is a multiple of 4.
	mov.l	#_sbss, %a0		| Start of BSS
	mov.l	#_ebss, %d0		| End of BSS
	sub.l	%a0, %d0		| How many bytes to zero
	beq	initBssDone		| Nothing to do
	lsr.l	#2, %d0			| Divide by 4
	sub.l	#1, %d0			| Compensate dbf (test at bottom of loop)
	mov.l	#0, %d1			| Get a zero
initBssLoop:
	mov.l	%d1, (%a0)+		| Zero one lword
	dbf	%d0, initBssLoop	| Do them all
initBssDone:

	jsr	main

	| Main should never exit, but if it does, we will do a cold restart.
	bra.s	_start

_spurious:
_level1:
_level3:
_level4:
_level5:
_level6:
_level7:
	bra.s	_start

| UART RX and KB RX interrupts.
_level2:
	| Save all registers on the stack.
	movem.l	%d0-%d7/%a0-%a6, -(%sp)

	| See if the keyboard has anything for us.
	jsr	keyboard_test_interrupt

	| See if the UART has anything for us.
	jsr	uart_test_interrupt

	| Restore all registers from the stack.
	movem.l	(%sp)+, %d0-%d7/%a0-%a6

	| Return from exception.
	rte
