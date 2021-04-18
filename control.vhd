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

-- This file contains a control register whereby the C code can control
-- the hardware.
--
-- So far, we are only using this to control a screen saver that is reset by
-- keyboard input.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity control is
	port (
		clk		: in std_logic;
		reset		: in std_logic;
		D		: in std_logic_vector (7 downto 0);
		WR		: in std_logic;

		Q		: out std_logic_vector (7 downto 0)
	);
end control;

architecture a of control is
begin
	control_process: process(clk)
	begin
		if(rising_edge(clk)) then
			if(reset = '1') then
				Q <= (others => '0');
			elsif(WR = '1') then
				Q <= D;
			end if;
		end if;
	end process;

end a;
