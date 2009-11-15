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
        iram_wdata         : in  std_logic_vector(C_PIXEL_BITS-1 downto 0);
        fifo_almost_full   : out std_logic;
        
        -- FDCT
        fdct_fifo_rd       : in  std_logic;
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

  signal pixel_cnt        : unsigned(15 downto 0);
  signal line_cnt         : unsigned(15 downto 0);

  signal ramq             : STD_LOGIC_VECTOR(C_PIXEL_BITS-1 downto 0);
  signal ramd             : STD_LOGIC_VECTOR(C_PIXEL_BITS-1 downto 0);
  signal ramwaddr         : unsigned(log2(C_MAX_LINE_WIDTH*8)-1 downto 0);
  signal ramenw           : STD_LOGIC;
  signal ramraddr         : unsigned(log2(C_MAX_LINE_WIDTH*8)-1 downto 0);
  
  signal pix_inblk_cnt    : unsigned(7 downto 0);
  signal line_inblk_cnt   : unsigned(7 downto 0);
  
  signal read_block_cnt   : unsigned(12 downto 0);
  signal write_block_cnt  : unsigned(12 downto 0);
  
  signal ramraddr_int     : unsigned(23 downto 0);
  signal raddr_base_line  : unsigned(23 downto 0);
  signal raddr_tmp        : unsigned(15 downto 0);
  signal ramwaddr_d1      : unsigned(log2(C_MAX_LINE_WIDTH*8)-1 downto 0);
  
  signal block_lock       : unsigned(C_MAX_LINE_WIDTH/8-1 downto 0);
  
