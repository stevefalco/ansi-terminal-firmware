library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity terminal is
	port (
		CLK12M			: in std_logic
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
			address_a	: in std_logic_vector (11 downto 0);
			address_b	: in std_logic_vector (11 downto 0);
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
	signal hSync			: std_logic;
	signal vSync			: std_logic;
	signal columnAddress		: std_logic_vector (9 downto 0);
	signal rowAddress		: std_logic_vector (9 downto 0);
	signal lineAddress		: std_logic_vector (8 downto 0);

	-- VGA
	signal addressA			: std_logic_vector (11 downto 0);
	signal addressAclipped		: std_logic_vector (11 downto 0);

	-- CPU
	signal addressB			: std_logic_vector (11 downto 0);
	signal dataB			: std_logic_vector (7 downto 0);
	signal wrenB			: std_logic;
	signal qB			: std_logic_vector (7 downto 0);
	
	signal frameChar		: std_logic_vector (7 downto 0);
	signal scanChar			: std_logic_vector (7 downto 0);

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
			hSync => hSync,
			vSync => vSync,
			columnAddress => columnAddress,
			rowAddress => rowAddress,
			lineAddress => lineAddress
		);

	-- Screen memory.  The A port is used to drive the VGA port.  The
	-- B port is for CPU access.
	--
	-- To keep the addressing simple, we make each line 128 characters
	-- long, and waste 48 bytes x 24 lines or 1152 bytes.  Thus, we can
	-- feed the column address right shifted by 3 directly into the low
	-- 6 bits of the frame_ram address.
	genFrameAddressA: process(all)
	begin
		addressA <= lineAddress(8 downto 4) & columnAddress(9 downto 3);
		if(unsigned(addressA) > 3072) then
			addressAclipped <= (others => '0');
		else
			addressAclipped <= addressA;
		end if;
	end process;
	
	frameRam: frame_ram
		port map (
			address_a => addressAclipped,
			address_b => addressB,
			clock => dotClock,
			data_a => "00000000", -- not used
			data_b => dataB,
			wren_a => '0', -- not used
			wren_b => wrenB,
			q_a => frameChar,
			q_b => qB
		);

	-- We are using 7-bit ascii, hence we toss frameChar(7).
	romAddr <= frameChar(6 downto 0) & lineAddress(3 downto 0);
	charRom: char_rom
		port map (
			address => romAddr,
			clock => dotClock,
			q => scanChar
		);

	-- The lower three bits of the columnAddress select the bit to be
	-- displayed.
	pelSelect: pel_select
		port map (
			clock => dotClock,
			inByte => scanChar,
			sel => columnAddress(2 downto 0),
			outBit => pixel
		);
end a;

