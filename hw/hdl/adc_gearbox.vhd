-------------------------------------------------------------------------------
-- adc_gearbox : 8 samples @ 491.52 MHz  ->  16 samples @ 245.76 MHz
--
-- clk_2x and clk_1x come from the same MMCM (phase aligned, 2:1), so this is a
-- synchronous transfer: every clk_1x edge coincides with a clk_2x edge and
-- captures the last two clk_2x words.  Only one register level lives in the
-- 491.52 MHz domain.  The older word goes to the low half, so lane 0 of the
-- output is the oldest sample.
--
-- r1 also changes on the clk_2x edge between two clk_1x edges, so r1 -> cap
-- has only half a clk_1x period (2.03 ns).  'cap' drives nothing but 'dout',
-- so the placer can keep it next to r0/r1; the wide fan-out from 'dout' to
-- the detectors, capture memory and spectrometer then has a full clk_1x
-- period.  (Latency: one extra clk_1x cycle, the same on every channel.)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity adc_gearbox is
  port (
    clk_2x : in  std_logic;
    clk_1x : in  std_logic;
    din    : in  std_logic_vector(127 downto 0);
    dout   : out std_logic_vector(255 downto 0)
  );
end entity adc_gearbox;

architecture rtl of adc_gearbox is
  signal r0, r1 : std_logic_vector(127 downto 0) := (others => '0');
  signal cap    : std_logic_vector(255 downto 0) := (others => '0');
begin

  process (clk_2x)
  begin
    if rising_edge(clk_2x) then
      r0 <= din;
      r1 <= r0;
    end if;
  end process;

  process (clk_1x)
  begin
    if rising_edge(clk_1x) then
      cap  <= r0 & r1;
      dout <= cap;
    end if;
  end process;

end architecture rtl;
