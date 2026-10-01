-------------------------------------------------------------------------------
-- capture_mem : simple dual port capture RAM for one channel
--   depth 2**AW words of 256 bits (default 4096 = 4 banks x 1024 words)
--   inferred as UltraRAM (4 x URAM288 per channel, 32 in total)
--   read latency = 2 clocks (address in -> dout)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity capture_mem is
  generic (
    AW : integer := 12;
    DW : integer := 256
  );
  port (
    clk   : in  std_logic;
    we    : in  std_logic;
    waddr : in  unsigned(AW-1 downto 0);
    wdata : in  std_logic_vector(DW-1 downto 0);
    raddr : in  unsigned(AW-1 downto 0);
    dout  : out std_logic_vector(DW-1 downto 0)
  );
end entity capture_mem;

architecture rtl of capture_mem is
  type mem_t is array (0 to 2**AW-1) of std_logic_vector(DW-1 downto 0);
  signal mem : mem_t;
  attribute ram_style : string;
  attribute ram_style of mem : signal is "ultra";

  signal rd1, rd2 : std_logic_vector(DW-1 downto 0);
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if we = '1' then
        mem(to_integer(waddr)) <= wdata;
      end if;
      rd1 <= mem(to_integer(raddr));
      rd2 <= rd1;
    end if;
  end process;

  dout <= rd2;

end architecture rtl;
