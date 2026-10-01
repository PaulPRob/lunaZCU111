-------------------------------------------------------------------------------
-- trig_logic : sample-exact coincidence / anti-coincidence trigger
--
-- Inputs come from 8 x chan_detect, all describing clock cycle cyc_in:
--   hit(j)(L)  : channel j sample L exceeded its threshold
--   dist(j)(L) : samples since the most recent hit of channel j at or before L
--
-- A hit of channel j lies inside the W-sample window that ends at sample L
-- (i.e. [L-W+1, L]) exactly when dist(j)(L) <= W-1.
--
-- COINCIDENCE (mode 0): trigger at sample q if an enabled channel hits at q
--   and at least N enabled channels have a hit inside [q-W+1, q].
--   This fires on the hit that completes the coincidence.
--
-- ANTI-COINCIDENCE (mode 1): trigger at sample p if enabled channel r hits at p
--   and no OTHER enabled channel hits anywhere in [p-W+1, p+W-1].
--   Evaluated W-1 samples late (at q = p+W-1) using a variable delay:
--     quiet_j(p) : dist_j(p)   >= W  -> no hit in [p-W+1, p]
--     quiet_j(q) : dist_j(q)   >= W  -> no hit in [p,     p+W-1]
--   The reported trigger position is p (not q).
--
-- SOFT : soft_trig pulse, position = current sample, always accepted.
--
-- Outputs one trigger per clock at most (earliest lane wins).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.luna_pkg.all;

entity trig_logic is
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    -- config (quasi-static)
    mode_anti  : in  std_logic;
    n_req      : in  unsigned(3 downto 0);   -- 1..8
    win        : in  unsigned(7 downto 0);   -- 1..255 samples
    ch_mask    : in  std_logic_vector(NCH-1 downto 0);
    arm        : in  std_logic;
    soft_trig  : in  std_logic;
    -- detector outputs
    cyc_in     : in  unsigned(CYC_W-1 downto 0);
    hit        : in  lanes_arr_t;
    dist       : in  dist_arr_t;
    -- trigger
    trig_valid : out std_logic;
    trig_pos   : out unsigned(63 downto 0);
    trig_mask  : out std_logic_vector(NCH-1 downto 0);
    trig_src   : out std_logic_vector(1 downto 0)
  );
end entity trig_logic;

architecture rtl of trig_logic is

  -- per-lane arrays of channel vectors
  type lane_chv_t is array (0 to LANES-1) of std_logic_vector(NCH-1 downto 0);

  ---------------------------------------------------------------------------
  -- coincidence pipeline
  signal c1_inwin : lane_chv_t;
  signal c1_hitm  : std_logic_vector(LANES-1 downto 0);
  signal c1_cyc   : unsigned(CYC_W-1 downto 0);
  signal c2_ge    : std_logic_vector(LANES-1 downto 0);
  signal c2_inwin : lane_chv_t;
  signal c2_cyc   : unsigned(CYC_W-1 downto 0);
  signal c3_valid : std_logic := '0';
  signal c3_pos   : unsigned(63 downto 0);
  signal c3_mask  : std_logic_vector(NCH-1 downto 0);

  ---------------------------------------------------------------------------
  -- anti-coincidence pipeline
  -- per channel a 32 bit word per cycle: bits 15..0 = hit, 31..16 = quiet
  type chword_t  is array (0 to NCH-1) of std_logic_vector(2*LANES-1 downto 0);
  type hist_t    is array (0 to LANES) of chword_t;           -- 17 cycles
  signal a1_x    : chword_t := (others => (others => '0'));
  signal a1_cyc  : unsigned(CYC_W-1 downto 0);
  signal hist    : hist_t := (others => (others => (others => '0')));                                     -- hist(i) = a1_x from i cycles ago (hist(0) unused)
  signal a2_hi, a2_lo, a2_x : chword_t;
  signal a2_cyc  : unsigned(CYC_W-1 downto 0);
  signal a3_hd   : lanes_arr_t;     -- delayed hit   (position p)
  signal a3_qd   : lanes_arr_t;     -- delayed quiet (position p)
  signal a3_q    : lanes_arr_t;     -- current quiet (position q = p + W - 1)
  signal a3_cyc  : unsigned(CYC_W-1 downto 0);
  signal a4_anti : std_logic_vector(LANES-1 downto 0);
  signal a4_who  : lane_chv_t;
  signal a4_cyc  : unsigned(CYC_W-1 downto 0);
  signal a5_valid: std_logic := '0';
  signal a5_pos  : unsigned(63 downto 0);
  signal a5_mask : std_logic_vector(NCH-1 downto 0);

  signal d_samp  : unsigned(7 downto 0);    -- W-1
  signal d_cyc   : integer range 0 to 15;
  signal d_lane  : integer range 0 to 15;

  signal soft_d  : std_logic := '0';
  signal soft_cyc: unsigned(CYC_W-1 downto 0);

