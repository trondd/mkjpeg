--------------------------------------------------------------------------------
--                                                                            --
--                          V H D L    F I L E                                --
--                          COPYRIGHT (C) 2006                                --
--                                                                            --
--------------------------------------------------------------------------------
--                                                                            --
-- Title       : DIVIDER                                                      --
-- Design      : DCT QUANTIZER                                                --
-- Author      : Michal Krepa                                                 --
--                                                                            --
--------------------------------------------------------------------------------
--                                                                            --
-- File        : QUANTIZER.VHD                                                --
-- Created     : Sun Aug 27 2006                                              --
--                                                                            --
--------------------------------------------------------------------------------
--                                                                            --
--  Description : Pipelined DCT Quantizer                                     --
--  Pipeline delay: 2*SIZE_C+INTERN_PIPE_C                                    --
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.All;
  use IEEE.NUMERIC_STD.all;
  
entity quantizer is
  generic 
    ( 
      SIZE_C        : INTEGER := 12;
      RAMQADDR_W    : INTEGER := 6;
      RAMQDATA_W    : INTEGER := 8
    );
  port
    (
      rst        : in  STD_LOGIC;
      clk        : in  STD_LOGIC;
      di         : in  STD_LOGIC_VECTOR(SIZE_C-1 downto 0);
      divalid    : in  STD_LOGIC;
      qdata      : in  std_logic_vector(7 downto 0);
      qwaddr     : in  std_logic_vector(5 downto 0);
      qwren      : in  std_logic;
                 
      do         : out STD_LOGIC_VECTOR(SIZE_C-1 downto 0);
      dovalid    : out STD_LOGIC
    );
end quantizer;

architecture rtl of quantizer is
  
  constant INTERN_PIPE_C : INTEGER := 3;
  
  signal romaddr_s     : UNSIGNED(RAMQADDR_W-1 downto 0);
  signal slv_romaddr_s : STD_LOGIC_VECTOR(RAMQADDR_W-1 downto 0);
  signal romdatao_s    : STD_LOGIC_VECTOR(RAMQDATA_W-1 downto 0);
  signal divisor_s     : STD_LOGIC_VECTOR(SIZE_C-1 downto 0);
  signal remainder_s   : STD_LOGIC_VECTOR(SIZE_C-1 downto 0);
  signal do_s          : STD_LOGIC_VECTOR(SIZE_C-1 downto 0);
  signal round_s       : STD_LOGIC;
  signal di_d1         : std_logic_vector(SIZE_C-1 downto 0);
  
  signal pipeline_reg  : STD_LOGIC_VECTOR(4 downto 0);
  signal sign_bit_pipe : std_logic_vector(SIZE_C+INTERN_PIPE_C+1-1 downto 0);  
  signal do_rdiv       : STD_LOGIC_VECTOR(SIZE_C-1 downto 0);
begin
  
  ----------------------------
  -- RAMQ
  ----------------------------
  U_RAMQ : entity work.RAMZ
    generic map
    (
      RAMADDR_W    => RAMQADDR_W,
      RAMDATA_W    => RAMQDATA_W
    )
    port map
    (
      d           => qdata,
      waddr       => qwaddr,
      raddr       => slv_romaddr_s,
      we          => qwren,
      clk         => CLK,
                  
      q           => romdatao_s
    );
  
  ----------------------------
  -- S_DIVIDER
  ----------------------------
  --U_S_DIVIDER : entity work.s_divider
  --  generic map
  --  ( 
  --     SIZE_C => SIZE_C 
  --  )            
  --  port map
  --  (
  --     rst         => rst,
  --     clk         => clk,
  --     a           => di_d1,
  --     d           => divisor_s,
  --     
  --     q           => do_s,    
  --     r           => remainder_s, -- if ever used, needs to be 1T delayed
  --     round       => round_s
  --  ); 
  
  divisor_s(RAMQDATA_W-1 downto 0)      <= romdatao_s;
  divisor_s(SIZE_C-1 downto RAMQDATA_W) <= (others => '0');
  
  r_divider : entity work.r_divider
  port map
  (
       rst   => rst,
       clk   => clk,
       a     => di_d1,     
       d     => romdatao_s,    
             
       q     => do_s
  ) ;
  do <= do_s;
  slv_romaddr_s <= STD_LOGIC_VECTOR(romaddr_s);
  
  ------------------------------
  ---- round to nearest integer
  ------------------------------
  --process(clk)
  --begin
  --  if clk = '1' and clk'event then
  --    if rst = '1' then
  --      do <= (others => '0');
  --    else
  --      -- round to nearest integer?
  --      if round_s = '1' then
  --        -- negative number, subtract 1
  --        if sign_bit_pipe(sign_bit_pipe'length-1) = '1' then
  --          do <= STD_LOGIC_VECTOR(SIGNED(do_s)-TO_SIGNED(1,SIZE_C));
  --        -- positive number, add 1
  --        else
  --          do <= STD_LOGIC_VECTOR(SIGNED(do_s)+TO_SIGNED(1,SIZE_C));
  --        end if;
  --      else
  --        do <= do_s;
  --      end if;
  --    end if; 
  --  end if;
  --end process;
  
  ----------------------------
  -- address incrementer
  ----------------------------
  process(clk)
  begin
    if clk = '1' and clk'event then
      if rst = '1' then
        romaddr_s     <= (others => '0'); 
        pipeline_reg  <= (OTHERS => '0'); 
        di_d1         <= (OTHERS => '0');
        sign_bit_pipe <= (others => '0');
      else
        if divalid = '1' then
          romaddr_s <= romaddr_s + TO_UNSIGNED(1,RAMQADDR_W);
        end if;
        
        pipeline_reg <= pipeline_reg(pipeline_reg'length-2 downto 0) & divalid;
        
        di_d1 <= di;
        
        sign_bit_pipe <= sign_bit_pipe(sign_bit_pipe'length-2 downto 0) & di(SIZE_C-1);
      end if; 
    end if;
  end process;
  
  dovalid <= pipeline_reg(pipeline_reg'high);
   
end rtl;  
--------------------------------------------------------------------------------