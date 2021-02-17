library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity pel_select is
	port (
		clock		: in std_logic;
		inByte		: in std_logic_vector (7 downto 0);
		sel		: in std_logic_vector (2 downto 0);
		outBit		: out std_logic
	);
end pel_select;

architecture pel_select of pel_select is
begin

	pel: process(clock)
	begin
		if (rising_edge(clock)) then
			case sel is
				when "000" => outBit <= inByte(0);
				when "001" => outBit <= inByte(1);
				when "010" => outBit <= inByte(2);
				when "011" => outBit <= inByte(3);
				when "100" => outBit <= inByte(4);
				when "101" => outBit <= inByte(5);
				when "110" => outBit <= inByte(6);
				when "111" => outBit <= inByte(7);

				when others => outBit <= '0';
			end case;
		end if;
	end process;

end pel_select;
