-------------------------------------------------------------------------------
-- File Name : BUF_FIFO.vhd
--
-- Project   : JPEG_ENC
--
-- Module    : BUF_FIFO
--
-- Content   : Input FIFO Buffer
--
-- Description : 
--
-- Spec.     : 
--
-- Author    : Michal Krepa
--
-------------------------------------------------------------------------------
-- History :
-- 20090311: (MK): Initial Creation.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
----------------------------------- LIBRARY/PACKAGE ---------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- generic packages/libraries:
-------------------------------------------------------------------------------
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

-------------------------------------------------------------------------------
-- user packages/libraries:
-------------------------------------------------------------------------------
library work;
  use work.JPEG_PKG.all;
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
----------------------------------- ENTITY ------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
entity BUF_FIFO is
  port 
  (
        CLK                : in  std_logic;
        RST                : in  std_logic;
        -- HOST PROG
        img_size_x         : in  std_logic_vector(15 downto 0);
        img_size_y         : in  std_logic_vector(15 downto 0);
        sof                : in  std_logic;
        
        -- HOST DATA
        iram_wren          : in  std_logic;
        iram_wdata         : in  std_logic_vector(23 downto 0);
        fifo_almost_full   : out std_logic;
        
        -- FDCT
        fdct_block_cnt     : in  std_logic_vector(12 downto 0);
        fdct_fifo_rd       : in  std_logic;
        fdct_fifo_empty    : out std_logic;
        fdct_fifo_q        : out std_logic_vector(23 downto 0);
        fdct_fifo_hf_full  : out std_logic
    );
end entity BUF_FIFO;

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
----------------------------------- ARCHITECTURE ------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
architecture RTL of BUF_FIFO is

  constant C_NUM_SUBF      : integer := C_MAX_LINE_WIDTH/8;
  constant C_PIXEL_BITS    : integer := 24;
  constant C_SUBF_ADDRW    : integer := 7-C_MEMORY_OPTIMIZED;
  --constant C_LOG2_NUM_SUBF : integer := integer(log2(real(C_NUM_SUBF))); 
  
  type T_DATA_ARR is array (0 to C_NUM_SUBF-1) of std_logic_vector(23 downto 0);
  type T_CNT_ARR  is array (0 to C_NUM_SUBF-1) of 
    std_logic_vector(C_SUBF_ADDRW downto 0);
    
  type T_FIFO_RAMADDR     is array (0 to C_NUM_SUBF-1) of 
                            STD_LOGIC_VECTOR(C_SUBF_ADDRW-1 downto 0);

  signal fifo_rd          : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_wr          : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_data        : std_logic_vector(23 downto 0);
  signal fifo_data_d1     : std_logic_vector(23 downto 0);
  signal fifo_full        : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_empty       : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_half_full   : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_count       : T_CNT_ARR;
  
  signal pixel_cnt        : unsigned(15 downto 0);
  signal wblock_cnt       : unsigned(12 downto 0);
  signal last_idx         : unsigned(12 downto 0);
  signal idx_reg          : unsigned(log2(C_NUM_SUBF)-1 downto 0);
  signal wr_idx_reg       : unsigned(log2(C_NUM_SUBF)-1 downto 0);
  
  signal ramq             : STD_LOGIC_VECTOR(C_PIXEL_BITS-1 downto 0);
  signal ramd             : STD_LOGIC_VECTOR (C_PIXEL_BITS-1 downto 0);
  signal ramwaddr         : STD_LOGIC_VECTOR
                            (log2(C_NUM_SUBF)+C_SUBF_ADDRW-1 downto 0);
  signal ramwaddr_offset  : unsigned(C_SUBF_ADDRW-1 downto 0);
  signal ramwaddr_base    : unsigned(log2(C_NUM_SUBF)+C_SUBF_ADDRW downto 0);
  signal ramenw           : STD_LOGIC;
  signal ramenw_m1        : STD_LOGIC;
  signal ramenw_m2        : STD_LOGIC;
  signal ramraddr         : STD_LOGIC_VECTOR
                            (log2(C_NUM_SUBF)+C_SUBF_ADDRW-1 downto 0);
  signal ramraddr_base    : unsigned(log2(C_NUM_SUBF)+C_SUBF_ADDRW downto 0);
  signal ramraddr_offset  : unsigned(C_SUBF_ADDRW-1 downto 0);
  signal ramenr           : STD_LOGIC;
  
  signal fifo_ramwaddr    : T_FIFO_RAMADDR;
  signal fifo_ramenw      : STD_LOGIC_VECTOR(C_NUM_SUBF-1 downto 0);
  signal fifo_ramraddr    : T_FIFO_RAMADDR;
  signal fifo_ramenr      : STD_LOGIC_VECTOR(C_NUM_SUBF-1 downto 0);
  
  signal offset_ramwaddr  : STD_LOGIC_VECTOR(C_SUBF_ADDRW-1 downto 0);
