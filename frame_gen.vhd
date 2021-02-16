library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity frame_gen is
	generic (
		columnMax		: integer := 800;
		rowMax			: integer := 525
	);

	port (
		dotClock		: in std_logic;
		hSync			: out std_logic;
		vSync			: out std_logic
	);
end frame_gen;

architecture a of frame_gen is
	signal columnCounter		: unsigned (9 downto 0);
	signal rowCounter		: unsigned (9 downto 0);
begin

	frameProcess: process(dotClock)
	begin
		if(rising_edge(dotClock)) then
			if(columnCounter < columnMax) then
				columnCounter <= columnCounter + 1;
			else
				columnCounter <= to_unsigned(0, columnCounter'length);
				if(rowCounter < rowMax) then
					rowCounter <= rowCounter + 1;
				else
					rowCounter <= to_unsigned(0, rowCounter'length);
				end if;
			end if;
		end if;
	end process;
end a;

