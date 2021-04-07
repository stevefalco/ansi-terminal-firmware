	.section .init
	.align	2
	.globl	_start

	dc.l	0	| Initial Stack Pointer
	dc.l	8	| Initial Program Counter
_start:			| first instruction of program
	mov.w	#0, %d0

next:
	addq.w	#1, %d0
	move.w	%d0, 0x00c040

	| Outer loop
	mov.w	#0xf, %d2
wait_more:

	| Inner loop
	mov.w	#0x7fff, %d1
wait:
	dbmi	%d1, wait

	dbmi	%d2, wait_more

	bra.s	next
