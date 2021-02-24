library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity z80_bus is
	port (
		-- CPU Interface.
		cpuAddr		: in std_logic_vector (15 downto 0);
		cpuData		: inout std_logic_vector (7 downto 0);
		cpuRden		: in std_logic;
		cpuWren		: in std_logic;

		-- CPU ROM Interface
		cpuRomQ		: in std_logic_vector (7 downto 0);

		-- CPU RAM Interface
		cpuRamWren	: out std_logic;
		cpuRamQ		: in std_logic_vector (7 downto 0);

		-- VIDEO RAM Interface
		videoRamWren	: out std_logic;
		videoRamQ	: in std_logic_vector (7 downto 0);

		-- UART Interface
		cpuUartCS	: out std_logic;
		cpuUartWR	: out std_logic;
		cpuUartQ	: in std_logic_vector (7 downto 0)
	);
end z80_bus;

architecture a of z80_bus is
begin
	z80_bus_process: process(all)
	begin
		-- Assume no writes
		cpuRamWren <= '0';
		videoRamWren <= '0';
		cpuUartCS <= '0';
		cpuUartWR <= '0';
		cpuData <= (others => 'Z');

		case to_integer(unsigned(cpuAddr(15 downto 0))) is

			when 16#0000# to 16#3FFF# =>
				-- CPU ROM
				if(cpuRden = '0') then
					cpuData <= cpuRomQ;
				end if;

			when 16#4000# to 16#7FFF# =>
				-- CPU RAM
				if(cpuRden = '0') then
					cpuData <= cpuRamQ;
				elsif(cpuWren = '0') then
					cpuRamWren <= '1';
				end if;

			when 16#8000# to 16#BFFF# =>
				-- Video RAM
				if(cpuRden = '0') then
					cpuData <= videoRamQ;
				elsif(cpuWren = '0') then
					videoRamWren <= '1';
				end if;

			when 16#C000# to 16#C007# =>
				-- UART
				if(cpuRden = '0') then
					cpuUartCS <= '1';
					cpuUartWR <= '0';
					cpuData <= cpuUartQ;
				elsif(cpuWren = '0') then
					cpuUartCS <= '1';
					cpuUartWR <= '1';
				end if;

			when others =>
				null;
		end case;
	end process;

end a;
