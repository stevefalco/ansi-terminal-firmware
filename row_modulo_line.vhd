library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

-- Take a row in the range of 0 to 524 and map it to a line in the range
-- of 0 to 23.  Rows 480 to 524 clear the "valid" flag.
-- Also, find the modulo 20 of the row.
entity row_mod_line is
	port (
		rowNum		: in std_logic_vector (9 downto 0);
		lineNum		: out std_logic_vector (4 downto 0);
		moduloNum	: out std_logic_vector (4 downto 0);
		valid		: out std_logic
	);
end row_mod_line;

architecture row_mod_line of row_mod_line is
	component divider
		port (
			denom	: in std_logic_vector (4 downto 0);
			numer	: in std_logic_vector (9 downto 0);
			quotient: out std_logic_vector (9 downtO 0);
			remain	: out std_logic_vector (4 downto 0)
		);
	end component;

	signal quotient		: std_logic_vector (9 downtO 0);
	signal remain		: std_logic_vector (4 downtO 0);
	
begin
	drow: divider
		port map
		(
			denom => "10100",
			numer => rowNum,
			quotient => quotient,
			remain => remain
		);

	rowMap: process(all)
	begin
		lineNum <= quotient(4 downto 0);
		moduloNum <= remain;
		if(rowNum < 480) then
			valid <= '1';
		else
			valid <= '0';
		end if;
	end process;

end row_mod_line;
