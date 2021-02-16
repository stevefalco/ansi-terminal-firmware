library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity testbench is
end testbench;

architecture a of testbench is

	component terminal is
		port (
			CLK12M			: in std_logic
		    );
	end component;

	signal CLK12M				: std_logic;

begin
	term: terminal
	port map
	(
		CLK12M => CLK12M
	);

	-- 12 Mhz
	extClk: process
	begin
		CLK12M <= '0';
		wait for 41.6667 ns;
		CLK12M <= '1';
		wait for 41.6667 ns;
	end process extClk;

end a;
