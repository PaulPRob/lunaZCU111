-------------------------------------------------------------------------------
-- ospfb : 32-branch real-input polyphase filter bank, oversampled 32/27,
--         computing the one coarse channel selected by SUBBAND
--
-- Input : one word per clk cycle of D = 27 new consecutive ADC samples
--         (12-bit codes, lane 0 oldest), i.e. fs/27 = 145.636 MHz at
--         fs = 3932.16 MS/s.
-- Output: coarse channel k (0..16), centred on k*fs/32 = k*122.88 MHz and
--         sampled at fs/27 complex, 18 bit, one sample per cycle.  It is
--         the channel shifted to baseband: a tone at k*fs/32 + df appears at
--         +df.  Channels 0 and 16 are real (im = 0).
--
-- Definition (bit exact in hw/sim/ospfb_model.py), for the output of the
-- word whose newest sample is x[n]:
--   v[p]  = round(sum_t COEF(p+32t) * x[n-p-32t] / 2**11)        p = 0..31
--   Z'    = sum_p v[p] * e^{+j 2 pi k p/32}                       (DFT bin k)
--   out   = round(Z' * e^{-j 2 pi k r/32} / G / 32),  r = n + const (mod 32)
-- The rotation by k*r takes the decimation D /= M into account: with
-- critical sampling (D = M = 32) it would be 1.  G (the filter's DC gain)
-- is folded into the rotation table, so the output has the scale of the
-- CSIRO pfb32x16t + rnd_23_18 it replaces: a passband tone of peak A codes
-- gives |out| = 32*A.
--
-- Structure (LAT = 29 cycles from a word entering the window to its output):
--   window   : 917-sample shift register, 27 samples per cycle
--   FIR      : per branch a systolic chain of 16 DSP48E2 (A, M, P registers,
--              P cascade).  Tap t of the output for window state m is taken
--              t cycles later, when the sample it needs has moved 27*t
--              further down the window: tap (p, t) reads window position
--              p + 59*t.  No extra delay lines are needed.
--   DFT bin  : symmetric pairs (p, 32-p) are pre-added, 31 multipliers and
--              two adder trees; the twiddles follow SUBBAND
--   rotation : e^{-j 2 pi k r/32}/G from a free-running r (+27 per cycle),
--              4 multipliers, round and saturate to 18 bit
-- dout_valid is high once the window holds 34 consecutive valid words.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ospfb_pkg.all;

entity ospfb is
  port (
    clk        : in  std_logic;
    subband    : in  unsigned(4 downto 0);                       -- 0..16
    din        : in  std_logic_vector(OS_D*12-1 downto 0);       -- lane j at [12j+11:12j]
    din_valid  : in  std_logic;
    dout_re    : out std_logic_vector(17 downto 0);
    dout_im    : out std_logic_vector(17 downto 0);
    dout_valid : out std_logic
  );
end entity ospfb;

architecture rtl of ospfb is

  attribute use_dsp : string;
  attribute use_dsp of rtl : architecture is "yes";

  constant STRIDE : integer := OS_M + OS_D;                      -- 59
  constant NW     : integer := (OS_M - 1) + STRIDE * (OS_T - 1) + 1;  -- 917
  constant FILL   : integer := (NW + OS_D - 1) / OS_D;           -- 34 words
  constant LAT    : integer := 29;
  constant H      : integer := OS_M / 2;                         -- 16

  type s12_arr_t is array (natural range <>) of signed(11 downto 0);
  type fa_t is array (0 to OS_M-1, 0 to OS_T-1) of signed(11 downto 0);
  type fm_t is array (0 to OS_M-1, 0 to OS_T-1) of signed(29 downto 0);
  type fp_t is array (0 to OS_M-1, 0 to OS_T-1) of signed(39 downto 0);
  type s18_arr_t is array (natural range <>) of signed(17 downto 0);
  type s19_arr_t is array (natural range <>) of signed(18 downto 0);
  type s41_arr_t is array (natural range <>) of signed(40 downto 0);

  signal win  : s12_arr_t(0 to NW-1) := (others => (others => '0'));
  signal vcnt : integer range 0 to FILL := 0;
  signal ok   : std_logic := '0';
  signal vpipe : std_logic_vector(1 to LAT) := (others => '0');

  signal fa : fa_t := (others => (others => (others => '0')));
  signal fm : fm_t := (others => (others => (others => '0')));
  signal fp : fp_t := (others => (others => (others => '0')));

  signal v      : s18_arr_t(0 to OS_M-1) := (others => (others => '0'));
  signal cw, sw : s18_arr_t(0 to H-1) := (others => (others => '0'));
  signal kodd   : std_logic := '0';
  signal pa, pd : s19_arr_t(0 to H-1) := (others => (others => '0'));
  signal mr, mi : s41_arr_t(0 to H-1) := (others => (others => '0'));
  signal tr1, ti1 : s41_arr_t(0 to 7) := (others => (others => '0'));
  signal tr2, ti2 : s41_arr_t(0 to 3) := (others => (others => '0'));
  signal tr3, ti3 : s41_arr_t(0 to 1) := (others => (others => '0'));
  signal zr_f, zi_f : signed(40 downto 0) := (others => '0');
  signal zr, zi : signed(26 downto 0) := (others => '0');

  signal r      : unsigned(4 downto 0) := (others => '0');
  signal rc, rs : signed(17 downto 0) := (others => '0');
  signal p1, p2, p3, p4 : signed(44 downto 0) := (others => '0');
  signal sr, si : signed(45 downto 0) := (others => '0');
  signal ore, oim : signed(17 downto 0) := (others => '0');

  -- round half up (add half an LSB, then arithmetic shift), then saturate
  function rnd_sat(x : signed; sh : natural; w : positive) return signed is
    variable y : signed(x'length-1 downto 0);
    constant MX : signed(x'length-1 downto 0) := to_signed(2**(w-1) - 1, x'length);
    constant MN : signed(x'length-1 downto 0) := to_signed(-2**(w-1), x'length);
  begin
    y := shift_right(x + shift_left(to_signed(1, x'length), sh - 1), sh);
    if y > MX then
      return MX(w-1 downto 0);
    elsif y < MN then
      return MN(w-1 downto 0);
    end if;
    return y(w-1 downto 0);
  end function;

begin

  -----------------------------------------------------------------------------
  -- window: win(a) = x[n - a], n = newest sample; 27 new samples per cycle
  -----------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      for a in 0 to OS_D-1 loop
        win(a) <= signed(din(12*(OS_D-1-a)+11 downto 12*(OS_D-1-a)));
      end loop;
      for a in OS_D to NW-1 loop
        win(a) <= win(a - OS_D);
      end loop;

      -- the output of this window is valid once it holds FILL valid words
      if din_valid = '0' then
        vcnt <= 0;
        ok   <= '0';
      else
        if vcnt /= FILL then
          vcnt <= vcnt + 1;
        end if;
        if vcnt >= FILL - 1 then
          ok <= '1';
        else
          ok <= '0';
        end if;
      end if;
      vpipe <= ok & vpipe(1 to LAT-1);
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- polyphase FIR: 32 systolic chains of 16 taps
  -----------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      for p in 0 to OS_M-1 loop
        for t in 0 to OS_T-1 loop
          fa(p, t) <= win(p + STRIDE*t);
          fm(p, t) <= fa(p, t) * to_signed(COEF(p + OS_M*t), 18);
          if t = 0 then
            fp(p, t) <= resize(fm(p, t), 40);
          else
            fp(p, t) <= fp(p, t-1) + fm(p, t);
          end if;
        end loop;
      end loop;
      for p in 0 to OS_M-1 loop
        v(p) <= rnd_sat(fp(p, OS_T-1), 11, 18);
      end loop;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- DFT bin k:  Re = sum_{p=0..15} (v[p] + v[32-p]) cos(2 pi kp/32)
  --             Im = sum_{p=1..15} (v[p] - v[32-p]) sin(2 pi kp/32)
  -- with v[32] standing for (-1)^k v[16] in the p = 0 term
  -----------------------------------------------------------------------------
  process (clk)
    variable k : integer range 0 to 31;
  begin
    if rising_edge(clk) then
      k := to_integer(subband);
      for p in 0 to H-1 loop
        cw(p) <= to_signed(TW_COS((k * p) mod OS_M), 18);
        sw(p) <= to_signed(TW_SIN((k * p) mod OS_M), 18);
      end loop;
      kodd <= subband(0);

      if kodd = '1' then
        pa(0) <= resize(v(0), 19) - resize(v(H), 19);
      else
        pa(0) <= resize(v(0), 19) + resize(v(H), 19);
      end if;
      pd(0) <= (others => '0');
      for p in 1 to H-1 loop
        pa(p) <= resize(v(p), 19) + resize(v(OS_M - p), 19);
        pd(p) <= resize(v(p), 19) - resize(v(OS_M - p), 19);
      end loop;
      for p in 0 to H-1 loop
        mr(p) <= resize(pa(p) * cw(p), 41);
        mi(p) <= resize(pd(p) * sw(p), 41);
      end loop;
      for i in 0 to 7 loop
        tr1(i) <= mr(2*i) + mr(2*i+1);
        ti1(i) <= mi(2*i) + mi(2*i+1);
      end loop;
      for i in 0 to 3 loop
        tr2(i) <= tr1(2*i) + tr1(2*i+1);
        ti2(i) <= ti1(2*i) + ti1(2*i+1);
      end loop;
      for i in 0 to 1 loop
        tr3(i) <= tr2(2*i) + tr2(2*i+1);
        ti3(i) <= ti2(2*i) + ti2(2*i+1);
      end loop;
      zr_f <= tr3(0) + tr3(1);
      zi_f <= ti3(0) + ti3(1);
      -- Z'/32 with 8 fraction bits (twiddles have 16): fits 27 bits
      zr <= rnd_sat(zr_f, 13, 27);
      zi <= rnd_sat(zi_f, 13, 27);
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- rotation e^{-j 2 pi k r/32} / G.  Every cycle carries one word, so r
  -- advancing by D = 27 per cycle stays in step with the data (its phase
  -- offset is a constant).
  -----------------------------------------------------------------------------
  process (clk)
    variable q : unsigned(9 downto 0);
  begin
    if rising_edge(clk) then
      r  <= r + OS_D;
      q  := subband * r;
      rc <= to_signed(ROT_COS(to_integer(q(4 downto 0))), 18);
      rs <= to_signed(ROT_SIN(to_integer(q(4 downto 0))), 18);

      p1 <= zr * rc;
      p2 <= zi * rs;
      p3 <= zi * rc;
      p4 <= zr * rs;
      sr <= resize(p1, 46) + resize(p2, 46);
      si <= resize(p3, 46) - resize(p4, 46);
      ore <= rnd_sat(sr, 24, 18);
      oim <= rnd_sat(si, 24, 18);
    end if;
  end process;

  dout_re    <= std_logic_vector(ore);
  dout_im    <= std_logic_vector(oim);
  dout_valid <= vpipe(LAT);

end architecture rtl;
