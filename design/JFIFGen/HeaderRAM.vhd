-- HeaderRam.vhd Khaleghian 8 Nov 2010

library ieee;
library work;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use work.all;
entity HeaderRam is
port (
d : in STD_LOGIC_VECTOR(7 downto 0);
waddr : in STD_LOGIC_VECTOR(9 downto 0);
raddr : in STD_LOGIC_VECTOR(9 downto 0);
we : in STD_LOGIC;
clk : in STD_LOGIC;
q : out STD_LOGIC_VECTOR(7 downto 0)
);
end HeaderRam;

architecture syn of HeaderRam is
type ram_type is array (1023 downto 0) of std_logic_vector (7 downto 0);
signal RAM : ram_type;
signal read_addr: STD_LOGIC_VECTOR(9 downto 0);
begin
q <= RAM(conv_integer(read_addr)) ;
process (clk)
begin
if clk'event and clk = '1'
then
if we='1' then
RAM(conv_integer(waddr)) <= d;
end if;
read_addr <= raddr;
end if;
end process;
end syn; 
