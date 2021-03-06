-- ANSI Terminal
--
-- (c) 2021 Steven A. Falco
--
-- ANSI Terminal is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- ANSI Terminal is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with ANSI Terminal.  If not, see <https://www.gnu.org/licenses/>.

-- A simple test bench for running the CPU code and looking at
-- the video waveforms.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity testbench is
end testbench;

architecture a of testbench is

	component terminal is
		port (
			CLK12M			: in std_logic;

			-- DIP switches for baud rate
			DIP_SW			: in std_logic_vector(7 downto 0);

			PIXEL_R1		: out std_logic;
			PIXEL_R2		: out std_logic;
			PIXEL_G1		: out std_logic;
			PIXEL_G2		: out std_logic;
			PIXEL_B1		: out std_logic;
			PIXEL_B2		: out std_logic;

			HSYNC			: out std_logic;
			VSYNC			: out std_logic;

			KBD_CLK			: in std_logic;
			KBD_DATA		: in std_logic;

			UART_RX			: in std_logic;
			UART_TX			: out std_logic;
			UART_RTS		: out std_logic;
			UART_CTS		: in std_logic;

			DBG_UART_RX		: in std_logic;
			DBG_UART_TX		: out std_logic;
			DBG_UART_RTS		: out std_logic;
			DBG_UART_CTS		: in std_logic;

			LEDS			: out std_logic_vector(7 downto 0)
		    );
	end component;

	signal CLK12M				: std_logic;

	signal loopback1			: std_logic;
	signal loopback2			: std_logic;
	signal loopback3			: std_logic;
	signal loopback4			: std_logic;

	signal dipSwitches			: std_logic_vector(7 downto 0);

	signal kbdClock				: std_logic := '0';
	signal kbdData				: std_logic := '0';

begin
	term: terminal
	port map
	(
		CLK12M => CLK12M,

		UART_RX => loopback1,
		UART_TX => loopback1,
		UART_RTS => loopback2,
		UART_CTS => loopback2,

		DBG_UART_RX => loopback3,
		DBG_UART_TX => loopback3,
		DBG_UART_RTS => loopback4,
		DBG_UART_CTS => loopback4,

		KBD_CLK => kbdClock,
		KBD_DATA => kbdData,

		DIP_SW => dipSwitches
	);

	-- 12 Mhz
	extClk: process
	begin
		CLK12M <= '0';
		wait for 41.6667 ns;
		CLK12M <= '1';
		wait for 41.6667 ns;
	end process extClk;

	dipSwitches <= "00001010";

end a;
