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

-- Top level VHDL for the ANSI terminal.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity terminal is
	port (
		CLK12M			: in std_logic;				-- M2

		-- DIP switches for baud rate
		DIP_SW			: in std_logic_vector(7 downto 0);	-- J14, L2, K2, J2, J1, P2, N1, N2

		-- The FPGA can drive 8 mA per pin.  The RGB pins drive a 75 ohm
		-- load, and we need to get it to 0.7 volts for "white".
		--
		-- That requires around 9 mA, which is a bit more than the FPGA
		-- wants to provide.  We will parallel two outputs, each with a
		-- separate series resistor.
		PIXEL_R1		: out std_logic;			-- P14
		PIXEL_R2		: out std_logic;			-- R14
		PIXEL_G1		: out std_logic;			-- R13
		PIXEL_G2		: out std_logic;			-- T14
		PIXEL_B1		: out std_logic;			-- R12
		PIXEL_B2		: out std_logic;			-- T13

		HSYNC			: out std_logic;			-- T15
		VSYNC			: out std_logic;			-- N16

		KBD_CLK			: in std_logic;				-- K15
		KBD_DATA		: in std_logic;				-- K16

		UART_RX			: in std_logic;				-- L16
		UART_TX			: out std_logic;			-- L15
		UART_RTS		: out std_logic;			-- P1
		UART_CTS		: in std_logic;				-- R1

		LEDS			: out std_logic_vector(7 downto 0)	-- M6, T4, T3, R3, T2, R4, N5, N3
	);
end terminal;

