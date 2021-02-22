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

add wave /testbench/term/clear
add wave /testbench/term/CLK12M
add wave /testbench/term/dotClock
add wave -radix unsigned /testbench/term/frameGen/frameProcess/columnCounter
add wave -radix unsigned /testbench/term/frameGen/frameProcess/rowCounter
add wave -radix unsigned /testbench/term/frameGen/frameProcess/mod20Counter
add wave /testbench/term/frameGen/hsync
add wave /testbench/term/frameGen/vsync
add wave /testbench/term/frameGen/blanking
add wave -radix unsigned /testbench/term/rowAddressD0
add wave -radix unsigned /testbench/term/lineAddressD0
add wave -radix unsigned /testbench/term/lineAddressD2
add wave -radix unsigned /testbench/term/columnAddressD0
add wave -radix unsigned /testbench/term/columnAddressD4
add wave -radix unsigned /testbench/term/addressA
add wave -radix ascii /testbench/term/frameChar
add wave -radix unsigned /testbench/term/romAddr
add wave -radix hexadecimal /testbench/term/scanChar
add wave /testbench/term/pixel
add wave /testbench/term/blankingD5
add wave /testbench/term/pixelBlanked
add wave /testbench/term/hSyncD5
add wave /testbench/term/vSyncD5

add wave /testbench/term/cpuClock
add wave /testbench/term/cpuClearD1_n
add wave -radix hexadecimal /testbench/term/cpuAddrBus
add wave -radix hexadecimal /testbench/term/cpuDataBus
add wave /testbench/term/nM1
add wave /testbench/term/nMREQ
add wave /testbench/term/nIORQ
add wave /testbench/term/nRD
add wave /testbench/term/nWR
add wave /testbench/term/nRFSH
add wave /testbench/term/nHALT
add wave /testbench/term/nBUSACK
add wave /testbench/term/z80CPU/*

run 40ms
