library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity terminal is
	port (
		CLK12M			: in std_logic
	);
end terminal;

architecture a of terminal is
	component dot_clock
		port
		(
			inclk0		: in std_logic  := '0';
			c0		: out std_logic 
			);
	end component;

	component frame_gen
		port (
			dotClock	: in std_logic;
			hSync		: out std_logic;
			vSync		: out std_logic
		);
	end component;

	signal dotClock			: std_logic;
	signal hSync			: std_logic;
	signal vSync			: std_logic;

begin

	dotClockGen: dot_clock
		port map
		(
			inclk0 => CLK12M,
			c0 => dotClock
		);

	frameGen: frame_gen
		port map
		(
			dotClock => dotClock,
			hSync => hSync,
			vSync => vSync
		);
end a;

