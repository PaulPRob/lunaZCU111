-------------------------------------------------------------------------------
-- luna_pkg : shared constants and types for the ZCU111 transient trigger design
--
-- Data format: every clk_1x (245.76 MHz) cycle each ADC channel delivers
-- LANES = 16 consecutive 16-bit two's complement samples (12-bit ADC code,
-- MSB justified).  Lane 0 is the oldest sample in the word.
-- Absolute sample index of lane L in cycle c is  c*16 + L.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package luna_pkg is

  constant NCH      : integer := 8;             -- ADC channels
  constant LANES    : integer := 16;            -- samples per clk_1x cycle
  constant SW       : integer := 16;            -- bits per sample
  constant WORD_W   : integer := LANES * SW;    -- 256
  constant RING_AW  : integer := 10;            -- 1024 words = 16384 samples/bank
  constant DIST_W   : integer := 8;             -- saturating sample-distance width
  constant CYC_W    : integer := 60;            -- cycle counter (sample index = 64 bit)

  constant DIST_MAX : unsigned(DIST_W-1 downto 0) := (others => '1');

  type word_arr_t  is array (0 to NCH-1)   of std_logic_vector(WORD_W-1 downto 0);
  type lanes_arr_t is array (0 to NCH-1)   of std_logic_vector(LANES-1 downto 0);
  type dist_lane_t is array (0 to LANES-1) of unsigned(DIST_W-1 downto 0);
  type dist_arr_t  is array (0 to NCH-1)   of dist_lane_t;
  type u16_arr_t   is array (0 to NCH-1)   of unsigned(15 downto 0);
  type u32_arr_t   is array (0 to NCH-1)   of unsigned(31 downto 0);

  -- trigger source codes (carried in the event header)
  constant SRC_COINC : std_logic_vector(1 downto 0) := "01";
  constant SRC_ANTI  : std_logic_vector(1 downto 0) := "10";
  constant SRC_SOFT  : std_logic_vector(1 downto 0) := "11";

  function popcount(v : std_logic_vector) return unsigned;
  function sat_add(a : unsigned(DIST_W-1 downto 0); b : natural) return unsigned;

end package luna_pkg;

package body luna_pkg is

  function popcount(v : std_logic_vector) return unsigned is
    variable n : unsigned(4 downto 0) := (others => '0');
  begin
    for i in v'range loop
      if v(i) = '1' then
        n := n + 1;
      end if;
    end loop;
    return n;
  end function;

  function sat_add(a : unsigned(DIST_W-1 downto 0); b : natural) return unsigned is
    variable s : unsigned(DIST_W downto 0);
  begin
    s := resize(a, DIST_W+1) + to_unsigned(b, DIST_W+1);
    if s(DIST_W) = '1' then
      return DIST_MAX;
    end if;
    return s(DIST_W-1 downto 0);
  end function;

end package body luna_pkg;
