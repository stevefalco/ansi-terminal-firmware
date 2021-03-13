library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity z80_bus is
	port (
		-- CPU Interface.
		cpuClock	: in std_logic;
		cpuAddr		: in std_logic_vector (15 downto 0);
		cpuData		: inout std_logic_vector (7 downto 0);
		cpuRden		: in std_logic;
		cpuWren		: in std_logic;
		cpuInt_n	: out std_logic;

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
		cpuUartQ	: in std_logic_vector (7 downto 0);
		cpuUartInt	: in std_logic;

		-- Keyboard Interface
		cpuKbCS		: out std_logic;
		cpuKbQ		: in std_logic_vector (7 downto 0);
		cpuKbInt	: in std_logic;

		-- DIP Switch Interface
		cpuDipQ		: in std_logic_vector (7 downto 0)
	);
end z80_bus;

architecture a of z80_bus is

	signal cpuUartCS_D0	: std_logic;
	signal cpuUartCS_D1	: std_logic;

	signal cpuKbCS_D0	: std_logic;
	signal cpuKbCS_D1	: std_logic;

begin
	z80_bus_process: process(all)
	begin
		-- Assume no writes, no uart access
		cpuRamWren <= '0';
		videoRamWren <= '0';
		cpuUartCS_D0 <= '0';
		cpuUartWR <= '0';
		cpuKbCS_D0 <= '0';
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
					cpuUartCS_D0 <= '1';
					cpuUartWR <= '0';
					cpuData <= cpuUartQ;
				elsif(cpuWren = '0') then
					cpuUartCS_D0 <= '1';
					cpuUartWR <= '1';
				end if;

			when 16#C010# =>
				-- DIP Switches
				if(cpuRden = '0') then
					cpuData <= cpuDipQ;
				end if;

			when 16#C020# to 16#C027# =>
				-- Keyboard
				if(cpuRden = '0') then
					cpuKbCS_D0 <= '1';
					cpuData <= cpuKbQ;
				end if;

			when others =>
				null;
		end case;
	end process;

	-- In this discussion, we consider that CPU clock cycles begin with a
	-- rising clock edge, and we call that edge "Rising Edge #1".  "Falling
	-- edge #1" occurs in the middle of the first CPU clock cycle.  CPU
	-- clock cycles are also known as T-States.
	--
	-- READ Cycles:
	--
	-- The CPU puts out an address on Rising Edge #1.  Then, on Falling
	-- Edge #1 it asserts nRD.  Then, on Falling Edge #3 it samples the
	-- data and deasserts nRD.  Thus, nRD is low for Rising Edge #2 and
	-- Rising Edge #3.
	--
	-- That is a problem for the UART, because it will pop received characters
	-- out of its FIFO on each rising edge, and so we would lose a character.
	-- When reading from the UART, we therefore shorten UART CS by masking
	-- out the first half of it.
	--
	-- WRITE Cycles:
	--
	-- The CPU puts out an address on Rising Edge #1.  Then, it puts out
	-- the data to be written on Falling Edge #1.  It then asserts the nWR
	-- signal on Falling Edge #2 and deasserts it on Falling Edge #3.
	--
	-- Thus, the UART will capture the data on Rising Edge #3, and no adjustment
	-- to UART CS is needed when writing.
	uartDelay: process(cpuClock)
	begin
		if (falling_edge(cpuClock)) then
			cpuUartCS_D1 <= cpuUartCS_D0;
		end if;
	end process;
	cpuUartCS <= cpuUartCS_D0 and cpuUartCS_D1 when cpuRden = '0' else cpuUartCS_D0;

	-- Similar to the UART case, we want to assert the KB CS on the second
	-- cycle.  The keyboard register interface will capture the various
	-- data, so they will persist until the next "data ready".
	kbDelay: process(cpuClock)
	begin
		if (falling_edge(cpuClock)) then
			cpuKbCS_D1 <= cpuKbCS_D0;
		end if;
	end process;
	cpuKbCS <= cpuKbCS_D0 and cpuKbCS_D1;

	-- We have one interrupt to the CPU, and only two devices that generate
	-- interrupts.  So, we just let the CPU poll both devices.
	z80_int_process: process(all)
	begin
		if(cpuUartInt = '1' or cpuKbInt = '1') then
			cpuInt_n <= '0';
		else
			cpuInt_n <= '1';
		end if;
	end process;

end a;
