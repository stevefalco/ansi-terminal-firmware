	.section .init
	.align	2
	.globl	_start

	dc.l	0	| Initial Stack Pointer
	dc.l	8	| Initial Program Counter
_start:			| first instruction of program
	bra	main

	.section .text
	.align	2

main:
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
	| Copy everything to video ram
	mov.l	#0x4000, %a0		| RAM base address
	mov.l	#0x8000, %a1		| Frame buffer
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
	mov.l	#0x8efe, %a1		| Frame end address
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
