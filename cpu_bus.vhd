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

-- This file controls which peripheral is to drive the cpu input bus,
-- and also generates the necessary peripheral control signals.
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
		cpuInt_n	: out std_logic_vector (2 downto 0);
		cpuVPAn		: out std_logic;
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
					cpuUartCS <= '0';
					cpuUartWR <= '0';
					cpuKbCS <= '0';
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
									cpuUartCS <= '1';
									cpuUartWR <= '0';
									cpuDataIn(15 downto 8) <= cpuUartQ;
								elsif(cpuRWn = '0') then
									cpuUartCS <= '1';
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
									cpuKbCS <= '1';
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
					cpuUartCS <= '0';
					cpuUartWR <= '0';
					cpuKbCS <= '0';
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

	-- We could use multiple interrupt levels, but that is unnecessary.  Instead,
	-- we just let the CPU poll both devices.
	-- 
	-- The peripheral interrupt lines are active-high, but the CPU interrupts are
	-- active-low.  We use "101" which means "interrupt 2".
	--
	-- The CPU normally expects peripherals to respond to an Interrupt Acknowledge
	-- (IACK) cycle.  However, if we assert cpuVPAn, then the CPU ignores the IACK
	-- and instead "autovectors".  That is sufficient for our purposes.
	cpu_int_process: process(all)
	begin
		if(cpuUartInt = '1' or cpuKbInt = '1') then
			cpuInt_n <= "101";
			cpuVPAn <= '0';
		else
			cpuInt_n <= "111";
			cpuVPAn <= '1';
		end if;
	end process;

end a;
