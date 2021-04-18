# ANSI Terminal
#
# (c) 2021 Steven A. Falco
#
# ANSI Terminal is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ANSI Terminal is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ANSI Terminal.  If not, see <https://www.gnu.org/licenses/>.

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
create_clock -name {cleanedClk} -period 20kHz [get_keepers {keyboard:cpuKB|cleanedClk}]

derive_pll_clocks
derive_clock_uncertainty

#**************************************************************
# Set Input Delay
#**************************************************************

#**************************************************************
# Set Output Delay
#**************************************************************

set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -max 1.0 [get_ports {PIXEL_*}]
set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -min -1.0 [get_ports {PIXEL_*}]

set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -max 1.0 [get_ports {HSYNC VSYNC}]
set_output_delay -add_delay -clock [get_clocks {dotClockGen|altpll_component|auto_generated|pll1|clk[0]}] -min -1.0 [get_ports {HSYNC VSYNC}]

# Isolate clocks
set_clock_groups -exclusive \
	-group  {dotClockGen|altpll_component|auto_generated|pll1|clk[0]} \
	-group  {cpuClockGen|altpll_component|auto_generated|pll1|clk[0]} \
	-group {cleanedClk}

# Don't cares
set_false_path -from [get_ports {UART_RX UART_CTS}] -to *
set_false_path -from * -to [get_ports {UART_TX UART_RTS}]

set_false_path -from [get_ports {KBD_CLK}] -to *
set_false_path -from * -to [get_ports {KBD_CLK}]

set_false_path -from [get_ports {KBD_DATA}] -to *
set_false_path -from * -to [get_ports {KBD_DATA}]

set_false_path -from [get_ports {DIP_SW[*]}] -to *

set_false_path -from * -to [get_ports {LEDS[*]}]
