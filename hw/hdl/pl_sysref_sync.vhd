-------------------------------------------------------------------------------
-- pl_sysref_sync : capture the LMK04208 PL SYSREF (7.68 MHz, pins AK17/AK16)
--
-- The LMK04208 launches SYSREF edge-aligned with FPGA_REFCLK_OUT (122.88 MHz).
-- clk_1x (245.76 MHz) is phase aligned to that reference by the MMCM, so we
-- sample SYSREF on the FALLING edge of clk_1x (about 2 ns away from any SYSREF
-- transition), then move it onto the rising edge of clk_1x and finally into
-- the RFDC AXI-Stream clock domain (clk_2x) as required for user_sysref_adc.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity pl_sysref_sync is
  port (
    sysref_in_p     : in  std_logic;
    sysref_in_n     : in  std_logic;
    clk_1x          : in  std_logic;
    clk_2x          : in  std_logic;
    user_sysref_adc : out std_logic;   -- clk_2x domain, to RFDC
    user_sysref_dac : out std_logic;   -- clk_1x domain, to RFDC DAC tile (if used)
    sysref_1x       : out std_logic    -- clk_1x domain, for status/debug
  );
end entity pl_sysref_sync;

architecture rtl of pl_sysref_sync is
  signal sysref_ibuf : std_logic;
  signal s_fall      : std_logic := '0';
  signal s_1x        : std_logic := '0';
  signal s_1x_d      : std_logic := '0';
  signal s_2x        : std_logic := '0';

  attribute IOB : string;
  attribute IOB of s_fall : signal is "TRUE";
begin

  -- IOSTANDARD / DIFF_TERM_ADV are set in the XDC (HP bank 64, 1.8 V)
  u_ibuf : IBUFDS
    port map (I => sysref_in_p, IB => sysref_in_n, O => sysref_ibuf);

  process (clk_1x)
  begin
    if falling_edge(clk_1x) then
      s_fall <= sysref_ibuf;
    end if;
  end process;

  process (clk_1x)
  begin
    if rising_edge(clk_1x) then
      s_1x   <= s_fall;
      s_1x_d <= s_1x;
    end if;
  end process;

  process (clk_2x)
  begin
    if rising_edge(clk_2x) then
      s_2x <= s_1x;
    end if;
  end process;

  user_sysref_adc <= s_2x;
  user_sysref_dac <= s_1x_d;
  sysref_1x       <= s_1x;

end architecture rtl;
