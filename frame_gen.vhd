library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

-- The FPGA can synthesize a 25.2 MHz clock from the on-board 12 MHz
-- oscillator.  Ideally, we'd choose 25.175 MHz, for a 59.94 Hz frame
-- rate, because that is the industry standard, but we will instead
-- wind up with exactly 60 Hz.  Close enough.
-- 
-- Everything is based off the pixel frequency and an 800x525 raster.
-- 
-- General timing
-- ==============
-- Pixel freq.		25.2 MHz
-- Line rate		31.500 kHz (25.2E6 / 800 columns)
-- Screen refresh rate	60 Hz (31.5E3 / 525 rows)
-- Pixel period		39.6 ns (1 / 25.2E6)
-- 
-- Horizontal timing (horizontal sync pulse is negative)
-- 
-- Scanline part	Pixels	Time [µs]
-- =======================================
-- Visible area	640	25.3440
-- Front porch	16	 0.6336
-- Sync pulse	96	 3.8016
-- Back porch	48	 1.9008
-- Whole line	800	31.6800
-- Idle time at end of line = 6.3360 us
-- 
-- Vertical timing (vertical sync pulse is negative)
-- 
-- Frame part	Lines	Time [ms]
-- =================================
-- Visible area	480	15.20640
-- Front porch	10	 0.31680
-- Sync pulse	2	 0.06336
-- Back porch	33	 1.04544
-- Whole frame	525	16.63200
-- Idle time at end of frame = 1.42560 ms

entity frame_gen is
	generic (
		columnMax		: integer := 799; -- 800 columns, 0 to 799
		rowMax			: integer := 524; -- 525 rows, 0 to 524

		-- One line of active video is 680 pels, 0 to 639
		hSyncStart		: integer := (640 + 16); -- hsync starts after 16-pel front porch
		hBackPorchStart		: integer := (640 + 16 + 96); -- hsync is 96 pels wide

		-- One frame of active video is 480 lines, 0 to 479
		vSyncStart		: integer := (480 + 10); -- vsync starts after 10-line front porch
		vBackPorchStart		: integer := (480 + 10 + 2) -- vsync is 2 lines wide
	);

	port (
		clear			: in std_logic;
		dotClock		: in std_logic;
		hSync			: out std_logic;
		vSync			: out std_logic;
		columnAddress		: out std_logic_vector (9 downto 0);
		rowAddress		: out std_logic_vector (9 downto 0)
	);
end frame_gen;

architecture a of frame_gen is
begin

	frameProcess: process(dotClock)

	variable columnCounter		: unsigned (9 downto 0); -- 0 to 799
	variable rowCounter		: unsigned (9 downto 0); -- 0 to 524

	begin
		if(rising_edge(dotClock)) then
			if(clear = '1') then
				columnCounter := to_unsigned(0, columnCounter'length);
				rowCounter := to_unsigned(0, rowCounter'length);
				hsync <= '1';
				vsync <= '1';
			else
				if(columnCounter < columnMax) then
					columnCounter := columnCounter + 1;
				else
					columnCounter := to_unsigned(0, columnCounter'length);

					if(rowCounter < rowMax) then
						rowCounter := rowCounter + 1;
					else
						rowCounter := to_unsigned(0, rowCounter'length);
					end if;
				end if;

				if(columnCounter >= hSyncStart and columnCounter < hBackPorchStart) then
					-- sync is active-low
					hsync <= '0';
				else
					hsync <= '1';
				end if;

				if(rowCounter >= vSyncStart and rowCounter < vBackPorchStart) then
					-- sync is active-low
					vsync <= '0';
				else
					vsync <= '1';
				end if;
			end if;

			columnAddress <= std_logic_vector(columnCounter);
			rowAddress <= std_logic_vector(rowCounter);
		end if;
	end process;
end a;

