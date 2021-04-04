-- ANSI Terminal
--
-- (c) 2021 Steven A. Falco
--
-- This file contains a control register whereby the Z80 code can control
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
