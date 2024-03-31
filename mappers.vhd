library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL; 

entity mappers is
	port (
		clk_sys:	in STD_LOGIC;

		RESET_n:	in STD_LOGIC;
		mapper_lock:in STD_LOGIC;

		rom_a:		out STD_LOGIC_VECTOR(21 downto 0);

		ioctl_addr:	in STD_LOGIC_VECTOR(21 downto 0);
		ioctl_dout:	in STD_LOGIC_VECTOR(7 downto 0);
		ioctl_wr:	in STD_LOGIC;

		cart_address:   in STD_LOGIC_VECTOR(15 downto 0);
		cart_cs:        in STD_LOGIC;
		cart_oe:        in STD_LOGIC;
		cart_wr:        in STD_LOGIC;
		cart_data_wr:   in STD_LOGIC_VECTOR(7 downto 0);

		-- Backup RAM
		nvram_a:    out STD_LOGIC_VECTOR(14 downto 0);
		nvram_cs:   out STD_LOGIC
	);

end mappers;

architecture Behavioral of mappers is
	
	signal A:				std_logic_vector(15 downto 0);
	signal D_in:				std_logic_vector(7 downto 0);
	signal last_read_addr:  std_logic_vector(15 downto 0);
	signal RESET_n_d : std_logic;
	signal bank0:				std_logic_vector(7 downto 0) := "00000000";
	signal bank1:				std_logic_vector(7 downto 0) := "00000001";
	signal bank2:				std_logic_vector(7 downto 0) := "00000010";
	signal bank3:				std_logic_vector(7 downto 0) := "00000011";

	signal nvram_e:         std_logic := '0';
	signal nvram_ex:        std_logic := '0';
	signal nvram_p:         std_logic := '0';
	signal nvram_cme:       std_logic := '0'; -- codemasters ram extension

	signal lock_mapper_B:	std_logic := '0';
	signal mapper_codies:	std_logic := '0'; -- Ernie Els Golf mapper
	signal mapper_codies_lock:	std_logic := '0'; 
	
	signal mapper_msx_check0 : boolean := false ;
	signal mapper_msx_check1 : boolean := false ;
	signal mapper_msx_lock0 :  boolean := false ;
	signal mapper_msx_lock :   boolean := false ;
	signal mapper_msx :		   std_logic := '0' ;

