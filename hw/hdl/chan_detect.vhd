-------------------------------------------------------------------------------
-- chan_detect : per-channel threshold detector
--
-- For every sample: hit = |x| > thresh  (|-32768| saturates to 32767).
-- For every lane L it also outputs dist(L) = number of samples since the most
-- recent hit at or before lane L (0 if lane L itself is a hit), saturating at
-- 255.  This is what the trigger logic uses to evaluate sample-exact
-- coincidence windows that straddle clock-cycle boundaries.
--
-- Latency: din (cycle c) -> hit/dist valid 3 clocks later (LATENCY = 3).
-- peak: max |x| since the last peak_clr pulse (for setting thresholds).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.luna_pkg.all;

entity chan_detect is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    din      : in  std_logic_vector(WORD_W-1 downto 0);
    thresh   : in  unsigned(15 downto 0);
    hit      : out std_logic_vector(LANES-1 downto 0);
    dist     : out dist_lane_t;
    peak     : out unsigned(15 downto 0);
    peak_clr : in  std_logic
  );
end entity chan_detect;

architecture rtl of chan_detect is
  type abs_arr_t is array (0 to LANES-1) of unsigned(15 downto 0);
  type m4_arr_t  is array (0 to 3) of unsigned(15 downto 0);

  signal a_s1    : abs_arr_t := (others => (others => '0'));
  signal hit_s2  : std_logic_vector(LANES-1 downto 0) := (others => '0');
  signal m4_s2   : m4_arr_t := (others => (others => '0'));
  signal m16_s3  : unsigned(15 downto 0) := (others => '0');
  signal peak_r  : unsigned(15 downto 0) := (others => '0');
  signal age     : unsigned(DIST_W-1 downto 0) := DIST_MAX;
  signal hit_s3  : std_logic_vector(LANES-1 downto 0) := (others => '0');
  signal dist_s3 : dist_lane_t := (others => DIST_MAX);
  signal thr_r   : unsigned(15 downto 0) := (others => '1');

  function umax(a, b : unsigned) return unsigned is
  begin
    if a > b then return a; else return b; end if;
  end function;
begin

  -- S1 : absolute value
  process (clk)
    variable s : signed(15 downto 0);
  begin
    if rising_edge(clk) then
      thr_r <= thresh;
      for k in 0 to LANES-1 loop
        s := signed(din(SW*k+SW-1 downto SW*k));
        if s = to_signed(-32768, 16) then
          a_s1(k) <= to_unsigned(32767, 16);
        elsif s < 0 then
          a_s1(k) <= unsigned(-s);
        else
          a_s1(k) <= unsigned(s);
        end if;
      end loop;
    end if;
  end process;

  -- S2 : threshold compare, first level of the peak tree
  process (clk)
  begin
    if rising_edge(clk) then
      for k in 0 to LANES-1 loop
        if a_s1(k) > thr_r then
          hit_s2(k) <= '1';
        else
          hit_s2(k) <= '0';
        end if;
      end loop;
      for g in 0 to 3 loop
        m4_s2(g) <= umax(umax(a_s1(4*g), a_s1(4*g+1)), umax(a_s1(4*g+2), a_s1(4*g+3)));
      end loop;
    end if;
  end process;

  -- S3 : per-lane distance since last hit, carried across cycles by 'age'
  --      age = distance from lane 0 of the current cycle back to the most
  --            recent hit in an earlier cycle (saturating)
  process (clk)
    variable d      : unsigned(DIST_W-1 downto 0);
    variable last_k : integer range 0 to LANES-1;
    variable any    : boolean;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        age     <= DIST_MAX;
        hit_s3  <= (others => '0');
        dist_s3 <= (others => DIST_MAX);
      else
        any    := false;
        last_k := 0;
        for L in 0 to LANES-1 loop
          d := sat_add(age, L);
          for k in 0 to L loop
            if hit_s2(k) = '1' then
              d := to_unsigned(L - k, DIST_W);
            end if;
          end loop;
          dist_s3(L) <= d;
          if hit_s2(L) = '1' then
            any    := true;
            last_k := L;
          end if;
        end loop;
        if any then
          age <= to_unsigned(LANES - last_k, DIST_W);
        else
          age <= sat_add(age, LANES);
        end if;
        hit_s3 <= hit_s2;
      end if;
    end if;
  end process;

  -- peak hold
  process (clk)
  begin
    if rising_edge(clk) then
      m16_s3 <= umax(umax(m4_s2(0), m4_s2(1)), umax(m4_s2(2), m4_s2(3)));
      if rst = '1' or peak_clr = '1' then
        peak_r <= (others => '0');
      else
        peak_r <= umax(peak_r, m16_s3);
      end if;
    end if;
  end process;

  hit  <= hit_s3;
  dist <= dist_s3;
  peak <= peak_r;

end architecture rtl;
