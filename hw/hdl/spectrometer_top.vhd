-------------------------------------------------------------------------------
-- spectrometer_top : integrating spectrometer on one of the 8 ADC channels
--
-- Used as a Vivado IP-integrator module reference.
--
--   din_1x (8 channels x 16 samples @ 245.76 MHz) -> input select (INPUT
--   register, pipelined 8:1 mux) -> gearbox_16_27 -> words of 27 samples,
--   16 every 27 clk_1x cycles -> async FIFO -> clk_spec (145.636 MHz = fs/27)
--   -> ospfb      : 32-branch real polyphase filter bank oversampled 32/27
--                   (512 taps); computes the coarse channel selected by
--                   SUBBAND (0..16): 122.88 MHz spacing, centred on
--                   k * 122.88 MHz, sampled at fs/27 = 145.636 MS/s complex,
--                   flat to +-58 MHz, aliases into +-61.44 MHz <= -72 dB
--   -> dfb4096x1c : 4096-channel filter bank (35.556 kHz channels, 145.636
--                   MHz span; the central 3456 channels are the subband's
--                   own +-61.44 MHz) with power and vector accumulation over
--                   ACC_LEN+1 spectra of 28.125 us
--   -> spectrum memory: 2 banks x 4096 x 64 bit (UltraRAM), read by the PS
--      through the AXI-Lite window; irq while a full bank is waiting
--
-- clk_1x and clk_spec come from the same MMCM (CLKOUT0 fractional divide
-- 6.75) but are treated as asynchronous: only the XPM FIFO and the XPM CDC
-- cells cross between them.  Their rates match exactly on average, so once
-- the FIFO is half full it is read every clk_spec cycle; an underflow (never
-- expected) is counted in STATUS and restarts the integration.
--
-- The CSIRO System Generator core dfb4096x1c_0 is an IP-catalog instance
-- created by hw/scripts/build.tcl from the local, untracked folder
-- refernces/PFB.
--
-- dfb4096x1c restarts its filter, FFT framing and accumulator on a rising
-- edge of its 'valid' input.  ENABLE, RESTART and writes to SUBBAND/ACC_LEN
-- hold 'valid' low for a few cycles, then raise it.  The accumulator is
-- re-synchronised only when the FFT output restarts, ~5.04 spectra later
-- (filter taps + FFT latency, measured in tb_spec); until then it keeps
-- emitting integrations on its old schedule, which may be empty, mixed or cut
-- short by the re-sync.  So after every (re)start the outputs that begin
-- within SETTLE_SPECTRA spectra are ignored, and an integration is stored
-- only if all 4096 channels were written.  The first integration stored
-- after a restart is flagged "first after restart".
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library xpm;
use xpm.vcomponents.all;
-- pragma translate_off
use std.textio.all;
use ieee.std_logic_textio.all;
-- pragma translate_on

