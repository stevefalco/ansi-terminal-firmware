-- ANSI Terminal
--
-- (c) 2021 Steven A. Falco
--
-- The Z80 core that we are using requires a tri-state bus.  This
-- file controls which peripheral is to drive the bus, and also
-- generates the necessary peripheral control signals.
--
-- We also generate a shared interrupt line.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity cpu_bus is
	port (
		-- CPU Interface.
		cpuClock	: in std_logic;
		cpuClear	: in std_logic;
		cpuByteEnables	: in std_logic_vector (1 downto 0);
		cpuAddr		: in std_logic_vector (23 downto 1);
		cpuDataIn	: out std_logic_vector (15 downto 0);
		cpuRWn		: in std_logic;
		cpuInt		: out std_logic_vector (2 downto 0);
		cpuDTACKn	: out std_logic;
		cpuASn		: in std_logic;

		-- CPU ROM Interface
		cpuRomQ		: in std_logic_vector (15 downto 0);

		-- CPU RAM Interface
		cpuRamWren	: out std_logic;
		cpuRamQ		: in std_logic_vector (15 downto 0);

		-- VIDEO RAM Interface
		videoRamWren	: out std_logic;
		videoRamQ	: in std_logic_vector (15 downto 0);

		-- UART Interface
		cpuUartCS	: out std_logic;
		cpuUartWR	: out std_logic;
		cpuUartQ	: in std_logic_vector (7 downto 0);
		cpuUartInt	: in std_logic;

		-- Keyboard Interface
		cpuKbCS		: out std_logic;
		cpuKbQ		: in std_logic_vector (7 downto 0);
		cpuKbInt	: in std_logic;

		-- LED Interface
		cpuLEDsWR	: out std_logic;

		-- DIP Switch Interface
		cpuDipQ		: in std_logic_vector (7 downto 0);

		-- Control Register Interface
		cpuControlWR	: out std_logic
	);
end cpu_bus;

architecture a of cpu_bus is

	signal cpuUartCS_D0	: std_logic;
	signal cpuUartCS_D1	: std_logic;

	signal cpuKbCS_D0	: std_logic;
	signal cpuKbCS_D1	: std_logic;

	type bus_FSM_type is (
		busIdle_state,
		busActive_state
	);

	signal busFSM		: bus_FSM_type := busIdle_state;

