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

-- Select a single pel from a character.  The characters are in a
-- 16x32 matrix.  We are given one 16-bit row of a character, and
-- we return the correct bit.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity pel_select is
	port (
		clock		: in std_logic;
		inWord		: in std_logic_vector (15 downto 0);
		sel		: in std_logic_vector (3 downto 0);
		outBit		: out std_logic
	);
end pel_select;

architecture a of pel_select is
begin

	pel: process(clock)
	begin
		if (rising_edge(clock)) then
			case sel is
				when "0000" => outBit <= inWord(15);
				when "0001" => outBit <= inWord(14);
				when "0010" => outBit <= inWord(13);
				when "0011" => outBit <= inWord(12);
				when "0100" => outBit <= inWord(11);
				when "0101" => outBit <= inWord(10);
				when "0110" => outBit <= inWord(9);
				when "0111" => outBit <= inWord(8);

				when "1000" => outBit <= inWord(7);
				when "1001" => outBit <= inWord(6);
				when "1010" => outBit <= inWord(5);
				when "1011" => outBit <= inWord(4);
				when "1100" => outBit <= inWord(3);
				when "1101" => outBit <= inWord(2);
				when "1110" => outBit <= inWord(1);
				when "1111" => outBit <= inWord(0);

				when others => outBit <= '0';
			end case;
		end if;
	end process;

end a;
