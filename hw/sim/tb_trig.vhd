-------------------------------------------------------------------------------
-- tb_trig : chan_detect x 8 + trig_logic against the Python golden model
--
-- stim file (text):
--   line 1   : mode n_req win mask(dec)
--   line 2.. : one line per clk_1x cycle, 8 decimal lane-hit masks (16 bit)
-- For every set lane bit the TB drives a sample of +/-0x6000 (sign alternates),
-- otherwise small noise; threshold = 0x4000.
-- out file : one line per trigger "pos mask src"
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.luna_pkg.all;

entity tb_trig is
  generic (
    STIM : string := "trig_stim.txt";
    OUTF : string := "trig_out.txt"
  );
end entity tb_trig;

architecture sim of tb_trig is
  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal words : word_arr_t := (others => (others => '0'));
  signal cyc   : unsigned(CYC_W-1 downto 0) := (others => '0');
  type cyc_pipe_t is array (1 to 3) of unsigned(CYC_W-1 downto 0);
  signal cyc_d : cyc_pipe_t := (others => (others => '0'));
  signal hits  : lanes_arr_t;
  signal dists : dist_arr_t;
  signal peaks : u16_arr_t;
  signal thr   : u16_arr_t := (others => to_unsigned(16#4000#, 16));

  signal mode  : std_logic := '0';
  signal n_req : unsigned(3 downto 0) := to_unsigned(2, 4);
  signal win   : unsigned(7 downto 0) := to_unsigned(64, 8);
  signal mask  : std_logic_vector(NCH-1 downto 0) := (others => '1');

  signal tv    : std_logic;
  signal tpos  : unsigned(63 downto 0);
  signal tmask : std_logic_vector(NCH-1 downto 0);
  signal tsrc  : std_logic_vector(1 downto 0);
  signal done  : boolean := false;
begin

  clk <= not clk after 2 ns when not done else '0';

  g_det : for ch in 0 to NCH-1 generate
    u_det : entity work.chan_detect
      port map (clk => clk, rst => rst, din => words(ch), thresh => thr(ch),
                hit => hits(ch), dist => dists(ch), peak => peaks(ch), peak_clr => '0');
  end generate;

  u_trig : entity work.trig_logic
    port map (clk => clk, rst => rst, mode_anti => mode, n_req => n_req, win => win,
              ch_mask => mask, arm => '1', soft_trig => '0', cyc_in => cyc_d(3),
              hit => hits, dist => dists, trig_valid => tv, trig_pos => tpos,
              trig_mask => tmask, trig_src => tsrc);

  process (clk)
  begin
    if rising_edge(clk) then
      cyc_d(1) <= cyc;
      cyc_d(2) <= cyc_d(1);
      cyc_d(3) <= cyc_d(2);
    end if;
  end process;

  stim_p : process
    file f     : text open read_mode is STIM;
    variable l : line;
    variable v : integer;
    variable m : integer;
    variable noise : integer := 12345;
    variable sgn   : boolean := false;
    variable s     : integer;
  begin
    readline(f, l);
    read(l, v); if v = 1 then mode <= '1'; else mode <= '0'; end if;
    read(l, v); n_req <= to_unsigned(v, 4);
    read(l, v); win <= to_unsigned(v, 8);
    read(l, v); mask <= std_logic_vector(to_unsigned(v, NCH));
    for i in 0 to 9 loop
      wait until rising_edge(clk);
    end loop;
    rst <= '0';
    while not endfile(f) loop
      readline(f, l);
      for ch in 0 to NCH-1 loop
        read(l, m);
        for k in 0 to LANES-1 loop
          noise := (noise * 75 + 74) mod 65537;
          if (m / 2**k) mod 2 = 1 then
            sgn := not sgn;
            if sgn then s := 16#6000#; else s := -16#6000#; end if;
          else
            s := (noise mod 4096) - 2048;
          end if;
          words(ch)(SW*k+SW-1 downto SW*k) <= std_logic_vector(to_signed(s, SW));
        end loop;
      end loop;
      wait until rising_edge(clk);
      cyc <= cyc + 1;
    end loop;
    for ch in 0 to NCH-1 loop
      words(ch) <= (others => '0');
    end loop;
    for i in 0 to 60 loop
      wait until rising_edge(clk);
    end loop;
    done <= true;
    wait;
  end process;

  mon_p : process (clk)
    file fo    : text open write_mode is OUTF;
    variable l : line;
  begin
    if rising_edge(clk) then
      if tv = '1' then
        -- positions fit in 31 bits for the simulation
        write(l, to_integer(tpos(30 downto 0)));
        write(l, string'(" "));
        write(l, to_integer(unsigned(tmask)));
        write(l, string'(" "));
        write(l, to_integer(unsigned(tsrc)));
        writeline(fo, l);
      end if;
    end if;
  end process;

end architecture sim;
