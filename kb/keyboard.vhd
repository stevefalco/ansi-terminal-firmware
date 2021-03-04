library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity keyboard is
	port (
			-- CPU interface
			clk				: in std_logic;
			reset				: in std_logic;
			addrIn				: in std_logic_vector(2 downto 0);
			dataOut				: out std_logic_vector(7 downto 0);
			kbCS				: in std_logic;
			irq				: out std_logic;

			-- Keyboard interface
			ps2_clk				: inout std_logic;
			ps2_data			: inout std_logic
	);
end keyboard;

architecture a of keyboard is

	component ps2_keyboard_interface is
		port (
			clk				: in std_logic;
			reset				: in std_logic;
			ps2_clk				: inout std_logic;
			ps2_data			: inout std_logic;
			rx_extended			: out std_logic;
			rx_released			: out std_logic;
			rx_shift_key_on			: out std_logic;
			rx_scan_code			: out std_logic_vector(7 downto 0);
			rx_ascii			: out std_logic_vector(7 downto 0);
			rx_data_ready			: out std_logic;
			rx_read				: in std_logic;
			tx_data				: in std_logic_vector(7 downto 0);
			tx_write			: in std_logic;
			tx_write_ack_o			: out std_logic;
			tx_error_no_keyboard_ack	: out std_logic
		    );
	end component;

	signal rx_extended			: std_logic;
	signal rx_released			: std_logic;
	signal rx_shift_key_on			: std_logic;
	signal rx_scan_code			: std_logic_vector(7 downto 0);
	signal rx_ascii				: std_logic_vector(7 downto 0);
	signal rx_data_ready			: std_logic;
	signal rx_read				: std_logic;

	signal rx_scan_code_reg			: std_logic_vector(7 downto 0);
	signal rx_ascii_reg			: std_logic_vector(7 downto 0);
	signal rx_status_reg			: std_logic_vector(7 downto 0);

begin
	kb: ps2_keyboard_interface
	port map
	(
		-- CPU
		clk => clk,
		reset => reset,

		-- KB
		ps2_clk => ps2_clk,
		ps2_data => ps2_data,

		-- RX
		rx_extended => rx_extended,
		rx_released => rx_released,
		rx_shift_key_on => rx_shift_key_on,
		rx_scan_code => rx_scan_code,
		rx_ascii => rx_ascii,
		rx_data_ready => rx_data_ready,
		rx_read => rx_read,

		-- TX
		tx_write => '0',
		tx_data => (others => '0')
	);

	rx: process(clk)
	begin
		if (rising_edge(clk)) then
			if (reset = '1') then
				rx_scan_code_reg <= (others => '0');
				rx_ascii_reg <= (others => '0');
				rx_status_reg <= (others => '0');
				rx_read <= '0';
				irq <= '0';
			else
				if (rx_data_ready = '1') then
					-- If data is available, capture it and set an interrupt to the CPU.
					rx_scan_code_reg <= rx_scan_code;
					rx_ascii_reg <= rx_ascii;
					rx_status_reg <= "00001" & rx_extended & rx_released & rx_shift_key_on;
					irq <= '1';
				else
					-- Once the CPU does a read, the rx_data_ready signal will clear,
					-- and we can clear the interrupt.
					rx_status_reg <= "00000" & rx_extended & rx_released & rx_shift_key_on;
					irq <= '0';
				end if;

				if (kbCS = '1' and addrIn = "000") then
					-- On the first read, send an ACK to the keyboard SM to retire the
					-- interrupt.  The CPU will read all the registers before returning
					-- from the interrupt.
					rx_read <= '1';
				else
					rx_read <= '0';
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
				dataOut <= rx_ascii_reg;

			when "010" =>
				dataOut <= rx_status_reg;

			when others =>
				dataOut <= (others => '0');
		end case;
	end process;
end a;
