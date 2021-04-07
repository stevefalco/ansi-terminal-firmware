-- ANSI Terminal
--
-- (c) 2021 Steven A. Falco
--
-- This file contains a register to write to the LEDs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity led_reg is
	port (
		clk		: in std_logic;
		reset		: in std_logic;
		D		: in std_logic_vector (7 downto 0);
		WR		: in std_logic;

		Q		: out std_logic_vector (7 downto 0)
	);
end led_reg;

architecture a of led_reg is
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
