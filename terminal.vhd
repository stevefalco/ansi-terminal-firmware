library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity terminal is
	port (
		CLK12M			: in std_logic;

		-- The FPGA can drive 8 mA per pin.  The RGB pins drive a 75 ohm
		-- load, and we need to get it to 0.7 volts for "white".
		--
		-- That requires around 9 mA, which is a bit more than the FPGA
		-- wants to provide.  We will parallel two outputs, each with a
		-- separate series resistor.  We could even get some greyscale
		-- output if desired, by wiring an R-2R ladder.  I've seen people
		-- use 3 or 4 independent bits per color, but we don't need that.
		PIXEL_R1		: out std_logic;
		PIXEL_R2		: out std_logic;
		PIXEL_G1		: out std_logic;
		PIXEL_G2		: out std_logic;
		PIXEL_B1		: out std_logic;
		PIXEL_B2		: out std_logic;

		HSYNC			: out std_logic;
		VSYNC			: out std_logic
	);
end terminal;

architecture a of terminal is
	component dot_clock
		port
		(
			inclk0		: in std_logic  := '0';
			c0		: out std_logic ;
			c1		: out std_logic
		);
	end component;

	component frame_gen
		port (
			clear		: in std_logic;
			dotClock	: in std_logic;
			hSync		: out std_logic;
			vSync		: out std_logic;
			columnAddress	: out std_logic_vector (9 downto 0);
			rowAddress	: out std_logic_vector (9 downto 0);
			lineAddress	: out std_logic_vector (8 downto 0);
			blanking	: out std_logic
		);
	end component;

	component char_rom
		port (
			address		: in std_logic_vector (10 downto 0);
			clock		: in std_logic;
			q		: out std_logic_vector (7 downto 0)
		);
	end component;

	component frame_ram
		port (
			address_a	: in std_logic_vector (10 downto 0);
			address_b	: in std_logic_vector (10 downto 0);
			clock_a		: in std_logic;
			clock_b		: in std_logic;
			data_a		: in std_logic_vector (7 downto 0);
			data_b		: in std_logic_vector (7 downto 0);
			wren_a		: in std_logic;
			wren_b		: in std_logic;
			q_a		: out std_logic_vector (7 downto 0);
			q_b		: out std_logic_vector (7 downto 0)
		);
	end component;

	component pel_select
		port (
			clock		: in std_logic;
			inByte		: in std_logic_vector (7 downto 0);
			sel		: in std_logic_vector (2 downto 0);
			outBit		: out std_logic
		);
	end component;

	component z80_top_direct_n
		port (
			nM1		: out std_logic;
			nMREQ		: out std_logic;
			nIORQ		: out std_logic;
			nRD		: out std_logic;
			nWR		: out std_logic;
			nRFSH		: out std_logic;
			nHALT		: out std_logic;
			nBUSACK		: out std_logic;

			nWAIT		: in std_logic;
			nINT		: in std_logic;
			nNMI		: in std_logic;
			nRESET		: in std_logic;
			nBUSRQ		: in std_logic;

			CLK		: in std_logic;
			A		: out std_logic_vector (15 downto 0);
			D		: inout std_logic_vector (7 downto 0)
		);
	end component;

	component z80Rom
		port (
			address		: in std_logic_vector (13 downto 0);
			clock		: in std_logic;
			q		: out std_logic_vector (7 downto 0)
		);
	end component;

	component z80Ram
		port (
			address		: in std_logic_vector (13 downto 0);
			clock		: in std_logic;
			data		: in std_logic_vector (7 downto 0);
			wren		: in std_logic;
			q		: out std_logic_vector (7 downto 0)
		);
	end component;

	component z80_bus
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

			-- UART Interface

			-- VIDEO RAM Interface
			videoRamWren	: out std_logic;
			videoRamQ	: in std_logic_vector (7 downto 0)
		);
	end component;

	-- Z80 Interface.
	signal nM1			: std_logic;
	signal nMREQ			: std_logic;
	signal nIORQ			: std_logic;
	signal nRD			: std_logic;
	signal nWR			: std_logic;
	signal nRFSH			: std_logic;
	signal nHALT			: std_logic;
	signal nBUSACK			: std_logic;

	signal cpuAddrBus		: std_logic_vector (15 downto 0);
	signal cpuDataBus		: std_logic_vector (7 downto 0);

	signal cpuBusClkOut		: std_logic;

	signal cpuRomQ			: std_logic_vector (7 downto 0);

	signal cpuRamWren		: std_logic;
	signal cpuRamQ			: std_logic_vector (7 downto 0);

	type resetFSM_type is (
		resetIdle_state,
		resetActive_state,
		resetComplete_state
	);

	signal resetFSM			: resetFSM_type := resetIdle_state;
	signal clear			: std_logic;
	signal clearNot			: std_logic;

	signal dotClock			: std_logic;
	signal cpuClock			: std_logic;

	signal addressA			: std_logic_vector (10 downto 0);

	signal videoRamWren		: std_logic;
	signal videoRamQ		: std_logic_vector (7 downto 0);
	
	signal rowAddressD0		: std_logic_vector (9 downto 0);

	signal lineAddressD0		: std_logic_vector (8 downto 0);
	signal lineAddressD1		: std_logic_vector (8 downto 0);
	signal lineAddressD2		: std_logic_vector (8 downto 0);
	signal frameChar		: std_logic_vector (7 downto 0);

	signal columnAddressD0		: std_logic_vector (9 downto 0);
	signal columnAddressD1		: std_logic_vector (9 downto 0);
	signal columnAddressD2		: std_logic_vector (9 downto 0);
	signal columnAddressD3		: std_logic_vector (9 downto 0);
	signal columnAddressD4		: std_logic_vector (9 downto 0);
	signal scanChar			: std_logic_vector (7 downto 0);

	signal hSyncD0			: std_logic;
	signal hSyncD1			: std_logic;
	signal hSyncD2			: std_logic;
	signal hSyncD3			: std_logic;
	signal hSyncD4			: std_logic;
	signal hSyncD5			: std_logic;

	signal vSyncD0			: std_logic;
	signal vSyncD1			: std_logic;
	signal vSyncD2			: std_logic;
	signal vSyncD3			: std_logic;
	signal vSyncD4			: std_logic;
	signal vSyncD5			: std_logic;

	signal blankingD0		: std_logic;
	signal blankingD1		: std_logic;
	signal blankingD2		: std_logic;
	signal blankingD3		: std_logic;
	signal blankingD4		: std_logic;
	signal blankingD5		: std_logic;

	signal pixel			: std_logic;
	signal pixelBlanked		: std_logic;

	signal romAddr			: std_logic_vector (10 downto 0);
