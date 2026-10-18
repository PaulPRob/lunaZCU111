-------------------------------------------------------------------------------
-- gearbox_16_27 : 16 samples per clk_1x cycle -> words of 27 samples
--
-- clk_1x domain (245.76 MHz).  Input: 16 consecutive 16-bit samples per
-- cycle (12-bit ADC code in bits 15..4, lane 0 oldest), with the sample index
-- of lane 0.  Output: 27 consecutive 12-bit codes (lane 0 oldest) with the
-- sample index of lane 0 and a valid strobe, 16 words every 27 cycles
-- (fs/27 = 145.636 M words/s, the rate of the oversampled filter bank).
--
-- The last three input blocks form a 48-sample window W (W(0) oldest).
-- 'need' is the position, counted from the start of the newest block, of the
-- last sample of the next output word.  When it falls in the newest block
-- (need <= 15) the word is W(need+6 .. need+32); then need advances by
-- 27 - 16 = 11, otherwise by -16.  27 > 16, so at most one word per cycle.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gearbox_16_27 is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    din       : in  std_logic_vector(255 downto 0);
    ts_in     : in  unsigned(63 downto 0);          -- sample index of din lane 0
    dout      : out std_logic_vector(27*12-1 downto 0);
    ts_out    : out unsigned(63 downto 0);          -- sample index of dout lane 0
    dout_valid: out std_logic
  );
end entity gearbox_16_27;

architecture rtl of gearbox_16_27 is
  type s12_arr_t is array (natural range <>) of std_logic_vector(11 downto 0);
  signal b0, b1, b2 : s12_arr_t(0 to 15) := (others => (others => '0'));
  signal ts0        : unsigned(63 downto 0) := (others => '0');
  signal need       : integer range 0 to 26 := 26;
begin

  process (clk)
    variable w : s12_arr_t(0 to 47);
  begin
    if rising_edge(clk) then
      for l in 0 to 15 loop
        b0(l) <= din(16*l+15 downto 16*l+4);
      end loop;
      b1  <= b0;
      b2  <= b1;
      ts0 <= ts_in;

      w := b2 & b1 & b0;
      dout_valid <= '0';
      if need <= 15 then
        for j in 0 to 26 loop
          dout(12*j+11 downto 12*j) <= w(need + 6 + j);
        end loop;
        ts_out     <= ts0 - 26 + to_unsigned(need, 64);
        dout_valid <= '1';
        need       <= need + 11;
      else
        need <= need - 16;
      end if;

      if rst = '1' then
        need       <= 26;
        dout_valid <= '0';
      end if;
    end if;
  end process;

end architecture rtl;
