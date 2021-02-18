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
add wave /testbench/term/frameGen/hsync
add wave /testbench/term/frameGen/vsync
add wave -radix unsigned /testbench/term/columnAddress
add wave -radix unsigned /testbench/term/rowAddress
add wave -radix unsigned /testbench/term/lineAddress
add wave -radix unsigned /testbench/term/addressA
add wave -radix unsigned /testbench/term/addressAclipped
add wave -radix ascii /testbench/term/frameChar
add wave -radix unsigned /testbench/term/romAddr
add wave -radix hexadecimal /testbench/term/scanChar
add wave /testbench/term/pixel

run 20ms
