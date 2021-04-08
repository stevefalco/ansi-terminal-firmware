ENTRY(_start)

__DYNAMIC = 0;

MEMORY {
	init : ORIGIN = 0x00000000, LENGTH = 0x00000040
	pmem : ORIGIN = 0x00000040, LENGTH = 0x00008000
	dmem : ORIGIN = 0x00008000, LENGTH = 0x00008000
}

SECTIONS {
	.init : {*(.init)} > init
	.text :
	{
		_ftext = .;
		*(.text .stub .text.* .gnu.linkonce.t.*)
		_etext = .;
	} > pmem

	.rodata :
	{
		. = ALIGN(4);
		_frodata = .;
		*(.rodata .rodata.* .gnu.linkonce.r.*)
		*(.rodata1)
		_erodata = .;
	} > pmem

	.data :
	{
	    . = ALIGN(4);
	    _fdata = .;
	    *(.data .data.* .gnu.linkonce.d.*)
		    *(.data1)
		    _gp = ALIGN(16);
	    *(.sdata .sdata.* .gnu.linkonce.s.*)
	    _edata = .;
	} > dmem

	.bss :
	{
	    . = ALIGN(4);
	    _fbss = .;
	    *(.dynsbss)
		    *(.sbss .sbss.* .gnu.linkonce.sb.*)
		    *(.scommon)
		    *(.dynbss)
		    *(.bss .bss.* .gnu.linkonce.b.*)
		    *(COMMON)
		    . = ALIGN(4);
		    _ebss = .;
		    _end = .;
	} > dmem
}

