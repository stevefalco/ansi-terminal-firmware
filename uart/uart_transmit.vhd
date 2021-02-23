library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

entity uart_transmit is
	generic (
		CLK_FREQ	: integer := 16e6
	);
	port (
		clock		: in std_logic;
		reset		: in std_logic;

		address		: in std_logic_vector(2 downto 0);
		data		: inout std_logic_vector(7 downto 0);
		rden		: in std_logic;
		wren		: in std_logic;

		uartTx		: out std_logic
	);
end uart_transmit;

architecture a of uart_transmit is

	type txFSM_type is (
		idle,
		sendData,
		sendTrailer,
		cleaningUp,
		done
	);
	signal txState			: txFSM_type := idle;

	-- statusRegister(0): 1 = busy, 0 = idle.
	signal statusRegister		: std_logic_vector(7 downto 0);

	signal txDataRegister		: std_logic_vector(7 downto 0);

	signal baudRegister		: std_logic_vector(15 downto 0) := "0000010011100010";

	-- For a 12 MHz clock, here are the divisors:
	--    300 baud, divide by 40000, exact
	--    600 baud, divide by 20000, exact
	--   1200 baud, divide by 10000, exact
	--   2400 baud, divide by  5000, exact
	--   4800 baud, divide by  2500, exact
	--   9600 baud, divide by  1250, exact
	--  19200 baud, divide by   625, exact
	--  38400 baud, divide by   312, error 0.16%
	--  57600 baud, divide by   208, error 0.16%
	-- 115200 baud, divide by   104, error 0.16%
	signal bitCounter		: unsigned(15 downto 0);

	signal nextBit			: std_logic;
	signal nextBitCounter		: natural range 0 to 8;

begin

	uartRegisters: process(clock)
	begin
		if(rising_edge(clock)) then
			data <= (others => 'Z');
			if(txState = done) then
				statusRegister(0) <= '0';
			end if;

			if(reset = '1') then
				statusRegister <= (others => '0');

			elsif(wren = '1') then
				case address is

					when "000" =>
						if(statusRegister(0) = '0') then
							txDataRegister <= data;
							statusRegister(0) <= '1';
						end if;

					when "010" =>
						baudRegister(15 downto 8) <= data;

					when "011" =>
						baudRegister(7 downto 0) <= data;

					when others =>
						null;

				end case;

			elsif(rden = '1') then
				case address is

					when "001" =>
						data <= statusRegister;

					when others =>
						null;
				end case;

			end if;
		end if;
	end process;

	uartXmit: process(clock)

		variable workingBaudRegister	: std_logic_vector(15 downto 0);

	begin
		if(rising_edge(clock)) then
			if(reset = '1' or statusRegister(0) = '0') then
				nextBit <= '0';
				nextBitCounter <= 0;
				txState <= idle;
				uartTx <= '1';

				workingBaudRegister := baudRegister;
				bitCounter <= (others => '0');

			elsif(statusRegister(0) = '1') then
				if(bitCounter = unsigned(workingBaudRegister)) then
					bitCounter <= (others => '0');
				else
					bitCounter <= bitCounter + 1;
				end if;

				if(bitCounter = 0) then

					case txState is

						when idle =>
							-- Drive the start bit
							uartTx <= '0';

							-- Get the first bit of user data, and move
							-- to the next.
							nextBit <= txDataRegister(nextBitCounter);
							nextBitCounter <= nextBitCounter + 1;

							-- Get ready to send it
							txState <= sendData;

						when sendData =>
							-- Drive the next user data bit
							uartTx <= nextBit;

							if(nextBitCounter = 8) then
								-- We are done sending bits of user data
								txState <= sendTrailer;
								nextBitCounter <= 0;
							else
								-- Get the next bit
								nextBit <= txDataRegister(nextBitCounter);

								-- One less to do
								nextBitCounter <= nextBitCounter + 1;
							end if;

						when sendTrailer =>
							-- Drive the stop bit
							uartTx <= '1';
							txState <= cleaningUp;

						when cleaningUp =>
							-- We stay here for one tick for the stop bit
							-- to go out.
							txState <= done;

						when done =>
							-- We stay here until the "uartRegisters" process
							-- notices and clears the busy bit.
							txState <= idle;

						when others =>
							null;

					end case;
				end if;
			end if;
		end if;
	end process;
end a;
