-------------------------------------------------------------------------------
-- tb_capture : full trigger_capture_top test (gearbox, regs, banks, readout)
--
-- ADC model: channel ch, TB sample index n  ->  ((n + 1000*ch) mod 4096) - 2048
-- (never exceeds the threshold) plus injected pulses of +0x6000.
-- The readout stream is written to cap_stream.txt ("<hex128> <tlast>") and
-- the expected event sequence to cap_log.txt; check_capture.py verifies:
-- header fields, centring of the trigger, sample continuity, cross-channel
-- alignment, pulse positions, bank order and the lost-trigger counter.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_capture is
end entity tb_capture;

architecture sim of tb_capture is
  signal clk_2x  : std_logic := '0';
  signal clk_1x  : std_logic := '0';
  signal aresetn : std_logic := '0';
  signal done    : boolean := false;

  type tdata_arr_t is array (0 to 7) of std_logic_vector(127 downto 0);
  signal tdata   : tdata_arr_t := (others => (others => '0'));
  signal nidx    : integer := 0;         -- TB sample index of next beat

  -- pulse injection request (TB sample index, channel mask)
  signal pulse_n    : integer := -1;
  signal pulse_mask : std_logic_vector(7 downto 0) := (others => '0');
  signal pulse2_n   : integer := -1;
  signal pulse2_mask: std_logic_vector(7 downto 0) := (others => '0');

  signal awaddr, araddr : std_logic_vector(11 downto 0) := (others => '0');
  signal awvalid, wvalid, bready, arvalid, rready : std_logic := '0';
  signal awready, wready, bvalid, arready, rvalid : std_logic;
  signal wdata, rdata : std_logic_vector(31 downto 0) := (others => '0');
  signal bresp, rresp : std_logic_vector(1 downto 0);

  signal m_tdata  : std_logic_vector(127 downto 0);
  signal m_tkeep  : std_logic_vector(15 downto 0);
  signal m_tvalid, m_tlast : std_logic;
  signal m_tready : std_logic := '0';
  signal irq      : std_logic;
  signal lfsr     : std_logic_vector(15 downto 0) := x"ACE1";
  signal beats    : integer := 0;
  signal lasts    : integer := 0;
