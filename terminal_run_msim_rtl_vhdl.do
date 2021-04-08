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

add wave -r /testbench/term/cpuBus/*
add wave /testbench/term/cpuRam/*
add wave -r /testbench/term/*

run 40ms
