	.section .init
	.align	2
	.globl	_start

	. = 0x000	| Reset vector
	dc.l	0x8000	| Initial Stack Pointer (%a7)
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

_start:			| first instruction of program

			| %a7 = sp
			| %a6 = fp

	mov.l	#_etext, %a0		| Initial values for data section
	mov.l	#_sdata, %a1		| Start of data section
	mov.l	#_edata, %d0		| End of data section
	sub.l	%a1, %d0		| How many bytes to copy
initData:
	mov.b	(%a0)+, (%a1)+		| Copy one byte
	dbf	%d0, initData		| Do them all

	mov.l	#_sbss, %a0		| Start of BSS
	mov.l	#_ebss, %d0		| End of BSS
	sub.l	%a0, %d0		| How many bytes to zero
initBSS:
	mov.b	#0, (%a0)+		| Zero one byte
	dbf	%d0, initBSS		| Do them all

	bra	main

main:

	jsr	mains

	mov.b	#1, %d6
	mov.b	%d6, 0xc060		| Enable video sync

	| Set up to fill cpu ram
	mov.w	#23, %d2		| Do 24 lines
	mov.l	#0x4000, %a0		| RAM base address

nextLine:
	mov.w	#7, %d1			| Do 8 groups - we test at the botom
					| so we get one extra.
next10:
	mov.w	#9, %d0			| Do groups of 10
	mov.b	#'0', %d3		| The starting character
next1:
	mov.b	%d3, (%a0)		| Place char
	addq.b	#1, %d3			| Bump char
	addq.l	#1, %a0			| Bump address
	dbf	%d0, next1
	dbf	%d1, next10
	dbf	%d2, nextLine

top:

	| mov.b	0xc020, %d6
	| mov.b	%d6, 0xc080

	| Copy everything to video ram
	| We start at an odd address since we want to write
	| the LSB with the character.  Also, we increment
	| by 2, to skip the flag byte.
	mov.l	#0x4000, %a0		| RAM base address
	mov.l	#0x8001, %a1		| Frame buffer
	mov.w	#((24 * 80) - 1), %d1	| How much to move

again:
	mov.b	(%a0), (%a1)		| Move one byte
	addq.l	#1, %a0			| Bump RAM ptr
	addq.l	#2, %a1			| Bump Frame ptr

	dbf	%d1, again		| Fill video ram

	mov.w	#0xf, %d5
w1a:
	mov.w	#0xffff, %d4
w1:
	nop
	nop
	nop
	nop
	dbf	%d4, w1
	dbf	%d5, w1a


	| Copy backwards to video ram
	mov.l	#0x4000, %a0		| RAM base address
	mov.l	#0x8eff, %a1		| Frame end address
	mov.w	#((24 * 80) - 1), %d1	| How much to move

bagain:
	mov.b	(%a0), (%a1)		| Move one byte
	addq.l	#1, %a0			| Bump RAM ptr
	subq.l	#2, %a1			| Frame ptr moves backwards

	dbf	%d1, bagain		| Fill video ram

	mov.w	#0xf, %d5
w2a:
	mov.w	#0xffff, %d4
w2:
	nop
	nop
	nop
	nop
	dbf	%d4, w2
	dbf	%d5, w2a

	bra.s	top

_spurious:
_level1:
_level2:
_level3:
_level4:
_level5:
_level6:
_level7:
	bra.s	top