begin

	A <= cart_address;
	D_in <= cart_data_wr;

	nvram_a <= (nvram_p and not A(14)) & A(13 downto 0);
	nvram_cs <= '1' when cart_cs='1' and ((A(15 downto 14)="10" and nvram_e = '1')
		or (A(15 downto 14)="11" and nvram_ex = '1')
		or (A(15 downto 13)="101" and nvram_cme = '1')) else '0';

	-- detect MSX mapper : we check the two first bytes of the rom, must be 41:42
	process (clk_sys)
	begin
		if rising_edge(clk_sys) then
		    RESET_n_d <= RESET_n;
			if RESET_n_d = '1' and RESET_n = '0' then
				mapper_msx_check0 <= false ;
				mapper_msx_check1 <= false ;
				mapper_msx_lock0 <= false ;
				mapper_msx_lock <= false ;
				mapper_msx <= '0' ;
			else
				if not mapper_msx_lock then 
					if ioctl_wr='1' then
						if unsigned(ioctl_addr)=0 then
							mapper_msx_check0 <= (ioctl_dout=x"41") ;
						elsif unsigned(ioctl_addr)=1 then
							mapper_msx_check1 <= (ioctl_dout=x"42") ;
							mapper_msx_lock0 <= true ;
						end if;
					else
						if mapper_msx_check0 and mapper_msx_check1 then
							mapper_msx <= '1'; -- if 4142 lock msx mapper on
						end if;
					end if;
					-- be paranoid : give only 1 chance to the mapper to lock on
					mapper_msx_lock <= mapper_msx_lock0 ; 
				end if;
			end if;
		end if;
	end process;
	
	-- external ram control
	process (RESET_n,clk_sys)
	begin
		if RESET_n='0' then
			bank0 <= "00000000";
			bank1 <= "00000001";
			bank2 <= "00000010";
			bank3 <= "00000011";
			nvram_e  <= '0';
			nvram_ex <= '0';
			nvram_p  <= '0';
			nvram_cme <= '0';
			lock_mapper_B <= '0' ;
			mapper_codies <= '0' ;
			mapper_codies_lock <= '0' ;
		else
			if rising_edge(clk_sys) then
				if cart_cs='1' and cart_oe='1' then
					last_read_addr <= A; -- gyurco anti-ldir patch
				end if;
				if mapper_msx = '1' then
					if cart_cs='1' and cart_wr='1' and A(15 downto 2)="00000000000000" then
						case A(1 downto 0) is
							when "00" => bank2 <= D_in;
							when "01" => bank3 <= D_in;
							when "10" => bank0 <= D_in;
							when "11" => bank1 <= D_in ; 
						end case;
					end if ;
				else
					if cart_cs='1' and cart_wr='1' and A(15 downto 2)="11111111111111" then
						mapper_codies <= '0' ;
						case A(1 downto 0) is
							when "00" => 
								nvram_ex <= D_in(4);
								nvram_e  <= D_in(3);
								nvram_p  <= D_in(2);
							when "01" => bank0 <= D_in;
							when "10" => bank1 <= D_in;
							when "11" => bank2 <= D_in ; 
						end case;
					end if;
					if cart_cs='1' and cart_wr='1' and nvram_e='0' and mapper_lock='0' then
						case A(15 downto 0) is
				-- Codemasters
				-- do not accept writing in adr $0000 (canary) unless we are sure that Codemasters mapper is in use
							when x"0000" => 
								if (lock_mapper_B='1') then 
									bank0 <= D_in ;
								-- we need a strong criteria to set mapper_codies, hopefully only Ernie Els Golf
								-- will have written a zero in $4000 before coming here
									if D_in /= "00000000" and mapper_codies_lock = '0' then
										if bank1 = "00000001" then
											mapper_codies <= '1' ;
										end if;
										mapper_codies_lock <= '1' ;
									end if;
								end if;
							when x"4000" => 
								if last_read_addr /= x"4000" then -- gyurco anti-ldir patch
									bank1(6 downto 0) <= D_in(6 downto 0) ;
									bank1(7) <= '0' ;
								-- mapper_codies <= mapper_codies or D_in(7) ;
									nvram_cme <= D_in(7) ;
									lock_mapper_B <= '1' ;
								end if ;
							when x"8000" => 
								if last_read_addr /= x"8000" then -- gyurco anti-ldir patch
									bank2 <= D_in ; 
									lock_mapper_B <= '1' ;
								end if;
					-- Korean mapper (Sangokushi 3, Dodgeball King)
							when x"A000" => 
								if last_read_addr /= x"A000" then -- gyurco anti-ldir patch
									if mapper_codies='0' then
										bank2 <= D_in ;
									end if ;
								end if ;
							when others => null ;
						end case ;
					end if;
				end if;
			end if;
		end if;
	end process;

	rom_a(12 downto 0) <= A(12 downto 0);
	process (A,bank0,bank1,bank2,bank3,mapper_msx,mapper_codies)
	begin
		if mapper_msx = '1' then
			case A(15 downto 13) is
			when "010" =>	
				rom_a(21 downto 13) <= '0' & bank0;
			when "011" =>
				rom_a(21 downto 13) <= '0' & bank1;
			when "100" =>
				rom_a(21 downto 13) <= '0' & bank2;
			when "101" =>
				rom_a(21 downto 13) <= '0' & bank3;
			when others =>
				rom_a(21 downto 13) <= "000000" & A(15 downto 13);
			end case;
		else
			rom_a(13) <= A(13);
			case A(15 downto 14) is
			when "00" =>
				-- first kilobyte is always from bank 0
				if A(13 downto 10)="0000" and mapper_codies='0' then
					rom_a(21 downto 14) <= (others=>'0');
				else
					rom_a(21 downto 14) <= bank0;
				end if;

			when "01" =>
				rom_a(21 downto 14) <= bank1;
			
			when others =>
				rom_a(21 downto 14) <= bank2;

			end case;
		end if;
	end process;

end Behavioral;
