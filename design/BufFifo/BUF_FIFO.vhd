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

  constant C_NUM_SUBF     : integer := ((C_MAX_LINE_WIDTH/8));
  
  type T_DATA_ARR is array (0 to C_NUM_SUBF-1) of std_logic_vector(23 downto 0);
  type T_CNT_ARR  is array (0 to C_NUM_SUBF-1) of 
    std_logic_vector(7-C_MEMORY_OPTIMIZED downto 0);

  signal fifo_rd          : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_wr          : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_data        : std_logic_vector(23 downto 0);
  signal fifo_data_d1     : std_logic_vector(23 downto 0);
  signal fifo_q           : T_DATA_ARR;
  signal fifo_full        : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_empty       : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_half_full   : std_logic_vector(C_NUM_SUBF-1 downto 0);
  signal fifo_count       : T_CNT_ARR;
  
  signal pixel_cnt        : unsigned(15 downto 0);
  signal wblock_cnt       : unsigned(12 downto 0);
  signal last_idx         : unsigned(12 downto 0);
  signal idx_reg          : unsigned(log2(C_NUM_SUBF)-1 downto 0);
  
-------------------------------------------------------------------------------
-- Architecture: begin
-------------------------------------------------------------------------------
begin

  -------------------------------------------------------------------
  -- SUB_FIFOs
  -------------------------------------------------------------------
  G_SUB_FIFO : for i in 0 to C_NUM_SUBF-1 generate
    
    U_SUB_FIFO : entity work.FIFO   
    generic map
    (
          DATA_WIDTH        => 24,
          ADDR_WIDTH        => 7-C_MEMORY_OPTIMIZED
    )
    port map 
    (        
          rst               => RST,
          clk               => CLK,
          rinc              => fifo_rd(i),
          winc              => fifo_wr(i),
          datai             => fifo_data,
  
          datao             => fifo_q(i),
          fullo             => fifo_full(i),
          emptyo            => fifo_empty(i),
          count             => fifo_count(i)
    );
  end generate G_SUB_FIFO;
  
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
    
      if last_idx > 0 then
        if C_MEMORY_OPTIMIZED = 0 then
          if unsigned(fifo_count(to_integer(last_idx)-2)) > to_unsigned(128-2*8,8) then
            fifo_almost_full <= '1';
          else
            fifo_almost_full <= '0';
          end if;
        else
           if unsigned(fifo_count(to_integer(last_idx))) = to_unsigned(64,8) then
            fifo_almost_full <= '1';
          else
            fifo_almost_full <= '0';
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
        if unsigned(fifo_count(i)) >= 64 then
          fifo_half_full(i) <= '1';
        else
          fifo_half_full(i) <= '0';
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
      fifo_data <= (others => '0');
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
      
      fifo_data <= iram_wdata;
    end if;
  end process;
  
  -------------------------------------------------------------------
  -- Mux2
  -------------------------------------------------------------------
  p_mux2 : process(CLK, RST)
  begin
    if RST = '1' then
      for i in 0 to C_NUM_SUBF-1 loop
        fifo_rd(i)    <= '0';
      end loop;
      fdct_fifo_empty <= '0';
      fdct_fifo_q     <= (others => '0');
      fdct_fifo_hf_full    <= '0';
      idx_reg              <= (others => '0');
    elsif CLK'event and CLK = '1' then
      idx_reg <= unsigned(fdct_block_cnt(log2(C_NUM_SUBF)-1 downto 0));
    
      for i in 0 to C_NUM_SUBF-1 loop
        if idx_reg = i then
          fifo_rd(i)      <= fdct_fifo_rd;
        else
          fifo_rd(i) <= '0';
        end if;
      end loop;

      fdct_fifo_empty   <= fifo_empty(to_integer(idx_reg));
      fdct_fifo_q       <= fifo_q(to_integer(idx_reg));
      fdct_fifo_hf_full <= fifo_half_full(to_integer(idx_reg));
    end if;
  end process;
  
  

end architecture RTL;
-------------------------------------------------------------------------------
-- Architecture: end
-------------------------------------------------------------------------------