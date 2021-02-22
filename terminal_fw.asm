#target rom

#code ROM, 0x0000, 0x4000

rom	equ 0x0000
ram	equ 0x4000
video	equ 0x8000

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

start:	ld	bc, 16
	ld	de, video
	ld	hl, video + 16
again:	ld	a, (hl)
	ld	(de), a
	inc	hl
	inc	de
	dec	bc
	ld	a, b
	or	c
	jr	nz, again
	jr	$