begin
	cpu_bus_process: process(cpuClock)
	begin
		if rising_edge(cpuClock) then
			case busFSM is

				when busIdle_state =>
					cpuRamWren <= '0';
					videoRamWren <= '0';
					cpuUartCS_D0 <= '0';
					cpuUartWR <= '0';
					cpuKbCS_D0 <= '0';
					cpuControlWR <= '0';
					cpuLEDsWR <= '0';
					cpuDataIn <= (others => '0');
					cpuDTACKn <= '1';

					if(cpuASn = '0' and cpuByteEnables /= "00") then
						busFSM <= busActive_state;
						-- We are faster than the CPU, so we ack the cycle
						-- immediately.  I might even nail the dtack to 0.
						-- We'll see...
						cpuDTACKn <= '0';

						-- Address bus is (23 downto 1), so all addresse
						-- constants here are divided by 2.
						--
						-- I could spread things out more, since I have
						-- plenty of address bits, but the FPGA doesn't
						-- have much internal memory left, so it wouldn't
						-- really be useful.
						case to_integer(unsigned(cpuAddr)) is

							when 16#000000# to 16#001FFF# =>
								-- CPU ROM @ 0x0000 to 0x3fff
								-- 8192 16-bit words
								if(cpuRWn = '1') then
									cpuDataIn <= cpuRomQ;
								end if;

							when 16#002000# to 16#003FFF# =>
								-- CPU RAM @ 0x4000 to 0x7fff
								-- 8192 16-bit words
								if(cpuRWn = '1') then
									cpuDataIn <= cpuRamQ;
								elsif(cpuRWn = '0') then
									cpuRamWren <= '1';
								end if;

							when 16#004000# to 16#00477F# =>
								-- Video RAM @ 0x8000 to 0x8eff
								-- 1920 16-bit words
								if(cpuRWn = '1') then
									cpuDataIn <= videoRamQ;
								elsif(cpuRWn = '0') then
									videoRamWren <= '1';
								end if;

							when 16#006000# to 16#006007# =>
								-- UART @ 0xc000 to 0xc00f
								-- 8 bytes, even addresses only
								if(cpuRWn = '1') then
									cpuUartCS_D0 <= '1';
									cpuUartWR <= '0';
									cpuDataIn(15 downto 8) <= cpuUartQ;
								elsif(cpuRWn = '0') then
									cpuUartCS_D0 <= '1';
									cpuUartWR <= '1';
								end if;

							when 16#006010# =>
								-- DIP Switches @ 0xc020
								-- 1 byte
								if(cpuRWn = '1') then
									cpuDataIn(15 downto 8) <= cpuDipQ;
								end if;

							when 16#006020# to 16#006027# =>
								-- Keyboard @ 0xc040 to 0xc04f
								-- 8 bytes, even addresses only
								if(cpuRWn = '1') then
									cpuKbCS_D0 <= '1';
									cpuDataIn(15 downto 8) <= cpuKbQ;
								end if;

							when 16#006030# =>
								-- Control Register Bits @ 0xc060
								-- 1 byte
								if(cpuRWn = '0') then
									cpuControlWR <= '1';
								end if;

							when 16#006040# =>
								-- LED Register Bits @0xc080
								-- 1 byte
								if(cpuRWn = '0') then
									cpuLEDsWR <= '1';
								end if;

							when others =>
								null;
						end case;
					end if;

				when busActive_state =>
					cpuRamWren <= '0';
					videoRamWren <= '0';
					cpuUartCS_D0 <= '0';
					cpuUartWR <= '0';
					cpuKbCS_D0 <= '0';
					cpuControlWR <= '0';
					cpuLEDsWR <= '0';

					if(cpuASn = '1') then
						busFSM <= busIdle_state;
						cpuDTACKn <= '1';
					end if;

				when others =>
					null;

			end case;
		end if;
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
	--
	-- When reading from the UART, we therefore shorten UART CS by masking
	-- out the first half of it.  The keyboard has a similar restriction,
	-- so we shorten its CS too.
	--
	-- WRITE Cycles:
	--
	-- The CPU puts out an address on Rising Edge #1.  Then, it puts out
	-- the data to be written on Falling Edge #1.  It then asserts the nWR
	-- signal on Falling Edge #2 and deasserts it on Falling Edge #3.
	--
	-- Thus, the UART will capture the data on Rising Edge #3, and no adjustment
	-- to UART CS is needed when writing.
--	uartDelay: process(cpuClock)
--	begin
--		if (falling_edge(cpuClock)) then
--			cpuUartCS_D1 <= cpuUartCS_D0;
--		end if;
--	end process;
--	cpuUartCS <= cpuUartCS_D0 and cpuUartCS_D1 when cpuRWn = '1' else cpuUartCS_D0;
--
--	-- Similar to the UART case, we want to assert the KB CS on the second
--	-- cycle.  The keyboard register interface will capture the various
--	-- data, so they will persist until the next "data ready".
--	--
--	-- We don't support writing to the keyboard, although in theory we could.
--	kbDelay: process(cpuClock)
--	begin
--		if (falling_edge(cpuClock)) then
--			cpuKbCS_D1 <= cpuKbCS_D0;
--		end if;
--	end process;
--	cpuKbCS <= cpuKbCS_D0 and cpuKbCS_D1;
--
--	-- We use one interrupt to the CPU, and only two devices that generate
--	-- interrupts.  So, we just let the CPU poll both devices.
--	cpu_int_process: process(all)
--	begin
--		if(cpuUartInt = '1' or cpuKbInt = '1') then
--			cpuInt(0) <= '1';
--		else
--			cpuInt(0) <= '0';
--		end if;
--		-- FIXME
--		cpuInt <= "111";
--	end process;

end a;