entity spectrometer_top is
  generic (
    SIM_DUMP   : boolean := false;  -- simulation only: log memory writes
    SIM_NO_PFB : boolean := false   -- simulation only: replace the coarse
                                    -- filter bank by zeros
  );
  port (
    clk_1x        : in  std_logic;  -- 245.76 MHz
    clk_spec      : in  std_logic;  -- 145.636 MHz (fs/27), asynchronous to clk_1x
    aresetn       : in  std_logic;  -- clk_spec domain, active low

    din_1x        : in  std_logic_vector(2047 downto 0); -- 8 ADC channels, ch k at
                                                         -- [256k+255:256k], lane 0 oldest
    ts_1x         : in  std_logic_vector(63 downto 0);   -- trigger-core sample counter

    s_axi_awaddr  : in  std_logic_vector(16 downto 0);
    s_axi_awprot  : in  std_logic_vector(2 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    s_axi_araddr  : in  std_logic_vector(16 downto 0);
    s_axi_arprot  : in  std_logic_vector(2 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;

    irq           : out std_logic
  );
end entity spectrometer_top;

architecture rtl of spectrometer_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO of clk_1x : signal is "xilinx.com:signal:clock:1.0 clk_1x CLK";
  attribute X_INTERFACE_INFO of clk_spec : signal is "xilinx.com:signal:clock:1.0 clk_spec CLK";
  attribute X_INTERFACE_PARAMETER of clk_spec : signal is
    "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of irq : signal is "xilinx.com:signal:interrupt:1.0 irq INTERRUPT";
  attribute X_INTERFACE_PARAMETER of irq : signal is "SENSITIVITY LEVEL_HIGH";

  component dfb4096x1c_0
    port (
      acc_len       : in  std_logic_vector(31 downto 0);
      in_im         : in  std_logic_vector(17 downto 0);
      in_re         : in  std_logic_vector(17 downto 0);
      valid         : in  std_logic;
      clk           : in  std_logic;
      new_acc_out   : out std_logic;
      spec_data_out : out std_logic_vector(63 downto 0);
      vacc_ram_addr : out std_logic_vector(11 downto 0)
    );
  end component;

  constant RESTART_LEN : integer := 32;     -- clk_spec cycles 'valid' is held low
  constant NFINE       : integer := 4096;   -- fine channels = cycles per spectrum
  constant SETTLE_SPECTRA : integer := 6;   -- ignore outputs this long after a start
  constant SETTLE_CYC  : integer := SETTLE_SPECTRA * NFINE;

  constant GB_W        : integer := 27 * 12;  -- gearbox word: 27 samples
  constant FIFO_W      : integer := GB_W + 64;  -- + sample index
  constant FIFO_START  : integer := 16;     -- words in the FIFO before reading

  signal rst : std_logic := '1';

  -- input select (clk_1x)
  type w256_arr_t is array (natural range <>) of std_logic_vector(255 downto 0);
  signal input_1x : std_logic_vector(2 downto 0);
  signal sel_b    : unsigned(2 downto 0) := (others => '0');
  signal s0       : w256_arr_t(0 to 7);
  signal s1       : w256_arr_t(0 to 1);
  signal s2       : std_logic_vector(255 downto 0) := (others => '0');
  type u64_arr_t is array (natural range <>) of unsigned(63 downto 0);
  signal ts_d     : u64_arr_t(0 to 2) := (others => (others => '0'));

  -- gearbox and FIFO (clk_1x -> clk_spec)
  signal rst_1x   : std_logic;
  signal gb_word  : std_logic_vector(GB_W-1 downto 0);
  signal gb_ts    : unsigned(63 downto 0);
  signal gb_valid : std_logic;
  signal f_din    : std_logic_vector(FIFO_W-1 downto 0);
  signal f_dout   : std_logic_vector(FIFO_W-1 downto 0);
  signal f_wr_en, f_full, f_wr_busy : std_logic;
  signal f_rd_en, f_dvalid, f_rd_busy : std_logic;
  signal f_count  : std_logic_vector(5 downto 0);
  signal f_run    : std_logic := '0';
  signal os_in_valid : std_logic := '0';
  signal fifo_err : std_logic := '0';
  signal ts_s     : unsigned(63 downto 0) := (others => '0');

  -- coarse filter bank
  signal os_re, os_im : std_logic_vector(17 downto 0);
  signal os_valid : std_logic;

  -- fine filter bank
  signal dfb_valid : std_logic := '0';
  signal settle    : integer range 0 to SETTLE_CYC := SETTLE_CYC;
  signal start_ok  : std_logic;
  signal wcnt      : integer range 0 to NFINE := 0;
  signal dfb_new   : std_logic;
  signal dfb_data  : std_logic_vector(63 downto 0);
  signal dfb_addr  : std_logic_vector(11 downto 0);
  signal new_d     : std_logic := '0';

  -- control
  signal cfg_enable, cfg_irq_en : std_logic;
  signal cfg_subband : unsigned(4 downto 0);
  signal cfg_acc_len : unsigned(31 downto 0);
  signal cfg_input   : unsigned(2 downto 0);
  signal p_restart, p_release, p_cnt_clear : std_logic;
  signal enable_d    : std_logic := '0';
  signal restart_cnt : integer range 0 to RESTART_LEN := RESTART_LEN;
  signal first       : std_logic := '1';

  -- banks
  type u32_bank_t is array (0 to 1) of unsigned(31 downto 0);
  type u64_bank_t is array (0 to 1) of unsigned(63 downto 0);
  type flg_bank_t is array (0 to 1) of std_logic_vector(31 downto 0);
  signal nfull     : unsigned(1 downto 0) := "00";
  signal head      : std_logic := '0';
  signal tail      : std_logic := '0';
  signal writing   : std_logic := '0';
  signal sof, commit : std_logic;
  signal b_seq    : u32_bank_t := (others => (others => '0'));
  signal b_acc     : u32_bank_t := (others => (others => '0'));
  signal b_ts      : u64_bank_t := (others => (others => '0'));
  signal b_flags   : flg_bank_t := (others => (others => '0'));
  signal seq       : unsigned(31 downto 0) := (others => '0');
  signal cnt_lost  : unsigned(31 downto 0) := (others => '0');
  signal cnt_rst   : unsigned(31 downto 0) := (others => '0');

  signal mem_we    : std_logic;
  signal mem_waddr : unsigned(12 downto 0);
  signal mem_raddr : unsigned(12 downto 0);
  signal mem_dout  : std_logic_vector(63 downto 0);
  signal hb        : integer range 0 to 1;
  signal hd_seq, hd_acc : unsigned(31 downto 0);
  signal hd_flags  : std_logic_vector(31 downto 0);
  signal hd_ts     : unsigned(63 downto 0);

begin

  process (clk_spec)
  begin
    if rising_edge(clk_spec) then
      rst <= not aresetn;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- input select: the 8 channel words come from all four ADC tiles, i.e. from
  -- across the die, so the 8:1 mux is pipelined: one register per channel
  -- (s0, placed near its source), 4:1 (s1), 2:1 (s2).  INPUT comes from the
  -- clk_spec register block through a CDC synchroniser (static; a write
  -- restarts the integration, so the cycles of switching are discarded).
  -----------------------------------------------------------------------------
  u_input_cdc : xpm_cdc_array_single
    generic map (DEST_SYNC_FF => 3, INIT_SYNC_FF => 0, SIM_ASSERT_CHK => 0,
                 SRC_INPUT_REG => 1, WIDTH => 3)
    port map (src_clk => clk_spec, src_in => std_logic_vector(cfg_input),
              dest_clk => clk_1x, dest_out => input_1x);

  process (clk_1x)
  begin
    if rising_edge(clk_1x) then
      sel_b <= unsigned(input_1x);
      for k in 0 to 7 loop
        s0(k) <= din_1x(256*k+255 downto 256*k);
      end loop;
      s1(0) <= s0(to_integer(sel_b(1 downto 0)));
      s1(1) <= s0(4 + to_integer(sel_b(1 downto 0)));
      if sel_b(2) = '0' then
        s2 <= s1(0);
      else
        s2 <= s1(1);
      end if;
      -- sample index of s2 lane 0
      ts_d <= unsigned(ts_1x) & ts_d(0 to 1);
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- 16 samples @ 245.76 MHz -> 27 samples, 16 words per 27 cycles -> FIFO
  -----------------------------------------------------------------------------
  u_rst_cdc : xpm_cdc_sync_rst
    generic map (DEST_SYNC_FF => 4, INIT => 1, INIT_SYNC_FF => 0, SIM_ASSERT_CHK => 0)
    port map (src_rst => rst, dest_clk => clk_1x, dest_rst => rst_1x);

  u_gearbox : entity work.gearbox_16_27
    port map (
      clk        => clk_1x,
      rst        => rst_1x,
      din        => s2,
      ts_in      => ts_d(2),
      dout       => gb_word,
      ts_out     => gb_ts,
      dout_valid => gb_valid
    );

  f_din   <= std_logic_vector(gb_ts) & gb_word;
  f_wr_en <= gb_valid and not f_full and not f_wr_busy;

  u_fifo : xpm_fifo_async
    generic map (
      CASCADE_HEIGHT      => 0,
      CDC_SYNC_STAGES     => 2,
      DOUT_RESET_VALUE    => "0",
      ECC_MODE            => "no_ecc",
      FIFO_MEMORY_TYPE    => "distributed",
      FIFO_READ_LATENCY   => 0,
      FIFO_WRITE_DEPTH    => 32,
      FULL_RESET_VALUE    => 0,
      PROG_EMPTY_THRESH   => 10,
      PROG_FULL_THRESH    => 20,
      RD_DATA_COUNT_WIDTH => 6,
      READ_DATA_WIDTH     => FIFO_W,
      READ_MODE           => "fwft",
      RELATED_CLOCKS      => 0,
      SIM_ASSERT_CHK      => 0,
      USE_ADV_FEATURES    => "1400",     -- rd_data_count, data_valid
      WAKEUP_TIME         => 0,
      WRITE_DATA_WIDTH    => FIFO_W,
      WR_DATA_COUNT_WIDTH => 6
    )
    port map (
      sleep         => '0',
      rst           => rst_1x,
      wr_clk        => clk_1x,
      wr_en         => f_wr_en,
      din           => f_din,
      full          => f_full,
      prog_full     => open,
      wr_data_count => open,
      overflow      => open,
      wr_rst_busy   => f_wr_busy,
      almost_full   => open,
      wr_ack        => open,
      rd_clk        => clk_spec,
      rd_en         => f_rd_en,
      dout          => f_dout,
      empty         => open,
      prog_empty    => open,
      rd_data_count => f_count,
      underflow     => open,
      rd_rst_busy   => f_rd_busy,
      almost_empty  => open,
      data_valid    => f_dvalid,
      injectsbiterr => '0',
      injectdbiterr => '0',
      sbiterr       => open,
      dbiterr       => open
    );

  -- read side: wait until FIFO_START words are in, then read one word every
  -- clk_spec cycle.  Write and read rates are equal, so the level stays near
  -- FIFO_START; if the FIFO ever runs dry the filter bank input goes invalid
  -- for a cycle, which restarts the fine filter bank (sticky STATUS bit 11).
  f_rd_en <= f_run;

  process (clk_spec)
  begin
    if rising_edge(clk_spec) then
      os_in_valid <= '0';
      if f_rd_busy = '1' then
        f_run <= '0';
      elsif f_run = '0' then
        if unsigned(f_count) >= FIFO_START then
          f_run <= '1';
        end if;
      elsif f_dvalid = '0' then
        f_run    <= '0';
        fifo_err <= '1';
      else
        os_in_valid <= '1';
      end if;
      if f_run = '1' and f_dvalid = '1' then
        ts_s <= unsigned(f_dout(FIFO_W-1 downto GB_W));
      end if;
      if p_cnt_clear = '1' or rst = '1' then
        fifo_err <= '0';
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- coarse filter bank (one word per cycle, registered data)
  -----------------------------------------------------------------------------
  b_os : block
    signal os_word : std_logic_vector(GB_W-1 downto 0) := (others => '0');
  begin
    process (clk_spec)
    begin
      if rising_edge(clk_spec) then
        os_word <= f_dout(GB_W-1 downto 0);
      end if;
    end process;

    g_nopfb : if SIM_NO_PFB generate
      os_re    <= (others => '0');
      os_im    <= (others => '0');
      os_valid <= os_in_valid;
    end generate;

    g_pfb : if not SIM_NO_PFB generate
      u_ospfb : entity work.ospfb
        port map (
          clk        => clk_spec,
          subband    => cfg_subband,
          din        => os_word,
          din_valid  => os_in_valid,
          dout_re    => os_re,
          dout_im    => os_im,
          dout_valid => os_valid
        );
    end generate;
  end block;

  -----------------------------------------------------------------------------
  -- enable / restart: 'valid' low for RESTART_LEN cycles, then a rising edge
  -----------------------------------------------------------------------------
  process (clk_spec)
  begin
    if rising_edge(clk_spec) then
      enable_d <= cfg_enable;
      if rst = '1' then
        restart_cnt <= RESTART_LEN;
      elsif p_restart = '1' or (cfg_enable = '1' and enable_d = '0') then
        restart_cnt <= RESTART_LEN;
        cnt_rst     <= cnt_rst + 1;
      elsif restart_cnt /= 0 then
        restart_cnt <= restart_cnt - 1;
      end if;
      if p_cnt_clear = '1' then
        cnt_rst <= (others => '0');
      end if;

      if restart_cnt = 0 and cfg_enable = '1' then
        dfb_valid <= os_valid;
      else
        dfb_valid <= '0';
      end if;

      -- outputs of the fine filter bank are valid SETTLE_CYC after 'valid' rose
      if dfb_valid = '0' then
        settle <= SETTLE_CYC;
      elsif settle /= 0 then
        settle <= settle - 1;
      end if;
    end if;
  end process;

  u_dfb : dfb4096x1c_0
    port map (
      acc_len       => std_logic_vector(cfg_acc_len),
      in_im         => os_im,
      in_re         => os_re,
      valid         => dfb_valid,
      clk           => clk_spec,
      new_acc_out   => dfb_new,
      spec_data_out => dfb_data,
      vacc_ram_addr => dfb_addr
    );

  -----------------------------------------------------------------------------
  -- store each integration in the next free bank.  While new_acc_out is high
  -- the DFB streams one spectrum per 4096 cycles with vacc_ram_addr = channel
  -- 0..4095 (for ACC_LEN = 0 new_acc_out stays high and the spectra follow
  -- each other), so spectra are framed by the channel number: a spectrum is
  -- stored only if channels 0..4095 all arrived in order.
  -----------------------------------------------------------------------------
  sof    <= '1' when dfb_new = '1' and unsigned(dfb_addr) = 0 else '0';
  commit <= '1' when restart_cnt = 0 and writing = '1' and dfb_new = '1' and
                     unsigned(dfb_addr) = NFINE - 1 and wcnt = NFINE - 1
            else '0';

  process (clk_spec)
    variable n    : unsigned(1 downto 0);
    variable t    : integer range 0 to 1;
    variable rel  : boolean;
    variable flg  : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk_spec) then
      new_d <= dfb_new;
      n   := nfull;
      rel := p_release = '1' and nfull /= 0;
      t   := 0;
      if tail = '1' then
        t := 1;
      end if;
      flg := (others => '0');
      flg(0) := first;
      flg(12 downto 8) := std_logic_vector(cfg_subband);
      flg(18 downto 16) := std_logic_vector(cfg_input);

      if restart_cnt /= 0 then
        -- a restart discards the integration being written
        writing <= '0';
        first   <= '1';
      elsif sof = '1' then
        -- channel 0 of an output spectrum
        wcnt <= 1;
        if start_ok = '1' then
          writing <= '1';
        else
          writing <= '0';
          if cfg_enable = '1' and settle = 0 and dfb_valid = '1' and nfull = 2 then
            cnt_lost <= cnt_lost + 1;
          end if;
        end if;
      elsif commit = '1' then
        -- channel 4095 written: the integration is complete
        b_seq(t)   <= seq;
        b_acc(t)   <= cfg_acc_len;
        b_ts(t)    <= ts_s;
        b_flags(t) <= flg;
        seq     <= seq + 1;
        tail    <= not tail;
        n       := n + 1;
        first   <= '0';
        writing <= '0';
      elsif writing = '1' and dfb_new = '1' then
        if wcnt /= NFINE - 1 then
          wcnt <= wcnt + 1;
        end if;
      else
        -- stream cut short (accumulator re-synchronised) or not writing
        writing <= '0';
      end if;

      if rel then
        n    := n - 1;
        head <= not head;
      end if;
      nfull <= n;

      if p_cnt_clear = '1' then
        cnt_lost <= (others => '0');
      end if;
      if rst = '1' then
        writing <= '0';
        nfull   <= "00";
        head    <= '0';
        tail    <= '0';
        first   <= '1';
      end if;

      if nfull /= 0 and cfg_irq_en = '1' then
        irq <= '1';
      else
        irq <= '0';
      end if;
    end if;
  end process;

  -- channel 0 of a spectrum that will be stored
  start_ok  <= '1' when sof = '1' and restart_cnt = 0 and settle = 0 and
                        dfb_valid = '1' and cfg_enable = '1' and nfull /= 2
               else '0';
  -- 'writing' is registered, so channel 0 uses start_ok directly
  mem_we    <= '1' when dfb_new = '1' and restart_cnt = 0 and
                        (writing = '1' or start_ok = '1')
               else '0';
  mem_waddr <= tail & unsigned(dfb_addr);

  u_mem : entity work.capture_mem
    generic map (AW => 13, DW => 64)
    port map (
      clk   => clk_spec,
      we    => mem_we,
      waddr => mem_waddr,
      wdata => dfb_data,
      raddr => mem_raddr,
      dout  => mem_dout
    );

  -----------------------------------------------------------------------------
  -- registers
  -----------------------------------------------------------------------------
  hb <= 1 when head = '1' else 0;
  hd_seq   <= b_seq(hb);
  hd_flags <= b_flags(hb);
  hd_acc   <= b_acc(hb);
  hd_ts    <= b_ts(hb);

  u_regs : entity work.spec_regs_axil
    port map (
      clk           => clk_spec,
      rst           => rst,
      s_axi_awaddr  => s_axi_awaddr,
      s_axi_awvalid => s_axi_awvalid,
      s_axi_awready => s_axi_awready,
      s_axi_wdata   => s_axi_wdata,
      s_axi_wstrb   => s_axi_wstrb,
      s_axi_wvalid  => s_axi_wvalid,
      s_axi_wready  => s_axi_wready,
      s_axi_bresp   => s_axi_bresp,
      s_axi_bvalid  => s_axi_bvalid,
      s_axi_bready  => s_axi_bready,
      s_axi_araddr  => s_axi_araddr,
      s_axi_arvalid => s_axi_arvalid,
      s_axi_arready => s_axi_arready,
      s_axi_rdata   => s_axi_rdata,
      s_axi_rresp   => s_axi_rresp,
      s_axi_rvalid  => s_axi_rvalid,
      s_axi_rready  => s_axi_rready,
      cfg_enable    => cfg_enable,
      cfg_irq_en    => cfg_irq_en,
      cfg_subband   => cfg_subband,
      cfg_acc_len   => cfg_acc_len,
      cfg_input     => cfg_input,
      p_restart     => p_restart,
      p_release     => p_release,
      p_cnt_clear   => p_cnt_clear,
      st_nfull      => nfull,
      st_head       => head,
      st_running    => dfb_valid,
      st_writing    => writing,
      st_fifo_err   => fifo_err,
      st_spec_cnt   => seq,
      st_lost_cnt   => cnt_lost,
      st_restarts   => cnt_rst,
      hd_seq        => hd_seq,
      hd_flags      => hd_flags,
      hd_acc_len    => hd_acc,
      hd_ts         => hd_ts,
      mem_raddr     => mem_raddr,
      mem_dout      => mem_dout
    );

  -----------------------------------------------------------------------------
  -- simulation only: write every stored channel to spec_writes.txt
  --   "W <bank> <addr> <data hex>" and
  --   "C <seq> <first> <subband> <acc_len> <input>"
  -----------------------------------------------------------------------------
  -- pragma translate_off
  g_dump : if SIM_DUMP generate
    -- handshake transitions, with the clk_spec cycle number
    process (clk_spec)
      file f        : text open write_mode is "spec_events.txt";
      variable l    : line;
      variable cyc  : integer := 0;
      variable pv, dv, nv : std_logic := '0';
      variable seen_pfb, seen_fin : boolean := false;
      variable nz   : integer := 0;
      procedure ev(s : string; v : std_logic) is
      begin
        write(l, cyc); write(l, string'(" ")); write(l, s);
        write(l, string'(" ")); write(l, v);
        writeline(f, l);
      end procedure;
    begin
      if rising_edge(clk_spec) then
        cyc := cyc + 1;
        if os_valid /= pv then pv := os_valid; ev("pfb_valid_out", pv); end if;
        if dfb_valid /= dv then dv := dfb_valid; ev("dfb_valid", dv); end if;
        if dfb_new /= nv then
          nv := dfb_new;
          ev("new_acc_out", nv);
          if nv = '0' then
            write(l, cyc); write(l, string'(" nonzero_words ")); write(l, nz);
            writeline(f, l);
          end if;
          nz := 0;
        end if;
        if dfb_new = '1' and unsigned(dfb_data) /= 0 then
          nz := nz + 1;
        end if;
        if not seen_pfb and unsigned(os_re) /= 0 then
          seen_pfb := true; ev("pfb_out_nonzero", '1');
        end if;
        if not seen_fin and fifo_err = '1' then
          seen_fin := true; ev("fifo_underflow", '1');
        end if;
      end if;
    end process;

    process (clk_spec)
      file f     : text open write_mode is "spec_writes.txt";
      variable l : line;
    begin
      if rising_edge(clk_spec) then
        if mem_we = '1' then
          write(l, string'("W "));
          write(l, to_integer(mem_waddr(12 downto 12)));
          write(l, string'(" "));
          write(l, to_integer(unsigned(dfb_addr)));
          write(l, string'(" "));
          hwrite(l, dfb_data);
          writeline(f, l);
        end if;
        if commit = '1' then
          write(l, string'("C "));
          write(l, to_integer(seq));
          write(l, string'(" "));
          write(l, first);
          write(l, string'(" "));
          write(l, to_integer(cfg_subband));
          write(l, string'(" "));
          write(l, to_integer(cfg_acc_len));
          write(l, string'(" "));
          write(l, to_integer(cfg_input));
          writeline(f, l);
        end if;
      end if;
    end process;
  end generate;
  -- pragma translate_on

end architecture rtl;