begin

  clk_2x <= not clk_2x after 1 ns when not done else '0';
  clk_1x <= not clk_1x after 2 ns when not done else '0';

  -----------------------------------------------------------------------------
  -- ADC stream (8 samples per clk_2x)
  -----------------------------------------------------------------------------
  process (clk_2x)
    variable v : integer;
    variable n : integer;
  begin
    if rising_edge(clk_2x) then
      for ch in 0 to 7 loop
        for i in 0 to 7 loop
          n := nidx + i;
          v := ((n + 1000*ch) mod 4096) - 2048;
          if (n = pulse_n and pulse_mask(ch) = '1') or
             (n = pulse2_n and pulse2_mask(ch) = '1') then
            v := 16#6000#;
          end if;
          tdata(ch)(16*i+15 downto 16*i) <= std_logic_vector(to_signed(v, 16));
        end loop;
      end loop;
      nidx <= nidx + 8;
    end if;
  end process;

  dut : entity work.trigger_capture_top
    port map (
      clk_2x => clk_2x, clk_1x => clk_1x, aresetn => aresetn,
      s00_axis_tdata => tdata(0), s00_axis_tvalid => '1', s00_axis_tready => open,
      s01_axis_tdata => tdata(1), s01_axis_tvalid => '1', s01_axis_tready => open,
      s02_axis_tdata => tdata(2), s02_axis_tvalid => '1', s02_axis_tready => open,
      s03_axis_tdata => tdata(3), s03_axis_tvalid => '1', s03_axis_tready => open,
      s04_axis_tdata => tdata(4), s04_axis_tvalid => '1', s04_axis_tready => open,
      s05_axis_tdata => tdata(5), s05_axis_tvalid => '1', s05_axis_tready => open,
      s06_axis_tdata => tdata(6), s06_axis_tvalid => '1', s06_axis_tready => open,
      s07_axis_tdata => tdata(7), s07_axis_tvalid => '1', s07_axis_tready => open,
      s_axi_awaddr => awaddr, s_axi_awprot => "000", s_axi_awvalid => awvalid,
      s_axi_awready => awready, s_axi_wdata => wdata, s_axi_wstrb => "1111",
      s_axi_wvalid => wvalid, s_axi_wready => wready, s_axi_bresp => bresp,
      s_axi_bvalid => bvalid, s_axi_bready => bready, s_axi_araddr => araddr,
      s_axi_arprot => "000", s_axi_arvalid => arvalid, s_axi_arready => arready,
      s_axi_rdata => rdata, s_axi_rresp => rresp, s_axi_rvalid => rvalid,
      s_axi_rready => rready,
      m_axis_tdata => m_tdata, m_axis_tkeep => m_tkeep, m_axis_tvalid => m_tvalid,
      m_axis_tlast => m_tlast, m_axis_tready => m_tready,
      sysref_1x => '0', irq => irq
    );

  -----------------------------------------------------------------------------
  -- AXIS sink with pseudo random back-pressure
  -----------------------------------------------------------------------------
  process (clk_1x)
    file fo    : text open write_mode is "cap_stream.txt";
    variable l : line;
  begin
    if rising_edge(clk_1x) then
      lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      m_tready <= lfsr(0) or lfsr(3);   -- ~75 % ready
      if m_tvalid = '1' and m_tready = '1' then
        hwrite(l, m_tdata);
        if m_tlast = '1' then
          write(l, string'(" 1"));
          lasts <= lasts + 1;
        else
          write(l, string'(" 0"));
        end if;
        writeline(fo, l);
        beats <= beats + 1;
      end if;
    end if;
  end process;

  watchdog : process
  begin
    wait for 2 ms;
    assert done report "TB: TIMEOUT waiting in test sequence" severity failure;
    wait;
  end process;

  -----------------------------------------------------------------------------
  -- test sequence
  -----------------------------------------------------------------------------
  seq : process
    file flog  : text open write_mode is "cap_log.txt";
    variable l : line;
    variable d : std_logic_vector(31 downto 0);

    procedure axi_write(a : integer; v : std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk_1x);
      awaddr <= std_logic_vector(to_unsigned(a, 12)); awvalid <= '1';
      wdata <= v; wvalid <= '1'; bready <= '1';
      loop
        wait until rising_edge(clk_1x);
        if awready = '1' then awvalid <= '0'; end if;
        if wready = '1' then wvalid <= '0'; end if;
        exit when bvalid = '1';
      end loop;
      bready <= '0';
    end procedure;

    procedure axi_read(a : integer; v : out std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk_1x);
      araddr <= std_logic_vector(to_unsigned(a, 12)); arvalid <= '1'; rready <= '1';
      loop
        wait until rising_edge(clk_1x);
        if arready = '1' then arvalid <= '0'; end if;
        exit when rvalid = '1';
      end loop;
      v := rdata;
      rready <= '0';
    end procedure;

    procedure wait_cycles(n : integer) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk_1x);
      end loop;
    end procedure;

    procedure inject(n_off : integer; m : std_logic_vector(7 downto 0);
                     n2_off : integer; m2 : std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(clk_2x);
      pulse_n     <= nidx + 400 + n_off;
      pulse_mask  <= m;
      pulse2_n    <= nidx + 400 + n2_off;
      pulse2_mask <= m2;
      wait_cycles(200);
    end procedure;

    procedure readout_one is
      variable target : integer;
    begin
      target := lasts + 1;
      axi_write(16#024#, x"00000001");
      while lasts < target loop
        wait until rising_edge(clk_1x);
      end loop;
      wait_cycles(4);
      axi_write(16#028#, x"00000001");
      wait_cycles(4);
    end procedure;

    procedure log(s : string) is
    begin
      write(l, s);
      writeline(flog, l);
    end procedure;

  begin
    wait_cycles(20);
    aresetn <= '1';
    wait_cycles(10);

    axi_read(16#000#, d);
    assert d = x"4C554E41" report "TB: bad ID register" severity failure;

    -- ---------------- event 1 : coincidence ch1 + ch5, L = 4096 -------------
    axi_write(16#020#, std_logic_vector(to_unsigned(4096, 32)));
    axi_write(16#010#, x"00000000");                  -- coincidence
    axi_write(16#014#, x"00000002");                  -- N = 2
    axi_write(16#018#, x"00000040");                  -- W = 64
    axi_write(16#01C#, x"000000FF");
    axi_write(16#008#, x"00000109");                  -- ARM, IRQ_EN, FLUSH
    wait_cycles(400);                                  -- pre-fill
    inject(0, x"02", 20, x"20");
    axi_read(16#00C#, d);
    report "TB: status after event 1 inject = " & integer'image(to_integer(unsigned(d)));
    axi_read(16#038#, d);
    report "TB: trig count = " & integer'image(to_integer(unsigned(d)));
    axi_read(16#03C#, d);
    report "TB: lost count = " & integer'image(to_integer(unsigned(d)));
    if irq /= '1' then wait until irq = '1'; end if;
    log("EVT 4096 1 34 0");                            -- L src mask lost
    readout_one;

    -- ---------------- event 2 : anti-coincidence ch3, L = 16384 -------------
    axi_write(16#020#, std_logic_vector(to_unsigned(16384, 32)));
    axi_write(16#010#, x"00000001");
    wait_cycles(1200);
    inject(0, x"08", -1000000, x"00");
    if irq /= '1' then wait until irq = '1'; end if;
    log("EVT 16384 2 8 0");
    readout_one;

    -- anti-coincidence must NOT fire for two channels 50 samples apart
    inject(0, x"08", 50, x"10");
    wait_cycles(300);
    assert irq = '0' report "TB: anti-coincidence fired on 2 channels" severity failure;

    -- ---------------- events 3..7 : fill all banks, one lost -----------------
    axi_write(16#020#, std_logic_vector(to_unsigned(4096, 32)));
    axi_write(16#010#, x"00000000");
    axi_write(16#014#, x"00000003");                  -- N = 3
    for e in 0 to 4 loop
      wait_cycles(400);
      inject(0, x"01", 30, x"C0");                    -- ch0 then ch6+ch7
    end loop;
    wait_cycles(400);
    axi_read(16#03C#, d);
    assert unsigned(d) = 1 report "TB: expected exactly one lost trigger" severity failure;
    axi_read(16#00C#, d);
    assert unsigned(d(3 downto 0)) = 4 report "TB: expected 4 full banks" severity failure;
    for e in 0 to 3 loop
      log("EVT 4096 1 193 0");
      readout_one;
    end loop;

    -- ---------------- soft trigger --------------------------------------------
    wait_cycles(400);
    axi_write(16#008#, x"00000103");                  -- ARM, IRQ_EN, SOFT
    if irq /= '1' then wait until irq = '1'; end if;
    log("EVT 4096 3 0 1");
    readout_one;

    axi_read(16#038#, d);
    log("TRIGCOUNT " & integer'image(to_integer(unsigned(d))));
    wait_cycles(50);
    report "TB: sequence complete, beats=" & integer'image(beats);
    done <= true;
    wait;
  end process;

end architecture sim;