architecture a of terminal is
	component dot_clock
		port
		(
			inclk0		: in std_logic;
			c0		: out std_logic
		);
	end component;

	component cpu_clock
		port
		(
			inclk0		: in std_logic;
			c0		: out std_logic
		);
	end component;

	component frame_gen
		port (
			clear		: in std_logic;
			dotClock	: in std_logic;
			hSync		: out std_logic;
			vSync		: out std_logic;
			columnAddress	: out std_logic_vector (10 downto 0);
			rowAddress	: out std_logic_vector (10 downto 0);
			lineAddress	: out std_logic_vector (9 downto 0);
			blanking	: out std_logic
		);
	end component;

	component char_rom
		port (
			address		: in std_logic_vector (12 downto 0);
			clock		: in std_logic;
			q		: out std_logic_vector (15 downto 0)
		);
	end component;

	component frame_ram
		port (
			address_a	: in std_logic_vector (10 downto 0);
			address_b	: in std_logic_vector (10 downto 0);
			byteena_b	: in std_logic_vector (1 downto 0);
			clock_a		: in std_logic;
			clock_b		: in std_logic;
			data_a		: in std_logic_vector (15 downto 0);
			data_b		: in std_logic_vector (15 downto 0);
			wren_a		: in std_logic;
			wren_b		: in std_logic;
			q_a		: out std_logic_vector (15 downto 0);
			q_b		: out std_logic_vector (15 downto 0)
		);
	end component;

	component pel_select
		port (
			clock		: in std_logic;
			inWord		: in std_logic_vector (15 downto 0);
			sel		: in std_logic_vector (3 downto 0);
			outBit		: out std_logic
		);
	end component;

	component fx68k
		port (
			clk		: in std_logic;
			HALTn		: in std_logic; -- Used for single step only. Force high if not used
			extReset	: in std_logic; -- External sync reset on emulated system
			pwrUp		: in std_logic; -- Asserted together with reset on emulated system coldstart	
			enPhi1		: in std_logic; -- Clock enables. Next cycle is PHI1 or PHI2
			enPhi2		: in std_logic; -- Clock enables. Next cycle is PHI1 or PHI2

			eRWn		: out std_logic;
			ASn		: out std_logic;
			LDSn		: out std_logic;
			UDSn		: out std_logic;
			E		: out std_logic;
			VMAn		: out std_logic;
	
			-- Next cycle would be raising/falling edge of E output
			-- output E_PosClkEn, E_NegClkEn,

			FC0		: out std_logic;
			FC1		: out std_logic;
			FC2		: out std_logic;
			BGn		: out std_logic;
			oRESETn		: out std_logic;
			oHALTEDn	: out std_logic;

			DTACKn		: in std_logic;
			VPAn		: in std_logic;
			BERRn		: in std_logic;
			BRn		: in std_logic;
			BGACKn		: in std_logic;
			IPL0n		: in std_logic;
			IPL1n		: in std_logic;
			IPL2n		: in std_logic;

			iEdb		: in std_logic_vector(15 downto 0);
			oEdb		: out std_logic_vector(15 downto 0);
			eab		: out std_logic_vector(23 downto 1)
		);
	end component;

	component cpu_rom
		port (
			address		: in std_logic_vector (12 downto 0);
			clock		: in std_logic;
			q		: out std_logic_vector (15 downto 0)
		);
	end component;

	component cpu_ram
		port (
			address		: in std_logic_vector (12 downto 0);
			byteena		: in std_logic_vector (1 downto 0);
			clock		: in std_logic;
			data		: in std_logic_vector (15 downto 0);
			wren		: in std_logic;
			q		: out std_logic_vector (15 downto 0)
		);
	end component;

	component cpu_bus
		port (
			-- CPU Interface.
			cpuClock	: in std_logic;
			cpuClear	: in std_logic;
			cpuByteEnables	: in std_logic_vector (1 downto 0);
			cpuAddr		: in std_logic_vector (23 downto 1);
			cpuDataIn	: out std_logic_vector (15 downto 0);
			cpuRWn		: in std_logic;
			cpuInt_n	: out std_logic_vector(2 downto 0);
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
	end component;

	component led_reg is
		port(
			clk		: in std_logic;
			reset		: in std_logic;
			D		: in std_logic_vector (7 downto 0);
			WR		: in std_logic;

			Q		: out std_logic_vector (7 downto 0)
		);
	end component;

	component gh_uart_16550 is
		port(
			clk     	: in std_logic;
			BR_clk  	: in std_logic;
			rst     	: in std_logic;
			CS      	: in std_logic;
			WR      	: in std_logic;
			ADD     	: in std_logic_vector(2 downto 0);
			D       	: in std_logic_vector(7 downto 0);

			sRX		: in std_logic;
			CTSn    	: in std_logic := '1';
			DSRn    	: in std_logic := '1';
			RIn     	: in std_logic := '1';
			DCDn    	: in std_logic := '1';

			sTX     	: out std_logic;
			DTRn    	: out std_logic;
			RTSn    	: out std_logic;
			OUT1n   	: out std_logic;
			OUT2n   	: out std_logic;
			TXRDYn  	: out std_logic;
			RXRDYn  	: out std_logic;

			IRQ     	: out std_logic;
			B_CLK   	: out std_logic;
			RD      	: out std_logic_vector(7 downto 0)
		);
	end component;

	component keyboard is
		port (
			-- CPU interface
			clk		: in std_logic;
			reset		: in std_logic;
			addrIn		: in std_logic_vector(2 downto 0);
			dataOut		: out std_logic_vector(7 downto 0);
			kbCS		: in std_logic;
			irq		: out std_logic;

			-- Keyboard interface
			ps2_clk		: in std_logic;
			ps2_data	: in std_logic
		);
	end component;

	component control is
		port (
			clk		: in std_logic;
			reset		: in std_logic;
			D		: in std_logic_vector (7 downto 0);
			WR		: in std_logic;

			Q		: out std_logic_vector (7 downto 0)
		);
	end component;

	signal cpuClock			: std_logic := '0';
	signal enPhi1			: std_logic := '0';
	signal enPhi2			: std_logic := '0';
	signal extReset			: std_logic := '1';
	signal DTACKn			: std_logic := '1';
	signal BERRn			: std_logic := '1';
	signal BRn			: std_logic := '1';
	signal BGACKn			: std_logic := '1';

	-- Outputs
	signal eRWn			: std_logic;
	signal ASn			: std_logic;
	signal E			: std_logic;
	signal VMAn			: std_logic;
	signal FC0			: std_logic;
	signal FC1			: std_logic;
	signal FC2			: std_logic;
	signal BGn			: std_logic;
	signal oRESETn			: std_logic;
	signal oHALTEDn			: std_logic;

	-- Buses
	signal iEdb			: std_logic_vector(15 downto 0) := (others => '0');	-- Input data
	signal oEdb			: std_logic_vector(15 downto 0) := (others => '0');	-- Output data
	signal eab			: std_logic_vector(23 downto 1) := (others => '0');	-- Address

	signal cpuInt_n			: std_logic_vector (2 downto 0) := (others => '1');	-- Interrupt level
	signal cpuVPAn			: std_logic;						-- Autovector flag

	signal LDSn			: std_logic;
	signal UDSn			: std_logic;
	signal cpuByteEnables		: std_logic_vector (1 downto 0);

	signal cpuRomQ			: std_logic_vector (15 downto 0);

	signal cpuRamWren		: std_logic;
	signal cpuRamQ			: std_logic_vector (15 downto 0);

	signal cpuUartCS		: std_logic;
	signal cpuUartWR		: std_logic;
	signal cpuUartQ			: std_logic_vector (7 downto 0);
	signal cpuUartInt		: std_logic;

	signal cpuKbCS			: std_logic;
	signal cpuKbQ			: std_logic_vector (7 downto 0);
	signal cpuKbInt			: std_logic;

	signal cpuLEDsWR		: std_logic;
	signal cpuLEDsQ			: std_logic_vector (7 downto 0);

	signal cpuControlWR		: std_logic;
	signal cpuControlQ		: std_logic_vector (7 downto 0);

	type resetFSM_type is (
		resetIdle_state,
		resetActive_state,
		resetComplete_state
	);

	signal resetFSM			: resetFSM_type := resetIdle_state;
	signal dotClear			: std_logic := '1';
	signal cpuClearD0		: std_logic := '1';
	signal cpuClearD1		: std_logic := '1';

	signal dotClock			: std_logic := '0';

	signal addressA			: std_logic_vector (10 downto 0);

	signal videoRamWren		: std_logic;
	signal videoRamQ		: std_logic_vector (15 downto 0);
	
	signal rowAddressD0		: std_logic_vector (10 downto 0);

	signal lineAddressD0		: std_logic_vector (9 downto 0);
	signal lineAddressD1		: std_logic_vector (9 downto 0);
	signal frameChar		: std_logic_vector (15 downto 0);

	signal columnAddressD0		: std_logic_vector (10 downto 0);
	signal columnAddressD1		: std_logic_vector (10 downto 0);
	signal columnAddressD2		: std_logic_vector (10 downto 0);
	signal columnAddressD3		: std_logic_vector (10 downto 0);
	signal scanChar			: std_logic_vector (15 downto 0);

	signal hSyncD0			: std_logic;
	signal hSyncD1			: std_logic;
	signal hSyncD2			: std_logic;
	signal hSyncD3			: std_logic;
	signal hSyncD4			: std_logic;

	signal vSyncD0			: std_logic;
	signal vSyncD1			: std_logic;
	signal vSyncD2			: std_logic;
	signal vSyncD3			: std_logic;
	signal vSyncD4			: std_logic;

	signal blankingD0		: std_logic;
	signal blankingD1		: std_logic;
	signal blankingD2		: std_logic;
	signal blankingD3		: std_logic;
	signal blankingD4		: std_logic;

	signal pixel			: std_logic;
	signal pixelBlanked		: std_logic;

	signal romAddr			: std_logic_vector (12 downto 0);

	signal slow_clock		: std_logic := '0';

	signal rts_n			: std_logic;
	signal cts_n			: std_logic;

	attribute keep: boolean;
	signal addrbus			: std_logic_vector(23 downto 0); -- for debug
	attribute keep of addrbus: signal is true;
begin

	addrbus <= eab & '0';

	-- LEDS <= "00000000";
	-- LEDS <= cpuControlQ;
	LEDS <= cpuLEDsQ;

	-- Create a 108.0 MHz dot clock from the 12 MHz oscillator.
	dotClockGen: dot_clock
		port map
		(
			inclk0 => CLK12M,
			c0 => dotClock		-- 108.0 MHz, 9.259... ns period
		);

	-- Create a 51.6 MHz cpu clock from the 12 MHz oscillator.
	-- This frequency is chosen to get good baud rate accuracy.
	cpuClockGen: cpu_clock
		port map
		(
			inclk0 => CLK12M,
			c0 => cpuClock		-- 51.6 MHz, 19.38... ns period
		);

	phaseProcess: process(cpuClock)
		variable clkDivisor : std_logic := '0';
	begin
		if(rising_edge(cpuClock)) then
			clkDivisor := not clkDivisor;
			enPhi1 <= clkDivisor;
			enPhi2 <= not clkDivisor;
		end if;
	end process;

	-- Reset all counters, registers, etc.
	resetProcess: process(dotClock)
		variable resetDuration : unsigned(8 downto 0) := (others => '0');
	begin
		if (rising_edge(dotClock)) then
			case resetFSM is

				when resetIdle_state =>
					resetFSM <= resetActive_state;
					dotClear <= '1';
					
				when resetActive_state =>
					resetDuration := resetDuration + 1;
					if (resetDuration = "11111111") then
						resetFSM <= resetComplete_state;
						dotClear <= '0';
					end if;

				when resetComplete_state =>
					null;

				when others =>
					null;
			end case;
		end if;
	end process;

	-- Cross clock domains.
	cpuResetProcess: process(cpuClock)
	begin
		if (rising_edge(cpuClock)) then
			cpuClearD0 <= dotClear;
			cpuClearD1 <= cpuClearD0;
		end if;
	end process;

	cpu: fx68k
		port map
		(
			clk => cpuClock,
			HALTn => '1',
			extReset => cpuClearD1,
			pwrUp => cpuClearD1,
			enPhi1 => enPhi1,
			enPhi2 => enPhi2,

			eRWn => eRWn,
			ASn => ASn,
			LDSn => LDSn,
			UDSn => UDSn,
			E => E,
			VMAn => VMAn,
	
			FC0 => FC0,
			FC1 => FC1,
			FC2 => FC2,
			BGn => BGn,
			oRESETn => oRESETn,
			oHALTEDn => oHALTEDn,

			DTACKn => DTACKn,
			VPAn => cpuVPAn,
			BERRn => BERRn,
			BRn => BRn,
			BGACKn => BGACKn,
			IPL0n => cpuInt_n(0),
			IPL1n => cpuInt_n(1),
			IPL2n => cpuInt_n(2),

			iEdb => iEdb,
			oEdb => oEdb,
			eab => eab
		);

	cpuByteEnables <= not (UDSn & LDSn);

	-- CPU ROM
	cpuRom: cpu_rom
		port map (
			address => eab(13 downto 1),
			clock => cpuClock,
			q => cpuRomQ
		);

	-- CPU RAM
	cpuRam: cpu_ram
		port map (
			address => eab(13 downto 1),
			byteena => cpuByteEnables,
			clock => cpuClock,
			data => oEdb,
			wren => cpuRamWren,
			q => cpuRamQ
		);

	-- CPU UART
	uart: gh_uart_16550
		port map(
			-- processor interface
			clk => cpuClock,
			BR_clk => cpuClock,
			rst => cpuClearD1,
			CS => cpuUartCS,
			WR => cpuUartWR,
			ADD => eab(3 downto 1),
			D => oEdb(7 downto 0),
			RD => cpuUartQ,
			IRQ => cpuUartInt,

			-- serial interface
			sRX => UART_RX,
			sTx => UART_TX,

			-- modem control signals
			CTSn => cts_n,		-- cts, active low
			RTSn => rts_n,		-- rts, active low
			DSRn => '0',		-- dsr, active low
			RIn => '0',		-- ring indicator, active low
			DCDn => '0'		-- dcd, active low
		);
	
	cts_n <= UART_CTS;
	UART_RTS <= rts_n;

	-- CPU Keyboard
	cpuKB: keyboard
		port map
		(
			-- CPU
			clk => cpuClock,
			reset => cpuClearD1,
			addrIn => eab(3 downto 1),
			dataOut => cpuKbQ,
			kbCS => cpuKbCS,
			irq => cpuKbInt,

			-- KB
			ps2_clk => KBD_CLK,
			ps2_data => KBD_DATA
		);

	-- CPU Control
	cpuControl: control
		port map
		(
			-- CPU
			clk => cpuClock,
			reset => cpuClearD1,
			D => oEdb(15 downto 8),
			WR => cpuControlWR,

			-- Control
			Q => cpuControlQ
		);

	-- CPU LEDs
	cpuLEDs: led_reg
		port map
		(
			-- CPU
			clk => cpuClock,
			reset => cpuClearD1,
			D => oEdb(15 downto 8),
			WR => cpuLEDsWR,

			-- Control
			Q => cpuLEDsQ
		);

	-- CPU Bus
	cpuBus: cpu_bus
		port map (
			-- CPU Interface
			cpuClock => cpuClock,
			cpuClear => cpuClearD1,
			cpuByteEnables => cpuByteEnables,
			cpuAddr => eab,
			cpuDataIn => iEdb,		-- CPU input data from cpuBus
			cpuRWn => eRWn,
			cpuInt_n => cpuInt_n,
			cpuVPAn => cpuVPAn,
			cpuDTACKn => DTACKn,
			cpuASn => ASn,

			-- CPU ROM Interface
			cpuRomQ => cpuRomQ,

			-- CPU RAM Interface
			cpuRamWren => cpuRamWren,
			cpuRamQ => cpuRamQ,

			-- VIDEO RAM Interface
			videoRamWren => videoRamWren,
			videoRamQ => videoRamQ,

			-- UART Interface
			cpuUartCS => cpuUartCS,
			cpuUartWR => cpuUartWR,
			cpuUartQ => cpuUartQ,
			cpuUartInt => cpuUartInt,
			
			-- Keyboard Interface
			cpuKbCS => cpuKbCS,
			cpuKbQ => cpuKbQ,
			cpuKbInt => cpuKbInt,

			-- LED Interface
			cpuLEDsWR => cpuLEDsWR,

			-- DIP Switch Interface
			cpuDipQ => DIP_SW,

			-- Control Register Interface
			cpuControlWR => cpuControlWR
		);

	-- Generate timing and addresses from the dot clock.  The row address
	-- covers the whole frame (0 to 1065).  The column address covers a whole
	-- scan line (0 to 1687).
	--
	-- Characters are 16 pels wide and 32 pels high, but each line of text is
	-- 42 pels high, because we want 24 lines of text to fill the 1024 visible
	-- scan lines.  In other words, there are 10 blank scan lines between each
	-- line of text.
	--
	-- The lineAddress signal just covers the active scan lines.  It does not
	-- increment during the 10 blank scan lines between each line of text.
       	-- That lets us do simple shifting to address the character ROM.
	frameGen: frame_gen
		port map (
			clear => dotClear,
			dotClock => dotClock,
			hSync => hSyncD0,
			vSync => vSyncD0,
			columnAddress => columnAddressD0,
			rowAddress => rowAddressD0,
			lineAddress => lineAddressD0,
			blanking => blankingD0
		);

	-- There are 80x24 = 1920 bytes of screen memory.
	--
	-- columnAddress runs from 0 to 1687, which shifts down 4 (divides by 16) to
	-- run from 0 to 105.  We map anything 80 and above to 0 so as not to go out
	-- of bounds on the ram address.
	--
	-- lineAddress runs from 0 to 767, which shifts down 5 (divides by 32) to
	-- run from 0 to 23.
	genFrameAddressA: process(all)
		variable colA	: unsigned (6 downto 0);
		variable lineA	: unsigned (4 downto 0);
		variable addr	: unsigned (11 downto 0);
		variable addrA	: unsigned (10 downto 0);
	begin
		colA := unsigned(columnAddressD0(10 downto 4));
		lineA := unsigned(lineAddressD0(9 downto 5));

		if(colA < 80) then
			-- lineA ranges from 0 to 23.  Multiplying by 80
			-- ranges from 0 to 1840.  colA ranges from 0 to 79,
			-- so the sum ranges from 0 to 1919, which only needs
			-- 11 bits.
			--
			-- But, Quartus thinks a 7-bit by 5-bit multiply has
			-- to have 12 bits, so we use "addr" as a 12-bit temp
			-- then toss the junk MSB...
			addr := (to_unsigned(80, 7) * lineA) + colA;
			addrA := addr(10 downto 0);
		else
			-- We are in the end-of-line blanking area, so map to 0.
			addrA := to_unsigned(0, addrA'length);
		end if;

		addressA <= std_logic_vector(addrA);
	end process;
	
	-- Screen memory.  The A port is used to drive the VGA port.  The
	-- B port is for CPU access.
	--
	-- Address and data are both registered on input, but not on output,
	-- so frameChar is one clock behind addressA (and hence 1 behind
	-- lineAddress).
	frameRam: frame_ram
		port map (
			address_a => addressA,
			address_b => eab(11 downto 1),
			byteena_b => cpuByteEnables,
			clock_a => dotClock,
			clock_b => cpuClock,
			data_a => (others => '0'), -- not used
			data_b => oEdb(15 downto 0),
			wren_a => '0', -- not used
			wren_b => videoRamWren,
			q_a => frameChar,
			q_b => videoRamQ
		);

	-- Line up lineAddress with frameChar.
	delayLineAddr: process(dotClock)
	begin
		if(rising_edge(dotClock)) then
			lineAddressD1 <= lineAddressD0;
		end if;
	end process;

	-- Our character set is based on 7-bit ASCII, so the MSB (bit 7)
	-- is not needed.  Instead, we are using bit 7 (of frameChar) to
	-- indicate where the cursor is positioned.
	--
	-- Essentially, bit 7 selects an alternate (reverse-video)
	-- character set for the cell containing the cursor.
	--
	-- Address and data output are both registered, so scanChar is
	-- two clocks behind romAddr, or three clocks behind addressA.
	romAddr <= frameChar(7 downto 0) & lineAddressD1(4 downto 0);
	charRom: char_rom
		port map (
			address => romAddr,
			clock => dotClock,
			q => scanChar
		);

	-- Line up columnAddress with scanChar.
	delayColumnAddress: process(dotCLock)
	begin
		if(rising_edge(dotClock)) then
			columnAddressD1 <= columnAddressD0;
			columnAddressD2 <= columnAddressD1;
			columnAddressD3 <= columnAddressD2;
		end if;
	end process;

	-- The lower four bits of the columnAddress select the bit of
	-- the character to be displayed.
	--
	-- The output is registered, so pixel is one clock behind
	-- scanChar, or 4 clocks behind addressA.
	pelSelect: pel_select
		port map (
			clock => dotClock,
			inWord => scanChar,
			sel => columnAddressD3(3 downto 0),
			outBit => pixel
		);

	-- Delay sync pulses and blanking to line up with the pixel.
	delaySync: process(dotCLock)
	begin
		if(rising_edge(dotClock)) then
			hSyncD1 <= hSyncD0;
			hSyncD2 <= hSyncD1;
			hSyncD3 <= hSyncD2;
			hSyncD4 <= hSyncD3;

			vSyncD1 <= vSyncD0;
			vSyncD2 <= vSyncD1;
			vSyncD3 <= vSyncD2;
			vSyncD4 <= vSyncD3;

			blankingD1 <= blankingD0;
			blankingD2 <= blankingD1;
			blankingD3 <= blankingD2;
			blankingD4 <= blankingD3;
		end if;
	end process;

	blankIt: process(all)
	begin
		if(not blankingD4) then
			pixelBlanked <= pixel;
		else
			pixelBlanked <= '0';
		end if;
	end process;

	-- We are displaying in white, so just turn on both bits of
	-- all three "guns".
	reclockVGA: process(dotCLock)
	begin
		if(rising_edge(dotClock)) then
			PIXEL_R1 <= pixelBlanked;
			PIXEL_R2 <= pixelBlanked;
			PIXEL_G1 <= pixelBlanked;
			PIXEL_G2 <= pixelBlanked;
			PIXEL_B1 <= pixelBlanked;
			PIXEL_B2 <= pixelBlanked;

			if(cpuControlQ(0) = '1') then
				HSYNC <= hSyncD4;
				VSYNC <= vSyncD4;
			else
				HSYNC <= '0';
				VSYNC <= '0';
			end if;
		end if;
	end process;

end a;

