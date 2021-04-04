; ANSI Terminal
;
; (c) 2021 Steven A. Falco
;
; The Z80 doesn't have a multiply instruction, so here are a few simple
; routines to perform the multiplications that we need.

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; math_multiply_10 - multiply A by ten and return the result in A
;
; This is used for processing escape numbers.  The largest value
; produced would be 80.
;
; Uses AF, C
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

math_multiply_10:

	; Call the initial A "iA" so we can keep track of what we've
	; done.
	;
	; Note - sla is slower than add!
	add	a, a			; A = iA * 2
	ld	c, a			; C = iA * 2
	add	a, a			; A = iA * 4
	add	a, a			; A = iA * 8
	add	a, c			; A = iA * 8 + iA * 2 = iA * 10

	ret

#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; math_multiply_16x8 - multiply DE by A and return the result in HL
;
; This is used for finding positions in the video buffer.  The largest
; value produced would be 1920.
;
; Input DE, A
; Affects AF, B, HL
; Output HL
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

math_multiply_16x8:
	ld	l, 0
	ld	b, 8

math_multiply_16x8_loop:
	add	hl, hl			; Shift HL one bit to the left
	add	a, a			; Shift A one bit to the left
	jr	NC, math_multiply_16x8_no_add ; skip the addition
	add	hl, de			; Add DE into HL

math_multiply_16x8_no_add:
	djnz	math_multiply_16x8_loop	; Do the above 8 times in all

	ret