begin

	-- Create a 25.2 MHz dot clock from the 12 MHz oscillator.
	dotClockGen: dot_clock
		port map
		(
			inclk0 => CLK12M,
			c0 => dotClock,
			c1 => cpuClock
		);

	-- Reset all counters, registers, etc.
	resetProcess: process(dotClock)
		variable resetDuration : unsigned(3 downto 0) := (others => '0');
	begin
		if (rising_edge(dotClock)) then
			case resetFSM is

				when resetIdle_state =>
					resetFSM <= resetActive_state;
					clear <= '1';
					clearNot <= '0';
					
				when resetActive_state =>
					resetDuration := resetDuration + 1;
					if (resetDuration = "1111") then
						resetFSM <= resetComplete_state;
						clear <= '0';
						clearNot <= '1';
					end if;

				when resetComplete_state =>
					null;

				when others =>
					null;
			end case;
		end if;
	end process;

	-- Z80 CPU
	z80CPU: z80_top_direct_n
		port map (
			nM1 => nM1,
			nMREQ => nMREQ,
			nIORQ => nIORQ,
			nRD => nRD,
			nWR => nWR,
			nRFSH => nRFSH,
			nHALT => nHALT,
			nBUSACK => nBUSACK,

			nWAIT => '1',
			nINT => '1',
			nNMI => '1',
			nRESET => clearNot,
			nBUSRQ => '1',

			CLK => cpuClock,
			A => cpuAddrBus,
			D => cpuDataBus
		);

	-- Z80 ROM
	z80_rom: z80Rom
		port map (
			address => cpuAddrBus(13 downto 0),
			clock => cpuClock,
			q => cpuRomQ
		);

	-- Z80 RAM
	z80_ram: z80Ram
		port map (
			address => cpuAddrBus(13 downto 0),
			clock => cpuClock,
			data => cpuDataBus,
			wren => cpuRamWren,
			q => cpuRamQ
		);

	-- Z80 Bus
	z80Bus: z80_bus
		port map (
			-- CPU Interface.
			cpuAddr => cpuAddrBus,
			cpuData => cpuDataBus,
			cpuRden => nRD,
			cpuWren => nWR,

			-- CPU ROM Interface
			cpuRomQ => cpuRomQ,

			-- CPU RAM Interface
			cpuRamWren => cpuRamWren,
			cpuRamQ => cpuRamQ,

			-- UART Interface

			-- VIDEO RAM Interface
			videoRamWren => videoRamWren,
			videoRamQ => videoRamQ
		);

	-- Generate timing and addresses from the dot clock.  The row address
	-- covers the whole frame (0 to 525).  The column address covers a whole
	-- scan line (0 to 799).
	--
	-- Characters are 8 pels wide and 16 pels high, but each line of text is
	-- 20 pels high, because we want 24 lines of text to fill the 480 visible
	-- scan lines.  In other words, there are 4 blank scan lines between each
	-- line of text.
	--
	-- The lineAddress signal just covers the active scan lines.  It does not
	-- increment during the 4 blank scan lines between each line of text.
       	-- That lets us do simple shifting to address the character ROM.
	frameGen: frame_gen
		port map (
			clear => clear,
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
	-- columnAddress runs from 0 to 799, which shifts down 3 (divides by 8) to
	-- run from 0 to 99.  We map anything 80 and above to 0 so as not to go out
	-- of bounds on the ram address.
	--
	-- lineAddress runs from 0 to 383, which shifts down 4 (divides by 16) to
	-- run from 0 to 23.
	genFrameAddressA: process(all)
		variable colA	: unsigned (6 downto 0);
		variable lineA	: unsigned (4 downto 0);
		variable addr	: unsigned (11 downto 0);
		variable addrA	: unsigned (10 downto 0);
	begin
		colA := unsigned(columnAddressD0(9 downto 3));
		lineA := unsigned(lineAddressD0(8 downto 4));

		if(colA < 80) then
			-- lineA ranges from 0 to 23.  Multiplying by 80
			-- ranges from 0 to 1840.  colA ranges from 0 to 79,
			-- so the sum ranges from 0 to 1919, which only needs
			-- 11 bits.
			--
			-- But, Quartus thinks addrA has to have 12 bits, so we
			-- humor it, then toss the junk MSB...
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
	-- Address and data are both registered, so frameChar is two clocks
	-- behind addressA (and hence 2 behind lineAddress).
	frameRam: frame_ram
		port map (
			address_a => addressA,
			address_b => cpuAddrBus(10 downto 0),
			clock_a => dotClock,
			clock_b => cpuClock,
			data_a => "00000000", -- not used
			data_b => cpuDataBus,
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
			lineAddressD2 <= lineAddressD1;
		end if;
	end process;

	-- We are using 7-bit ascii, hence we toss frameChar(7).
	--
	-- Address and data are both registered, so scanChar is two clocks
	-- behind romAddr, or four clocks behind addressA.
	romAddr <= frameChar(6 downto 0) & lineAddressD2(3 downto 0);
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
			columnAddressD4 <= columnAddressD3;
		end if;
	end process;

	-- The lower three bits of the columnAddress select the bit to be
	-- displayed.
	--
	-- The output is registered, so pixel is one clock behind
	-- scanChar, or 5 clocks behind addressA..
	pelSelect: pel_select
		port map (
			clock => dotClock,
			inByte => scanChar,
			sel => columnAddressD4(2 downto 0),
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
			hSyncD5 <= hSyncD4;

			vSyncD1 <= vSyncD0;
			vSyncD2 <= vSyncD1;
			vSyncD3 <= vSyncD2;
			vSyncD4 <= vSyncD3;
			vSyncD5 <= vSyncD4;

			blankingD1 <= blankingD0;
			blankingD2 <= blankingD1;
			blankingD3 <= blankingD2;
			blankingD4 <= blankingD3;
			blankingD5 <= blankingD4;
		end if;
	end process;

	blankIt: process(all)
	begin
		if(not blankingD5) then
			pixelBlanked <= pixel;
		else
			pixelBlanked <= '0';
		end if;
	end process;

	PIXEL_R1 <= pixelBlanked;
	PIXEL_R2 <= pixelBlanked;
	PIXEL_G1 <= pixelBlanked;
	PIXEL_G2 <= pixelBlanked;
	PIXEL_B1 <= pixelBlanked;
	PIXEL_B2 <= pixelBlanked;

	HSYNC <= hSyncD5;
	VSYNC <= vSyncD5;

end a;

