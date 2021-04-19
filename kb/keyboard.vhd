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

-- Keyboard interface.  We return scan codes, and the C code turns them
-- into key strokes.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

-- CPU clock is 88.5 MHz
entity keyboard is
	generic (
		clk_freq	: integer := 88_500_000;	-- Hz
		stable_time	: integer := 5			-- us
	);
	port (
			-- CPU interface
			clk				: in std_logic;
			reset				: in std_logic;
			addrIn				: in std_logic_vector(2 downto 0);
			dataOut				: out std_logic_vector(7 downto 0);
			kbCS				: in std_logic;
			irq				: out std_logic;

			-- Keyboard interface
			ps2_clk				: in std_logic;
			ps2_data			: in std_logic
	);
end keyboard;

architecture a of keyboard is

	signal rx_scan_code_reg			: std_logic_vector(7 downto 0);

	signal clkFlops				: std_logic_vector(1 downto 0);
	signal ctrReset				: std_logic;
	signal cleanedClk			: std_logic;

	type shiftRegFSM_type is (
		shiftRegIdle_state,
		shiftRegActive_state,
		shiftRegComplete_state
	);

	signal shiftRegFSM			: shiftRegFSM_type := shiftRegIdle_state;
	signal shiftReg				: std_logic_vector(8 downto 0);
	signal shiftRegCount			: integer range 0 to 8;

	signal rx_data_ready			: std_logic := '0';
	signal rx_data_ready_D0			: std_logic := '0';
	signal rx_data_ready_D1			: std_logic := '0';
	signal rx_data_ack			: std_logic := '0';

begin

	ctrReset <= clkFlops(0) xor clkFlops(1); -- '1' if state of clock line is changing

	ps2_clk_debounce: process(clk)
		variable count : integer range 0 to clk_freq * stable_time / 1_000_000;
	begin
		if (rising_edge(clk)) then
			if (reset = '1') then
				clkFlops <= "00";
				cleanedClk <= '1'; -- clock should rest high
				count := 0;
			else
				clkFlops(0) <= ps2_clk;
				clkFlops(1) <= clkFlops(0);

				if(ctrReset) then
					count := 0; -- state is changing, clear counter.
				elsif (count < clk_freq * stable_time / 1_000_000) then
					count := count + 1; -- not stable long enough yet.
				else
					cleanedClk <= clkFlops(1);
				end if;
			end if;
		end if;
	end process;

	ps2_FSM: process(cleanedClk, reset, rx_data_ack)
	begin
		if (reset = '1' or rx_data_ack = '1') then
			shiftRegFSM <= shiftRegIdle_state;
			shiftRegCount <= 0;
			rx_data_ready <= '0';
		elsif (falling_edge(cleanedClk)) then
			case shiftRegFSM is
				when shiftRegIdle_state =>
					if(ps2_data = '0') then
						-- First low bit starts us off.
						shiftRegFSM <= shiftRegActive_state;
						shiftRegCount <= 0;
						rx_data_ready <= '0';
					end if;

				when shiftRegActive_state =>
					shiftReg(shiftRegCount) <= ps2_data;
					if (shiftRegCount /= 8) then
						shiftRegCount <= shiftRegCount + 1;
					else
						shiftRegFSM <= shiftRegComplete_state;
					end if;

				when shiftRegComplete_state =>
					-- Stop bit received.  Data is ready.
					rx_data_ready <= '1';

				when others =>
					null;
			end case;
		end if;
	end process;

	cross_to_clk: process(clk)
	begin
		if (rising_edge(clk)) then
			rx_data_ready_D0 <=  rx_data_ready;
			rx_data_ready_D1 <=  rx_data_ready_D0;
		end if;
	end process;

	rx: process(clk)
	begin
		if (rising_edge(clk)) then
			if (reset = '1') then
				rx_scan_code_reg <= (others => '0');
				rx_data_ack <= '0';
				irq <= '0';
			else
				if (rx_data_ready_D1 = '1') then
					-- If data is available, capture it and set an interrupt to the CPU.
					rx_scan_code_reg <= shiftReg(7 downto 0);
					irq <= '1';
				else
					-- Once the CPU does a read, the rx_data_ready signal will clear,
					-- and we can clear the interrupt.
					irq <= '0';
				end if;

				if (kbCS = '1' and addrIn = "000") then
					-- On the first read, send an ACK to the keyboard SM to retire the
					-- interrupt.  The CPU will read the register before returning
					-- from the interrupt.
					rx_data_ack <= '1';
				else
					rx_data_ack <= '0';
				end if;
			end if;

		end if;
	end process;

	output_select: process(all)
	begin
		case addrIn is
			when "000" =>
				dataOut <= rx_scan_code_reg;

			when "001" =>
				dataOut <= "0000000" & rx_data_ready_D1;

			when others =>
				dataOut <= (others => '0');
		end case;
	end process;
end a;