-------------------------------------------------------------------------------
-- Architecture: begin
-------------------------------------------------------------------------------
begin  
  -------------------------------------------------------------------
  -- RAM for SUB_FIFOs
  -------------------------------------------------------------------
  U_SUB_RAMZ : entity work.SUB_RAMZ
  generic map 
  (
           RAMADDR_W => log2(C_MAX_LINE_WIDTH*8),
           RAMDATA_W => C_PIXEL_BITS        
  )   
  port map 
  (      
        d            => ramd,               
        waddr        => std_logic_vector(ramwaddr_d1),     
        raddr        => std_logic_vector(ramraddr),     
        we           => ramenw,     
        clk          => clk,     
        
        q            => ramq     
  ); 
  
  -------------------------------------------------------------------
  -- register RAM data input
  -------------------------------------------------------------------
  p_mux1 : process(CLK, RST)
  begin
    if RST = '1' then
      ramenw           <= '0';
      ramd             <= (others => '0');
    elsif CLK'event and CLK = '1' then
      ramd      <= iram_wdata;
      ramenw    <= iram_wren;
    end if;
  end process;
  
  -------------------------------------------------------------------
  -- resolve RAM write address
  -------------------------------------------------------------------
  p_pixel_cnt : process(CLK, RST)
  begin
    if RST = '1' then
      pixel_cnt   <= (others => '0');
      line_cnt    <= (others => '0');
      ramwaddr    <= (others => '0');
      ramwaddr_d1 <= (others => '0');      
    elsif CLK'event and CLK = '1' then
      ramwaddr_d1 <= ramwaddr;
    
      if iram_wren = '1' then
        -- pixel index in line
        if pixel_cnt = unsigned(img_size_x)-1 then
          pixel_cnt <= (others => '0');
          -- line counter
          line_cnt  <= line_cnt + 1;
          -- RAM is only 8 lines buffer
          if line_cnt(2 downto 0) = 8-1 then
            ramwaddr <= (others => '0');
          else
            ramwaddr  <= ramwaddr + 1;
          end if;
        else
          pixel_cnt <= pixel_cnt + 1;
          ramwaddr  <= ramwaddr + 1;
        end if;  
      end if;
      
      if sof = '1' then
        pixel_cnt <= (others => '0');
        ramwaddr  <= (others => '0');
      end if;
    end if;
  end process;

  write_block_cnt <= pixel_cnt(15 downto 3);

  -------------------------------------------------------------------
  -- lock written blocks, unlock after read
  -------------------------------------------------------------------
  p_mux6 : process(CLK, RST)
  begin
    if RST = '1' then
      block_lock <= (others => '0');
    elsif CLK'event and CLK = '1' then
      if pixel_cnt(2 downto 0) = 8-1 then
        if line_cnt(2 downto 0) = 8-1 then
          block_lock(to_integer(write_block_cnt)) <= '1';
        end if;
      end if;
      
      if pix_inblk_cnt = 8-1 then
        if line_inblk_cnt = 8-1 then
          block_lock(to_integer(read_block_cnt)) <= '0';
        end if;
      end if; 
    end if;
  end process;
  
  -------------------------------------------------------------------
  -- FIFO half full / almost full flag generation
  -------------------------------------------------------------------
  p_mux3 : process(CLK, RST)
  begin
    if RST = '1' then
      fdct_fifo_hf_full   <= '0';
      fifo_almost_full    <= '0';
    elsif CLK'event and CLK = '1' then
        
      if block_lock(to_integer(read_block_cnt)) = '1' then
        fdct_fifo_hf_full <= '1';
      else
        fdct_fifo_hf_full <= '0';
      end if;
      
      if write_block_cnt = unsigned(img_size_x(15 downto 3))-1 then
        if block_lock(0) = '1' then
          fifo_almost_full <= '1';
        else
          fifo_almost_full <= '0';
        end if;
      elsif block_lock(to_integer(write_block_cnt+1)) = '1' then
        fifo_almost_full <= '1';
      else
        fifo_almost_full <= '0';
      end if;
      
    end if;
  end process;
  
  -------------------------------------------------------------------
  -- read side
  -------------------------------------------------------------------
  p_mux5 : process(CLK, RST)
  begin
    if RST = '1' then
      read_block_cnt <= (others => '0');
      pix_inblk_cnt  <= (others => '0');
      line_inblk_cnt <= (others => '0');
    elsif CLK'event and CLK = '1' then
      if fdct_fifo_rd = '1' then
        if pix_inblk_cnt = 8-1 then
          pix_inblk_cnt <= (others => '0');
          if line_inblk_cnt = 8-1 then
            line_inblk_cnt <= (others => '0');
            if read_block_cnt = unsigned(img_size_x(15 downto 3))-1 then
              read_block_cnt <= (others => '0');
            else
              read_block_cnt <= read_block_cnt + 1;
            end if;
          else
            line_inblk_cnt <= line_inblk_cnt + 1;
          end if;
        else
          pix_inblk_cnt <= pix_inblk_cnt + 1;
        end if;
      end if;
      
      if sof = '1' then
        read_block_cnt <= (others => '0');
        pix_inblk_cnt  <= (others => '0');
        line_inblk_cnt <= (others => '0');
      end if;
      
    end if;
  end process;
  
  -- generate RAM data output based on 16 or 24 bit mode selection
  fdct_fifo_q <= (ramq(15 downto 11) & "000" & 
                 ramq(10 downto 5) & "00" & 
                 ramq(4 downto 0) & "000") when C_PIXEL_BITS = 16 else 
                 std_logic_vector(resize(unsigned(ramq), 24));
  
  
  ramraddr <= ramraddr_int(ramraddr'range);
  
  -------------------------------------------------------------------
  -- resolve RAM read address
  -------------------------------------------------------------------
  p_mux4 : process(CLK, RST)
  begin
    if RST = '1' then
      ramraddr_int          <= (others => '0');
    elsif CLK'event and CLK = '1' then
      raddr_base_line <= line_inblk_cnt * unsigned(img_size_x);
      raddr_tmp       <= (read_block_cnt & "000") + pix_inblk_cnt;
    
      ramraddr_int <= raddr_tmp + raddr_base_line;
    end if;
  end process;

end architecture RTL;
-------------------------------------------------------------------------------
-- Architecture: end
-------------------------------------------------------------------------------