-------------------------------------------------------------------------------
-- Architecture: begin
-------------------------------------------------------------------------------
begin

  -------------------------------------------------------------------
  -- SUB_FIFOs
  -------------------------------------------------------------------
  G_SUB_FIFO : for i in 0 to C_NUM_SUBF-1 generate
    
    U_SUB_FIFO : entity work.SUB_FIFO   
    generic map
    (
          DATA_WIDTH        => C_PIXEL_BITS,
          ADDR_WIDTH        => C_SUBF_ADDRW
    )
    port map 
    (        
          rst               => RST,
          clk               => CLK,
          rinc              => fifo_rd(i),
          winc              => fifo_wr(i),
  
          fullo             => fifo_full(i),
          emptyo            => fifo_empty(i),
          count             => fifo_count(i),
          
          ramwaddr          => fifo_ramwaddr(i),
          ramenw            => fifo_ramenw(i),
          ramraddr          => fifo_ramraddr(i),
          ramenr            => fifo_ramenr(i)
    );
  end generate G_SUB_FIFO;
  
  -------------------------------------------------------------------
  -- RAM for SUB_FIFOs
  -------------------------------------------------------------------
  U_SUB_RAMZ : entity work.SUB_RAMZ
  generic map 
  (
           RAMADDR_W => log2(C_NUM_SUBF)+C_SUBF_ADDRW,
           RAMDATA_W => C_PIXEL_BITS        
  )   
  port map 
  (      
        d            => ramd,               
        waddr        => ramwaddr,     
        raddr        => ramraddr,     
        we           => ramenw,     
        clk          => clk,     
        
        q            => ramq     
  ); 
  
  -------------------------------------------------------------------
  -- FIFO almost full
  -------------------------------------------------------------------
  p_fifo_almost_full : process(CLK, RST)
  begin
    if RST = '1' then
      fifo_almost_full   <= '1';
      last_idx           <= (others => '0');
    elsif CLK'event and CLK = '1' then
      if img_size_x = (img_size_x'range => '0') then
        last_idx <= (others => '0');
      else
        last_idx <= unsigned(img_size_x(15 downto 3))-1;
      end if;      
    
      if C_MEMORY_OPTIMIZED = 0 then
        if unsigned(fifo_count(to_integer(wblock_cnt))) > to_unsigned(128-2*8,8) then
          fifo_almost_full <= '1';
        else
          fifo_almost_full <= '0';
        end if;
      else
        if unsigned(fifo_count(to_integer(wblock_cnt))) >= to_unsigned(62,8) then
          fifo_almost_full <= '1';
        -- due to FIFO full latency next subFIFO is in danger of being
        -- overwritten thus its fifo full must be checked ahead
        else
          -- next=0 when current is last
          if wblock_cnt = last_idx then
            -- latency from FIFO full till it is recognized by Host is 2T (64-2)=62
            if unsigned(fifo_count(0)) >= to_unsigned(62,8) then
              fifo_almost_full <= '1';
            else
              fifo_almost_full <= '0';
            end if;
          -- next is just current+1
          else
            -- latency from FIFO full till it is recognized by Host is 2T (64-2)=62
            if unsigned(fifo_count(to_integer(wblock_cnt)+1)) >= to_unsigned(62,8) then
              fifo_almost_full <= '1';
            else
              fifo_almost_full <= '0';
            end if;
          end if;
        end if;
        
      end if;      
    end if;
  end process;
  
  -------------------------------------------------------------------
  -- pixel_cnt
  -------------------------------------------------------------------
  p_pixel_cnt : process(CLK, RST)
  begin
    if RST = '1' then
      pixel_cnt   <= (others => '0');
    elsif CLK'event and CLK = '1' then
      if iram_wren = '1' then
        if pixel_cnt = unsigned(img_size_x)-1 then
          pixel_cnt <= (others => '0');
        else
          pixel_cnt <= pixel_cnt + 1;
        end if;  
      end if;
      
      if sof = '1' then
        pixel_cnt <= (others => '0');
      end if;
    end if;
  end process;
  
  wblock_cnt <= pixel_cnt(pixel_cnt'high downto 3);

  -------------------------------------------------------------------
  -- FIFO half full
  -------------------------------------------------------------------
  p_half_full : process(CLK, RST)
  begin
    if RST = '1' then
      for i in 0 to C_NUM_SUBF-1 loop
        fifo_half_full(i) <= '0';
      end loop;
    elsif CLK'event and CLK = '1' then
      for i in 0 to C_NUM_SUBF-1 loop
        if C_MEMORY_OPTIMIZED = 0 then
          if unsigned(fifo_count(i)) >= 64 then
            fifo_half_full(i) <= '1';
          else
            fifo_half_full(i) <= '0';
          end if;
        else
          fifo_half_full(i) <= fifo_full(i);
        end if;
      end loop;
    end if;
  end process;

  -------------------------------------------------------------------
  -- Mux1
  -------------------------------------------------------------------
  p_mux1 : process(CLK, RST)
  begin
    if RST = '1' then
      for i in 0 to C_NUM_SUBF-1 loop
        fifo_wr(i) <= '0';
      end loop;
    elsif CLK'event and CLK = '1' then
      for i in 0 to C_NUM_SUBF-1 loop
        if wblock_cnt(log2(C_NUM_SUBF)-1 downto 0) = i then
          fifo_wr(i) <= iram_wren;
        else
          fifo_wr(i) <= '0';
        end if;
      end loop;
    end if;
  end process;
  
  -------------------------------------------------------------------
  -- Mux2
  -------------------------------------------------------------------
  p_mux2 : process(CLK, RST)
  begin
    if RST = '1' then
      for i in 0 to C_NUM_SUBF-1 loop
        fifo_rd(i)      <= '0';
      end loop;
      fdct_fifo_empty   <= '0';
      fdct_fifo_hf_full <= '0';
      idx_reg           <= (others => '0');
    elsif CLK'event and CLK = '1' then
      idx_reg <= unsigned(fdct_block_cnt(log2(C_NUM_SUBF)-1 downto 0));
    
      for i in 0 to C_NUM_SUBF-1 loop
        if idx_reg = i then
          fifo_rd(i) <= fdct_fifo_rd;
        else
          fifo_rd(i) <= '0';
        end if;
      end loop;

      fdct_fifo_empty   <= fifo_empty(to_integer(idx_reg));
      fdct_fifo_hf_full <= fifo_half_full(to_integer(idx_reg));
    end if;
  end process;
  
  fdct_fifo_q  <= ramq;
  
  -------------------------------------------------------------------
  -- Mux3
  -------------------------------------------------------------------
  p_mux3 : process(CLK, RST)
  begin
    if RST = '1' then
      ramwaddr         <= (others => '0');
      ramwaddr_offset  <= (others => '0');
      ramwaddr_base    <= (others => '0');
      ramenw           <= '0';
      ramenw_m1        <= '0';
      wr_idx_reg       <= (others => '0');
      ramd             <= (others => '0');
      fifo_data        <= (others => '0');
      fifo_data_d1     <= (others => '0');
    elsif CLK'event and CLK = '1' then
      wr_idx_reg    <= unsigned(wblock_cnt(log2(C_NUM_SUBF)-1 downto 0));
      
      fifo_data    <= iram_wdata;
      fifo_data_d1 <= fifo_data;
      ramd         <= fifo_data_d1;
      
      ramenw_m1 <= fifo_ramenw(to_integer(wr_idx_reg));
      ramenw    <= ramenw_m1;
      
      ramwaddr_offset <= unsigned(fifo_ramwaddr(to_integer(wr_idx_reg)));
      ramwaddr_base   <= to_unsigned(2**C_SUBF_ADDRW, C_SUBF_ADDRW+1) *
                         wr_idx_reg;
      ramwaddr  <= std_logic_vector(ramwaddr_base(ramwaddr'range) + 
                  resize(ramwaddr_offset, ramwaddr'length));
    end if;
  end process;
  
  -------------------------------------------------------------------
  -- Mux4
  -------------------------------------------------------------------
  p_mux4 : process(CLK, RST)
  begin
    if RST = '1' then
      ramraddr          <= (others => '0');
      ramraddr_base     <= (others => '0');
      ramraddr_offset   <= (others => '0');
    elsif CLK'event and CLK = '1' then
      ramraddr_offset <= unsigned(fifo_ramraddr(to_integer(idx_reg)));
      ramraddr_base   <= to_unsigned(2**C_SUBF_ADDRW, C_SUBF_ADDRW+1) *
                         idx_reg;
      ramraddr <= std_logic_vector(ramraddr_base(ramraddr'range) + 
                  resize(unsigned(ramraddr_offset), ramraddr'length));
    end if;
  end process;

end architecture RTL;
-------------------------------------------------------------------------------
-- Architecture: end
-------------------------------------------------------------------------------