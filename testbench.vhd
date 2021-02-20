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

			-- The FPGA can drive 8 mA per pin.  The RGB pins drive a 75 ohm
			-- load, and we need to get it to 0.7 volts for "white".
			--
			-- That requires around 9 mA, which is a bit more than the FPGA
			-- wants to provide.  We will parallel two outputs, each with a
			-- separate series resistor.  We could even get some greyscale
			-- output if desired, by wiring an R-2R ladder.  I've seen people
			-- use 3 or 4 independent bits per color, but we don't need that.
			PIXEL_R1		: out std_logic;
			PIXEL_R2		: out std_logic;
			PIXEL_G1		: out std_logic;
			PIXEL_G2		: out std_logic;
			PIXEL_B1		: out std_logic;
			PIXEL_B2		: out std_logic;

			HSYNC			: out std_logic;
			VSYNC			: out std_logic
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
