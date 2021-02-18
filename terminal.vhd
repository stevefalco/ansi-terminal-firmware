library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity terminal is
	port (
		CLK12M			: in std_logic;

		-- The FPGA can drive 8 mA per pin.  We have a 75 ohm
		-- load, and we need to get it to 0.7 volts for "white".
		--
		-- That requires around 9 mA, so we will parallel two
		-- outputs, each with a separate series resistor.  We
		-- could even get some greyscale output if desired, by
		-- wiring an R-2R ladder.
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
			c0		: out std_logic 
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
			lineAddress	: out std_logic_vector (8 downto 0)
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
			clock		: in std_logic;
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

	type resetFSM_type is (
		resetIdle_state,
		resetActive_state,
		resetComplete_state
	);

	signal resetFSM			: resetFSM_type := resetIdle_state;
	signal clear			: std_logic;

	signal dotClock			: std_logic;
	signal columnAddress		: std_logic_vector (9 downto 0);
	signal rowAddress		: std_logic_vector (9 downto 0);
	signal lineAddress		: std_logic_vector (8 downto 0);

	-- VGA
	signal addressA			: std_logic_vector (10 downto 0);

	-- CPU
	signal addressB			: std_logic_vector (10 downto 0);
	signal dataB			: std_logic_vector (7 downto 0);
	signal wrenB			: std_logic;
	signal qB			: std_logic_vector (7 downto 0);
	
	signal lineAddressD1		: std_logic_vector (8 downto 0);
	signal lineAddressD2		: std_logic_vector (8 downto 0);
	signal frameChar		: std_logic_vector (7 downto 0);

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
	signal pixel			: std_logic;

	signal romAddr			: std_logic_vector (10 downto 0);

begin

	dotClockGen: dot_clock
		port map
		(
			inclk0 => CLK12M,
			c0 => dotClock
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
					
				when resetActive_state =>
					resetDuration := resetDuration + 1;
					if (resetDuration = "1111") then
						resetFSM <= resetComplete_state;
						clear <= '0';
					end if;

				when resetComplete_state =>
					null;

				when others =>
					null;
			end case;
		end if;
	end process;

	-- Generate timing and addresses from pixel clock.
	frameGen: frame_gen
		port map (
			clear => clear,
			dotClock => dotClock,
			hSync => hSyncD0,
			vSync => vSyncD0,
			columnAddress => columnAddress,
			rowAddress => rowAddress,
			lineAddress => lineAddress
		);

	-- There are 80x24 = 1920 bytes of screen memory.
	--
	-- Columns run from 0 to 799, which shifts down 3
	-- (divides by 8) to run from 0 to 99.  We map
	-- anything 80 and above to 0.
	--
	-- Lines run from 0 to 479, which shifts down 4
	-- (divides by 16) to run from 0 to 29.  We map
	-- anything 24 and above to 0.
	genFrameAddressA: process(all)
		variable colA	: unsigned (6 downto 0);
		variable lineA	: unsigned (4 downto 0);
		variable addrA	: unsigned (10 downto 0);
	begin
		colA := unsigned(columnAddress(9 downto 3));
		lineA := unsigned(lineAddress(8 downto 4));

		if(colA < 80) then
			addrA := "0000" & colA;
		else
			addrA := to_unsigned(0, addrA'length);
		end if;

		if(lineA < 24) then
			addrA := 80 * lineA + addrA;
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
			address_b => addressB,
			clock => dotClock,
			data_a => "00000000", -- not used
			data_b => dataB,
			wren_a => '0', -- not used
			wren_b => wrenB,
			q_a => frameChar,
			q_b => qB
		);

	-- Line up lineAddress with frameChar.
	delayLineAddr: process(dotClock)
	begin
		if(rising_edge(dotClock)) then
			lineAddressD1 <= lineAddress;
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
			columnAddressD1 <= columnAddress;
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

	-- Delay sync pulses to line up with the pixel.
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
		end if;
	end process;

	PIXEL_R1 <= pixel;
	PIXEL_R2 <= pixel;
	PIXEL_G1 <= pixel;
	PIXEL_G2 <= pixel;
	PIXEL_B1 <= pixel;
	PIXEL_B2 <= pixel;

	HSYNC <= hSyncD4;
	VSYNC <= vSyncD4;

end a;