begin

  d_samp <= win - 1 when win /= 0 else (others => '0');
  d_cyc  <= to_integer(d_samp(7 downto 4));
  d_lane <= to_integer(d_samp(3 downto 0));

  ---------------------------------------------------------------------------
  -- COINCIDENCE
  ---------------------------------------------------------------------------
  process (clk)
    variable hm : std_logic;
  begin
    if rising_edge(clk) then
      -- C1
      for L in 0 to LANES-1 loop
        hm := '0';
        for j in 0 to NCH-1 loop
          if ch_mask(j) = '1' and dist(j)(L) < win then
            c1_inwin(L)(j) <= '1';
          else
            c1_inwin(L)(j) <= '0';
          end if;
          hm := hm or (ch_mask(j) and hit(j)(L));
        end loop;
        c1_hitm(L) <= hm;
      end loop;
      c1_cyc <= cyc_in;

      -- C2
      for L in 0 to LANES-1 loop
        if c1_hitm(L) = '1' and popcount(c1_inwin(L)) >= resize(n_req, 5) then
          c2_ge(L) <= '1';
        else
          c2_ge(L) <= '0';
        end if;
      end loop;
      c2_inwin <= c1_inwin;
      c2_cyc   <= c1_cyc;

      -- C3 : earliest lane
      c3_valid <= '0';
      for L in LANES-1 downto 0 loop
        if c2_ge(L) = '1' then
          c3_valid <= '1';
          c3_pos   <= c2_cyc & to_unsigned(L, 4);
          c3_mask  <= c2_inwin(L);
        end if;
      end loop;

      if rst = '1' then
        c3_valid <= '0';
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- ANTI-COINCIDENCE
  ---------------------------------------------------------------------------
  process (clk)
    variable cat : std_logic_vector(4*LANES-1 downto 0);
    variable quiet_ok : std_logic_vector(NCH-1 downto 0);
    variable others_quiet : std_logic;
    variable any : std_logic;
  begin
    if rising_edge(clk) then
      -- A1 : pack hit + quiet
      for j in 0 to NCH-1 loop
        for L in 0 to LANES-1 loop
          a1_x(j)(L) <= hit(j)(L);
          if dist(j)(L) >= win then
            a1_x(j)(LANES+L) <= '1';
          else
            a1_x(j)(LANES+L) <= '0';
          end if;
        end loop;
      end loop;
      a1_cyc <= cyc_in;

      -- history of a1_x : hist(i) holds a1_x from i cycles before
      hist(1) <= a1_x;
      for i in 2 to LANES loop
        hist(i) <= hist(i-1);
      end loop;

      -- A2 : pick the two words that contain samples delayed by W-1
      for j in 0 to NCH-1 loop
        if d_cyc = 0 then
          a2_hi(j) <= a1_x(j);
        else
          a2_hi(j) <= hist(d_cyc)(j);
        end if;
        a2_lo(j) <= hist(d_cyc + 1)(j);
      end loop;
      a2_x   <= a1_x;
      a2_cyc <= a1_cyc;

      -- A3 : lane shift. delayed(L) = sample at (cycle*16 + L - D)
      for j in 0 to NCH-1 loop
        -- hit bits
        cat := (others => '0');
        cat(2*LANES-1 downto 0) := a2_hi(j)(LANES-1 downto 0) & a2_lo(j)(LANES-1 downto 0);
        for L in 0 to LANES-1 loop
          a3_hd(j)(L) <= cat(LANES + L - d_lane);
        end loop;
        -- quiet bits
        cat(2*LANES-1 downto 0) := a2_hi(j)(2*LANES-1 downto LANES) & a2_lo(j)(2*LANES-1 downto LANES);
        for L in 0 to LANES-1 loop
          a3_qd(j)(L) <= cat(LANES + L - d_lane);
        end loop;
        a3_q(j) <= a2_x(j)(2*LANES-1 downto LANES);
      end loop;
      a3_cyc <= a2_cyc;

      -- A4 : exactly-one-channel condition per lane
      for L in 0 to LANES-1 loop
        for j in 0 to NCH-1 loop
          quiet_ok(j) := (not ch_mask(j)) or (a3_qd(j)(L) and a3_q(j)(L));
        end loop;
        any := '0';
        for r in 0 to NCH-1 loop
          others_quiet := '1';
          for j in 0 to NCH-1 loop
            if j /= r then
              others_quiet := others_quiet and quiet_ok(j);
            end if;
          end loop;
          a4_who(L)(r) <= a3_hd(r)(L) and ch_mask(r) and others_quiet;
          any := any or (a3_hd(r)(L) and ch_mask(r) and others_quiet);
        end loop;
        a4_anti(L) <= any;
      end loop;
      a4_cyc <= a3_cyc;

      -- A5 : earliest lane, position corrected back by D
      a5_valid <= '0';
      for L in LANES-1 downto 0 loop
        if a4_anti(L) = '1' then
          a5_valid <= '1';
          a5_pos   <= a4_cyc & to_unsigned(L, 4);   -- position q; D subtracted below
          a5_mask  <= a4_who(L);
        end if;
      end loop;

      if rst = '1' then
        a5_valid <= '0';
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- output arbitration
  ---------------------------------------------------------------------------
  process (clk)
  begin
    if rising_edge(clk) then
      soft_d   <= soft_trig;
      soft_cyc <= cyc_in;
      trig_valid <= '0';
      if soft_d = '1' then
        trig_valid <= '1';
        trig_pos   <= soft_cyc & "0000";
        trig_mask  <= (others => '0');
        trig_src   <= SRC_SOFT;
      elsif arm = '1' and mode_anti = '0' and c3_valid = '1' then
        trig_valid <= '1';
        trig_pos   <= c3_pos;
        trig_mask  <= c3_mask;
        trig_src   <= SRC_COINC;
      elsif arm = '1' and mode_anti = '1' and a5_valid = '1' then
        trig_valid <= '1';
        trig_pos   <= a5_pos - resize(d_samp, 64);
        trig_mask  <= a5_mask;
        trig_src   <= SRC_ANTI;
      end if;
      if rst = '1' then
        trig_valid <= '0';
      end if;
    end if;
  end process;

end architecture rtl;
