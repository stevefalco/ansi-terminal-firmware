#code ROM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; math_multiply_10 - multiply A by ten and return the result in A
;
; This is used for processing escape numbers.  The largest value
; produced would be 80.
;
; Uses A, C
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
