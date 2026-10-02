-------------------------------------------------------------------------------
-- tb_spec : spectrometer_top with the real CSIRO PFB/DFB cores
--
-- ADC channel 0 carries two real tones (sample rate fs, fine channel
-- df = fs/32/4096 = 30 kHz at fs = 3932.16 MS/s):
--   A: subband 12 centre + 25 df   -> expect fine channel 25 of subband 12
--   B: subband 12 centre - 100 df  -> expect fine channel 4096-100 = 3996
-- spec_writes.txt / spec_events.txt are checked by check_spec.py.
--
-- TEST_MODE 0 (data): ACC_LEN = 1 (2 spectra), SUBBAND 12, ENABLE; two
--   integrations are read back over AXI-Lite (the first is flagged "first
--   after restart").
-- TEST_MODE 1 (restart, run with NO_PFB = true for speed): ACC_LEN = 7, then
--   ~1.5 spectra after the accumulator has re-synchronised, ACC_LEN = 0.  The
--   restart must re-synchronise the accumulator again (otherwise its counter
--   is already past the new length and no integration would come for days),
--   so a 1-spectrum integration must arrive promptly, flagged "first", then
--   another one not flagged.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;

entity tb_spec is
  generic (
    TEST_MODE : integer := 0;      -- 0 data, 1 restart
    NO_PFB    : boolean := false
  );
end entity tb_spec;

architecture sim of tb_spec is

  constant T1   : time := 4070 ps;           -- clk_1x (245.76 MHz nominal)
  constant NFFT : integer := 4096;
  constant NTOT : integer := 32 * NFFT;      -- fine channels across 0..fs
  constant PA   : integer := 12 * NFFT + 25;
  constant PB   : integer := 12 * NFFT - 100;
  constant AMPA : real := 600.0;              -- 12-bit ADC codes
  constant AMPB : real := 150.0;

  signal clk_1x, clk_spec : std_logic := '0';
  signal aresetn : std_logic := '0';
  signal din     : std_logic_vector(255 downto 0) := (others => '0');
  signal ts      : unsigned(63 downto 0) := (others => '0');

  signal awaddr, araddr : std_logic_vector(16 downto 0) := (others => '0');
  signal awvalid, wvalid, bready, arvalid, rready : std_logic := '0';
  signal awready, wready, bvalid, arready, rvalid : std_logic;
  signal wdata, rdata : std_logic_vector(31 downto 0) := (others => '0');
  signal bresp, rresp : std_logic_vector(1 downto 0);
  signal irq : std_logic;

  signal cyc : integer := 0;                  -- clk_spec cycle counter

begin

  -- phase-aligned 2:1 clocks (both edges scheduled by 'wait', same delta)
  process
  begin
    clk_1x <= '0';
    wait for T1 / 2;
    loop
      clk_1x <= '1';
      wait for T1 / 2;
      clk_1x <= '0';
      wait for T1 / 2;
    end loop;
  end process;

  process
  begin
    clk_spec <= '0';
    wait for T1 / 2;
    loop
      clk_spec <= '1';
      wait for T1;
      clk_spec <= '0';
      wait for T1;
    end loop;
  end process;

  process (clk_spec)
  begin
    if rising_edge(clk_spec) then
      cyc <= cyc + 1;
    end if;
  end process;

  -- ADC: 16 samples per clk_1x, lane 0 oldest, 12-bit code in bits 15..4
  process (clk_1x)
    variable pha : integer := 0;               -- phase of tone A, in 1/NTOT turns
    variable phb : integer := 0;
    variable x   : real;
    variable c   : integer;
  begin
    if rising_edge(clk_1x) then
      for l in 0 to 15 loop
        x := AMPA * cos(MATH_2_PI * real(pha) / real(NTOT)) +
             AMPB * cos(MATH_2_PI * real(phb) / real(NTOT));
        pha := (pha + PA) mod NTOT;
        phb := (phb + PB) mod NTOT;
        c := integer(round(x));
        din(16*l+15 downto 16*l) <= std_logic_vector(to_signed(c * 16, 16));
      end loop;
      ts <= ts + 16;
    end if;
  end process;

  dut : entity work.spectrometer_top
    generic map (SIM_DUMP => true, SIM_NO_PFB => NO_PFB)
    port map (
      clk_1x        => clk_1x,
      clk_spec      => clk_spec,
      aresetn       => aresetn,
      din_1x        => din,
      ts_1x         => std_logic_vector(ts),
      s_axi_awaddr  => awaddr,
      s_axi_awprot  => "000",
      s_axi_awvalid => awvalid,
      s_axi_awready => awready,
      s_axi_wdata   => wdata,
      s_axi_wstrb   => "1111",
      s_axi_wvalid  => wvalid,
      s_axi_wready  => wready,
      s_axi_bresp   => bresp,
      s_axi_bvalid  => bvalid,
      s_axi_bready  => bready,
      s_axi_araddr  => araddr,
      s_axi_arprot  => "000",
      s_axi_arvalid => arvalid,
      s_axi_arready => arready,
      s_axi_rdata   => rdata,
      s_axi_rresp   => rresp,
      s_axi_rvalid  => rvalid,
      s_axi_rready  => rready,
      irq           => irq
    );

  stim : process
    variable d, lo, hi : std_logic_vector(31 downto 0);
    variable t0 : integer;

    procedure wr(a : integer; v : integer) is
    begin
      wait until rising_edge(clk_spec);
      awaddr  <= std_logic_vector(to_unsigned(a, 17));
      wdata   <= std_logic_vector(to_unsigned(v, 32));
      awvalid <= '1';
      wvalid  <= '1';
      bready  <= '1';
      loop
        wait until rising_edge(clk_spec);
        if awready = '1' then awvalid <= '0'; end if;
        if wready = '1' then wvalid <= '0'; end if;
        exit when bvalid = '1';
      end loop;
      bready <= '0';
      awvalid <= '0';
      wvalid <= '0';
    end procedure;

    procedure rd(a : integer; v : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk_spec);
      araddr  <= std_logic_vector(to_unsigned(a, 17));
      arvalid <= '1';
      rready  <= '1';
      loop
        wait until rising_edge(clk_spec);
        if arready = '1' then arvalid <= '0'; end if;
        exit when rvalid = '1';
      end loop;
      v := rdata;
      rready  <= '0';
      arvalid <= '0';
    end procedure;

    procedure wait_irq(timeout : integer; what : string) is
    begin
      t0 := cyc;
      while irq = '0' loop
        wait until rising_edge(clk_spec);
        if cyc - t0 > timeout then
          report "TB FAIL: no integration within " & integer'image(timeout) &
                 " cycles (" & what & ")" severity failure;
        end if;
      end loop;
      report "TB " & what & ": integration after " & integer'image(cyc - t0) & " cycles";
    end procedure;

    procedure show_head(b : integer) is
      variable s, f, a : std_logic_vector(31 downto 0);
    begin
      rd(16#030#, s); rd(16#034#, f); rd(16#038#, a);
      report "TB head seq=" & integer'image(to_integer(unsigned(s))) &
             " first=" & std_logic'image(f(0)) &
             " subband=" & integer'image(to_integer(unsigned(f(12 downto 8)))) &
             " acc_len=" & integer'image(to_integer(unsigned(a)));
    end procedure;

    procedure release_all is
      variable st : std_logic_vector(31 downto 0);
    begin
      loop
        rd(16#00C#, st);
        exit when st(1 downto 0) = "00";
        wr(16#018#, 1);
      end loop;
    end procedure;

    variable st : std_logic_vector(31 downto 0);
    variable bank : integer;
  begin
    aresetn <= '0';
    for i in 1 to 20 loop
      wait until rising_edge(clk_spec);
    end loop;
    aresetn <= '1';
    for i in 1 to 5 loop
      wait until rising_edge(clk_spec);
    end loop;

    rd(16#000#, d);
    assert d = x"4C535043" report "TB FAIL: bad ID" severity failure;
    rd(16#004#, d);
    report "TB version " & integer'image(to_integer(unsigned(d)));

    wr(16#010#, 12);
    if TEST_MODE = 0 then
      -- data: two integrations of 2 spectra
      wr(16#014#, 1);
      wr(16#008#, 16#101#);
      for i in 1 to 2 loop
        wait_irq(80000, "data");
        rd(16#00C#, st);
        bank := 0;
        if st(4) = '1' then bank := 1; end if;
        show_head(bank);
        rd(16#10000# + bank * 16#8000# + 8 * 25, lo);
        rd(16#10000# + bank * 16#8000# + 8 * 25 + 4, hi);
        report "TB AXI bank " & integer'image(bank) & " bin 25 = 0x" & to_hstring(hi) & to_hstring(lo);
        rd(16#10000# + bank * 16#8000# + 8 * 3996, lo);
        rd(16#10000# + bank * 16#8000# + 8 * 3996 + 4, hi);
        report "TB AXI bank " & integer'image(bank) & " bin 3996 = 0x" & to_hstring(hi) & to_hstring(lo);
        release_all;
      end loop;
    else
      -- restart: 8-spectrum integration, shortened to 1 spectrum part way
      -- through (the accumulator re-synchronises ~5.04 spectra after the
      -- start; 30000 cycles is ~2.3 spectra after that)
      wr(16#014#, 7);
      wr(16#008#, 16#101#);
      for i in 1 to 30000 loop
        wait until rising_edge(clk_spec);
      end loop;
      rd(16#00C#, st);
      assert st(1 downto 0) = "00"
        report "TB FAIL: integration stored before the 8-spectrum length" severity failure;
      wr(16#014#, 0);
      wait_irq(45000, "restart after shortening");
      show_head(0);
      release_all;
      wait_irq(10000, "restart next");
      show_head(0);
      release_all;
    end if;

    rd(16#01C#, d);
    report "TB spec_count=" & integer'image(to_integer(unsigned(d)));
    rd(16#020#, d);
    report "TB lost_count=" & integer'image(to_integer(unsigned(d)));
    rd(16#024#, d);
    report "TB restarts=" & integer'image(to_integer(unsigned(d)));
    report "TB DONE";
    finish;
  end process;

end architecture sim;
