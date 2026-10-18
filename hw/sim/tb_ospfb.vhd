-------------------------------------------------------------------------------
-- tb_ospfb : ospfb (32/27 oversampled coarse filter bank) against the
--            bit-exact model hw/sim/ospfb_model.py
--
-- ospfb_stim.txt : one word per clk cycle, "valid c0 .. c26" (c0 oldest)
-- ospfb_out.txt  : "cycle re im" for every cycle with dout_valid
-- The checker finds the latency and the rotation phase offset itself.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

use work.ospfb_pkg.all;

entity tb_ospfb is
  generic (K : integer := 12);
end entity tb_ospfb;

architecture sim of tb_ospfb is
  signal clk       : std_logic := '0';
  signal din       : std_logic_vector(OS_D*12-1 downto 0) := (others => '0');
  signal din_valid : std_logic := '0';
  signal dre, dim  : std_logic_vector(17 downto 0);
  signal dvalid    : std_logic;
  signal cyc       : integer := 0;
  signal done      : boolean := false;
begin

  clk <= not clk after 3429 ps when not done;

  dut : entity work.ospfb
    port map (
      clk        => clk,
      subband    => to_unsigned(K, 5),
      din        => din,
      din_valid  => din_valid,
      dout_re    => dre,
      dout_im    => dim,
      dout_valid => dvalid
    );

  -- word i of the file is registered by the DUT at the edge ending cycle i
  stim : process
    file f     : text open read_mode is "ospfb_stim.txt";
    variable l : line;
    variable v : integer;
  begin
    while not endfile(f) loop
      readline(f, l);
      read(l, v);
      if v = 1 then din_valid <= '1'; else din_valid <= '0'; end if;
      for j in 0 to OS_D-1 loop
        read(l, v);
        din(12*j+11 downto 12*j) <= std_logic_vector(to_signed(v, 12));
      end loop;
      wait until rising_edge(clk);
    end loop;
    din_valid <= '0';
    for i in 1 to 64 loop
      wait until rising_edge(clk);
    end loop;
    done <= true;
    report "TB ospfb DONE (K=" & integer'image(K) & ")";
    finish;
  end process;

  dump : process (clk)
    file f     : text open write_mode is "ospfb_out.txt";
    variable l : line;
  begin
    if rising_edge(clk) then
      cyc <= cyc + 1;
      if dvalid = '1' then
        write(l, cyc);
        write(l, string'(" "));
        write(l, to_integer(signed(dre)));
        write(l, string'(" "));
        write(l, to_integer(signed(dim)));
        writeline(f, l);
      end if;
    end if;
  end process;

end architecture sim;
