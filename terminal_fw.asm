#target rom

#code ROM, 0x0000, 0x4000

rom	equ 0x0000
ram	equ 0x4000
video	equ 0x8000
uart	equ 0xc000

RST0:	di
	ld	sp, $7fff
	jp	start

	defs	0x08-$
RST1:	ret

	defs	0x10-$
RST2:	ret

	defs	0x18-$
RST3:	ret

	defs	0x20-$
RST4:	ret

	defs	0x28-$
RST5:	ret

	defs	0x30-$
RST6:	ret

	defs	0x38-$
RST7:	ei
	ret

	defs	0x66-$
NMI:	ld	a, i
	push	af
	pop	af
	ret	po
	ei
	ret

start:
	; unlock divisor registers
	ld	hl, uart + 3
	ld	a, 0x80
	ld	(hl), a

	; baud rate divisor
	; baud=   300 dTX= 43000 dRX=  2688 tA=12900000.000000 rA=12902400.000000 tE=        0.00 rE=        0.02
	; baud=   600 dTX= 21500 dRX=  1344 tA=12900000.000000 rA=12902400.000000 tE=        0.00 rE=        0.02
	; baud=  1200 dTX= 10750 dRX=   672 tA=12900000.000000 rA=12902400.000000 tE=        0.00 rE=        0.02
	; baud=  2400 dTX=  5375 dRX=   336 tA=12900000.000000 rA=12902400.000000 tE=        0.00 rE=        0.02
	; baud=  4800 dTX=  2688 dRX=   168 tA=12902400.000000 rA=12902400.000000 tE=        0.02 rE=        0.02
	; baud=  9600 dTX=  1344 dRX=    84 tA=12902400.000000 rA=12902400.000000 tE=        0.02 rE=        0.02
	; baud= 19200 dTX=   672 dRX=    42 tA=12902400.000000 rA=12902400.000000 tE=        0.02 rE=        0.02
	; baud= 38400 dTX=   336 dRX=    21 tA=12902400.000000 rA=12902400.000000 tE=        0.02 rE=        0.02
	; baud= 57600 dTX=   224 dRX=    14 tA=12902400.000000 rA=12902400.000000 tE=        0.02 rE=        0.02
	; baud=115200 dTX=   112 dRX=     7 tA=12902400.000000 rA=12902400.000000 tE=        0.02 rE=        0.02
	ld	hl, uart
	ld	a, 0x07
	ld	(hl), a

	inc	hl
	ld	a, 0x00
	ld	(hl), a

	; lock divisor registers and set 8 bit data, no parity, one stop bit.
	ld	hl, uart + 3
	ld	a, 0x03
	ld	(hl), a

	; write char
	ld	hl, uart
	ld	a, 0x29
	ld	(hl), a

wait1:	ld	hl, uart + 5
	ld	a, (hl)
	bit	6, a
	jr	z, wait1

	; write char
	ld	hl, uart
	ld	a, 0x55
	ld	(hl), a

wait2:	ld	hl, uart + 5
	ld	a, (hl)
	bit	6, a
	jr	z, wait2

	; write char
	ld	hl, uart
	ld	a, 0xaa
	ld	(hl), a

wait3:	ld	hl, uart + 5
	ld	a, (hl)
	bit	6, a
	jr	z, wait3

	; move bytes around
mover:	ld	bc, 1920
	ld	de, ram
	ld	hl, video
again:	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	bc
	ld	a, b
	or	c
	jr	nz, again

back:	ld	bc, 1920
	ld	de, video
	ld	hl, ram + 1919
b2:	ld	a, (hl)
	ld	(de), a
	dec	hl
	inc	de
	dec	bc
	ld	a, b
	or	c
	jr	nz, b2

pause:	ld	d, 10

b4:	ld	bc, 65535
b3:	dec	bc
	ld	a, b
	or	c
	jr	nz, b3

	dec	d
	jr	nz, b4

	jr	start
	jr	$

