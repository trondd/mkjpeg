--------------------------------------------------------------------------------
--                                                                            --
--                          V H D L    F I L E                                --
--                          COPYRIGHT (C) 2009                                --
--                                                                            --
--------------------------------------------------------------------------------
--
-- Title       : JPEG_PKG
-- Design      : JPEG_ENC
-- Author      : Michal Krepa
--
--------------------------------------------------------------------------------
--
-- File        : JPEG_PKG.VHD
-- Created     : Sat Mar 7 2009
--
--------------------------------------------------------------------------------
--
--  Description : Package for JPEG core
--
--------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use ieee.numeric_std.all;
  
package JPEG_PKG is

  -- do not change, constant
  constant C_HDR_SIZE         : integer := 407;
  
  -- warning! this parameter heavily affects memory size required
  -- if expected image width is known change this parameter to match this
  -- otherwise some onchip RAM will be wasted and never used
  constant C_MAX_LINE_WIDTH   : integer := 640;

  -- 0=highest clock per pixel performance
  -- 1=memory used by BUF_FIFO halved, speed performance reduced by circa 18%
  constant C_MEMORY_OPTIMIZED : integer := 1;
  
  type T_SM_SETTINGS is record
    x_cnt               : unsigned(15 downto 0);
    y_cnt               : unsigned(15 downto 0);
    cmp_idx             : unsigned(1 downto 0);
  end record;
  
  constant C_SM_SETTINGS : T_SM_SETTINGS := 
  (
    (others => '0'),
    (others => '0'),
    (others => '0')
  );
  
  function log2(n : natural) return natural;
  
end package JPEG_PKG;

package body JPEG_PKG is

  -----------------------------------------------------------------------------
  function log2(n : natural) 
  return natural is
  begin
    for i in 0 to 31 loop
      if (2**i) >= n then
        return i;
      end if;
    end loop;
    return 32;
  end log2;
  -----------------------------------------------------------------------------

end package body JPEG_PKG;