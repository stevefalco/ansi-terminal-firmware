## Copyright (C) 2020  Intel Corporation. All rights reserved.
## Your use of Intel Corporation's design tools, logic functions 
## and other software and tools, and any partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Intel Program License 
## Subscription Agreement, the Intel Quartus Prime License Agreement,
## the Intel FPGA IP License Agreement, or other applicable license
## agreement, including, without limitation, that your use is for
## the sole purpose of programming logic devices manufactured by
## Intel and sold by Intel or its authorized distributors.  Please
## refer to the applicable agreement for further details, at
## https://fpgasoftware.intel.com/eula.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 20.1.0 Build 711 06/05/2020 SJ Lite Edition"

## DATE    "Thu Jan 21 16:43:58 2021"

##
## DEVICE  "10CL025YU256C8G"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3

# 12 MHz reference
set refPeriod 12MHz

#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {CLK12M} -period $refPeriod [get_ports {CLK12M}]

derive_pll_clocks
derive_clock_uncertainty

#**************************************************************
# Set Input Delay
#**************************************************************

set_input_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[1]}] -max 20.0 [get_ports {UART_RX}]
set_input_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[1]}] -min -20.0 [get_ports {UART_RX}]

#**************************************************************
# Set Output Delay
#**************************************************************

set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -max 1.0 [get_ports {PIXEL_*}]
set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -min -1.0 [get_ports {PIXEL_*}]

set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -max 1.0 [get_ports {HSYNC VSYNC}]
set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -min -1.0 [get_ports {HSYNC VSYNC}]

set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[1]}] -max 20.0 [get_ports {UART_TX}]
set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[1]}] -min -20.0 [get_ports {UART_TX}]

# Isolate clocks
set_false_path -from [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -to [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[1]}]
set_false_path -from [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}]
