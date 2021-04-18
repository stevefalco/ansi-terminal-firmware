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

-- This file contains the logic to generate a 1280x1024 VGA (SXGA) frame.
-- We also take care of generating the blank scan lines between rows of
-- text.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

-- Everything is based off the pixel frequency of 108 MHz and a
-- 1688x1066 raster.
-- 
-- General timing
-- ==============
-- Pixel freq.		108.0 MHz
-- Line rate		63.98 kHz (108E6 / 1688 columns)
-- Screen refresh rate	60.02 Hz (63.981E3 / 1066 rows)
-- Pixel period		9.2592 ns (1 / 108E6)
-- 
-- Horizontal timing (horizontal sync pulse is positive)
-- 
-- Scanline part	Pixels	Time [µs]
-- =======================================
-- Visible area	1280	11.8519
-- Front porch	48	 0.4444
-- Sync pulse	112	 1.0370
-- Back porch	248	 2.2963
-- Whole line	1688	15.6296
-- Idle time at end of line = 2.2963 us
-- 
-- Vertical timing (vertical sync pulse is positive)
-- 
-- Frame part	Lines	Time [ms]
-- =================================
-- Visible area	1024	16.00474
-- Front porch	1	 0.01563
-- Sync pulse	3	 0.04689
-- Back porch	38	 0.59393
-- Whole frame	1066	16.66119
-- Idle time at end of frame = 0.5939 ms

entity frame_gen is
	generic (
		columnMax		: integer := 1687; -- 1688 columns, 0 to 1687
		rowMax			: integer := 1065; -- 1066 rows, 0 to 1065
		lastVisibleRow		: integer := 1023; -- 1024 visible rows, 0 to 1023
		mod42Max		: integer := 41;   -- 42 rows per line, 0 to 41

		-- One line of active video is 1280 pels, 0 to 1279
		hFrontPorchStart	: integer := 1280;
		hSyncStart		: integer := (1280 + 48); -- hsync starts after 48-pel front porch
		hBackPorchStart		: integer := (1280 + 48 + 112); -- hsync is 112 pels wide

		-- One frame of active video is 1024 lines, 0 to 1023
		vFrontPorchStart	: integer := 1024;
		vSyncStart		: integer := (1024 + 1); -- vsync starts after 1-line front porch
		vBackPorchStart		: integer := (1024 + 1 + 3) -- vsync is 3 lines wide
	);

	port (
		clear			: in std_logic;
		dotClock		: in std_logic;
		hSync			: out std_logic;
		vSync			: out std_logic;
		columnAddress		: out std_logic_vector (10 downto 0);
		rowAddress		: out std_logic_vector (10 downto 0);
		lineAddress		: out std_logic_vector (9 downto 0);
		blanking		: out std_logic
	);
end frame_gen;

architecture a of frame_gen is
begin

	frameProcess: process(dotClock)

	variable columnCounter		: unsigned (10 downto 0); -- 0 to 1687
	variable rowCounter		: unsigned (10 downto 0); -- 0 to 1065
	variable lineCounter		: unsigned (9 downto 0); -- 0 to 767
	variable mod42Counter		: unsigned (5 downto 0); -- 0 to 41

	begin
		if(rising_edge(dotClock)) then
			if(clear = '1') then
				columnCounter := to_unsigned(0, columnCounter'length);
				rowCounter := to_unsigned(0, rowCounter'length);
				lineCounter := to_unsigned(0, lineCounter'length);
				mod42Counter := "000000";
				hsync <= '0';
				vsync <= '0';
			else
				if(columnCounter < columnMax) then
					columnCounter := columnCounter + 1;
				else
					-- Completed a line.
					columnCounter := to_unsigned(0, columnCounter'length);

					-- Characters are 32 rows high, but we want a spacing
					-- of 10 blank rows between lines of characters.
					if(mod42Counter < mod42Max) then
						mod42Counter := mod42Counter + 1;
					else
						mod42Counter := "000000";
					end if;

					if(mod42Counter < 32) then
						if(rowCounter < lastVisibleRow) then
							lineCounter := lineCounter + 1;
						else
							lineCounter := to_unsigned(0, lineCounter'length);
						end if;
					end if;
					
					if(rowCounter < rowMax) then
						rowCounter := rowCounter + 1;
					else
						-- Top of frame.  Reset everything.
						columnCounter := to_unsigned(0, columnCounter'length);
						rowCounter := to_unsigned(0, rowCounter'length);
						lineCounter := to_unsigned(0, lineCounter'length);
						mod42Counter := "000000";
						hsync <= '0';
						vsync <= '0';
					end if;
				end if;

				if(columnCounter >= hSyncStart and columnCounter < hBackPorchStart) then
					-- sync is active-high
					hsync <= '1';
				else
					hsync <= '0';
				end if;

				if(rowCounter >= vSyncStart and rowCounter < vBackPorchStart) then
					-- sync is active-high
					vsync <= '1';
				else
					vsync <= '0';
				end if;

				if(columnCounter < hFrontPorchStart and mod42Counter < 32 and rowCounter < vFrontPorchStart) then
					blanking <= '0';
				else
					blanking <= '1';
				end if;
			end if;

			columnAddress <= std_logic_vector(columnCounter);
			rowAddress <= std_logic_vector(rowCounter);
			lineAddress <= std_logic_vector(lineCounter);
		end if;
	end process;
end a;

