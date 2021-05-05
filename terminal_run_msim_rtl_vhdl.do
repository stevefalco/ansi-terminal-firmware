restart -f

radix -hexadecimal

configure wave -namecolwidth 463
configure wave -valuecolwidth 101
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns

delete wave *

add wave /testbench/term/addrbus
add wave /testbench/term/iEdb
add wave /testbench/term/oEdb
add wave /testbench/term/ASn
add wave /testbench/term/eRWn
add wave /testbench/term/cpuByteEnables
add wave /testbench/term/cpuClock
add wave /testbench/term/enPhi1
add wave /testbench/term/enPhi2
add wave /testbench/term/cpu/busControl/busPhase
add wave /testbench/term/cpu/tState
add wave /testbench/term/cpu/excUnit/regs68L
add wave /testbench/term/cpu/excUnit/regs68H


add wave -r /testbench/term/cpuBus/*
add wave -r /testbench/term/*

run 40ms
