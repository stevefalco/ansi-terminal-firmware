ENTRY(_start)

__DYNAMIC = 0;

MEMORY {
	/* Note: init is a magic name - nothing else seems to work */
	init (rx) : ORIGIN = 0x00000000, LENGTH = 0x00000100
	rom (rx)  : ORIGIN = 0x00000100, LENGTH = 0x00003F00
	ram (!rx) : ORIGIN = 0x00004000, LENGTH = 0x00004000
}

SECTIONS {
	.init : {
		* (.init)
	} > init

	.text : {
		* (.text*)
		_etext = .;
	} > rom

	.bss (NOLOAD) : {
		. = ALIGN(4);
		_sbss = .;
		* (.bss*)
		* (COMMON)
		. = ALIGN(4);
		_ebss = .;
	} > ram

	.data : AT (ADDR(.text) + SIZEOF(.text)) {
		. = ALIGN(4);
		_sdata = .;
		* (.data*);
		. = ALIGN(4);
		_edata = .;
	} > ram

	/DISCARD/ : {
		* (.comment)
	}
}

