-------------------------------------------------------------------------------
-- trigger_capture_top : 8-channel threshold trigger + multi-bank capture
--
-- Used as a Vivado IP-integrator module reference.
--   s00..s07_axis : RFDC ADC streams, 8 x 16-bit samples per clk_2x (491.52 MHz)
--   s_axi         : control/status registers (clk_1x, 245.76 MHz)
--   m_axis        : event readout stream to the AXI DMA (clk_1x)
--   irq           : level high while at least one captured event is waiting
--                   (and IRQ_EN is set)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.luna_pkg.all;

entity trigger_capture_top is
  generic (
    NB_LOG2 : integer := 2          -- 4 capture banks
  );
  port (
    clk_2x         : in  std_logic;
    clk_1x         : in  std_logic;
    aresetn        : in  std_logic;  -- clk_1x domain, active low

    s00_axis_tdata : in  std_logic_vector(127 downto 0);
    s00_axis_tvalid: in  std_logic;
    s00_axis_tready: out std_logic;
    s01_axis_tdata : in  std_logic_vector(127 downto 0);
    s01_axis_tvalid: in  std_logic;
    s01_axis_tready: out std_logic;
    s02_axis_tdata : in  std_logic_vector(127 downto 0);
    s02_axis_tvalid: in  std_logic;
    s02_axis_tready: out std_logic;
    s03_axis_tdata : in  std_logic_vector(127 downto 0);
    s03_axis_tvalid: in  std_logic;
    s03_axis_tready: out std_logic;
    s04_axis_tdata : in  std_logic_vector(127 downto 0);
    s04_axis_tvalid: in  std_logic;
    s04_axis_tready: out std_logic;
    s05_axis_tdata : in  std_logic_vector(127 downto 0);
    s05_axis_tvalid: in  std_logic;
    s05_axis_tready: out std_logic;
    s06_axis_tdata : in  std_logic_vector(127 downto 0);
    s06_axis_tvalid: in  std_logic;
    s06_axis_tready: out std_logic;
    s07_axis_tdata : in  std_logic_vector(127 downto 0);
    s07_axis_tvalid: in  std_logic;
    s07_axis_tready: out std_logic;

    s_axi_awaddr   : in  std_logic_vector(11 downto 0);
    s_axi_awprot   : in  std_logic_vector(2 downto 0);
    s_axi_awvalid  : in  std_logic;
    s_axi_awready  : out std_logic;
    s_axi_wdata    : in  std_logic_vector(31 downto 0);
    s_axi_wstrb    : in  std_logic_vector(3 downto 0);
    s_axi_wvalid   : in  std_logic;
    s_axi_wready   : out std_logic;
    s_axi_bresp    : out std_logic_vector(1 downto 0);
    s_axi_bvalid   : out std_logic;
    s_axi_bready   : in  std_logic;
    s_axi_araddr   : in  std_logic_vector(11 downto 0);
    s_axi_arprot   : in  std_logic_vector(2 downto 0);
    s_axi_arvalid  : in  std_logic;
    s_axi_arready  : out std_logic;
    s_axi_rdata    : out std_logic_vector(31 downto 0);
    s_axi_rresp    : out std_logic_vector(1 downto 0);
    s_axi_rvalid   : out std_logic;
    s_axi_rready   : in  std_logic;

    m_axis_tdata   : out std_logic_vector(127 downto 0);
    m_axis_tkeep   : out std_logic_vector(15 downto 0);
    m_axis_tvalid  : out std_logic;
    m_axis_tlast   : out std_logic;
    m_axis_tready  : in  std_logic;

    sysref_1x      : in  std_logic;   -- PL SYSREF sampled in clk_1x (status only)
    irq            : out std_logic
  );

end entity trigger_capture_top;

architecture rtl of trigger_capture_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO of clk_2x : signal is "xilinx.com:signal:clock:1.0 clk_2x CLK";
  attribute X_INTERFACE_PARAMETER of clk_2x : signal is
    "ASSOCIATED_BUSIF s00_axis:s01_axis:s02_axis:s03_axis:s04_axis:s05_axis:s06_axis:s07_axis";
  attribute X_INTERFACE_INFO of clk_1x : signal is "xilinx.com:signal:clock:1.0 clk_1x CLK";
  attribute X_INTERFACE_PARAMETER of clk_1x : signal is
    "ASSOCIATED_BUSIF s_axi:m_axis, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of irq : signal is "xilinx.com:signal:interrupt:1.0 irq INTERRUPT";
  attribute X_INTERFACE_PARAMETER of irq : signal is "SENSITIVITY LEVEL_HIGH";


  constant DET_LAT : integer := 3;   -- chan_detect latency

  signal rst       : std_logic := '1';
  signal words     : word_arr_t;          -- clk_1x, 16 samples/channel
  signal cyc       : unsigned(CYC_W-1 downto 0) := (others => '0');
  type cyc_pipe_t is array (1 to DET_LAT) of unsigned(CYC_W-1 downto 0);
  signal cyc_d     : cyc_pipe_t;

  signal hits      : lanes_arr_t;
  signal dists     : dist_arr_t;
  signal peaks     : u16_arr_t;
  signal hit_cnt   : u32_arr_t := (others => (others => '0'));

  signal cfg_arm, cfg_irq_en, cfg_mode : std_logic;
  signal cfg_n     : unsigned(3 downto 0);
  signal cfg_win   : unsigned(7 downto 0);
  signal cfg_mask  : std_logic_vector(NCH-1 downto 0);
  signal cfg_len_w : unsigned(10 downto 0);
  signal cfg_thr   : u16_arr_t;

  signal p_soft, p_tsr, p_flush, p_cclr, p_rds, p_rel : std_logic;
  signal p_peak_clr : std_logic_vector(NCH-1 downto 0);

  signal trig_valid : std_logic;
  signal trig_pos   : unsigned(63 downto 0);
  signal trig_mask  : std_logic_vector(NCH-1 downto 0);
  signal trig_src   : std_logic_vector(1 downto 0);

  signal st_nfull   : unsigned(NB_LOG2 downto 0);
  signal st_head    : unsigned(NB_LOG2-1 downto 0);
  signal st_capt, st_busy, st_pref, rd_done : std_logic;
  signal cnt_trig, cnt_lost : unsigned(31 downto 0);

  signal ts_now     : unsigned(63 downto 0);
  signal sysref_d   : std_logic := '0';
  signal sysref_cnt : unsigned(31 downto 0) := (others => '0');

  type in_arr_t is array (0 to NCH-1) of std_logic_vector(127 downto 0);
  signal ain : in_arr_t;
begin

  process (clk_1x)
  begin
    if rising_edge(clk_1x) then
      rst <= not aresetn;
    end if;
  end process;

  ts_now <= cyc & "0000";

  s00_axis_tready <= '1'; s01_axis_tready <= '1';
  s02_axis_tready <= '1'; s03_axis_tready <= '1';
  s04_axis_tready <= '1'; s05_axis_tready <= '1';
  s06_axis_tready <= '1'; s07_axis_tready <= '1';

  ain(0) <= s00_axis_tdata; ain(1) <= s01_axis_tdata;
  ain(2) <= s02_axis_tdata; ain(3) <= s03_axis_tdata;
  ain(4) <= s04_axis_tdata; ain(5) <= s05_axis_tdata;
  ain(6) <= s06_axis_tdata; ain(7) <= s07_axis_tdata;

  -----------------------------------------------------------------------------
  -- 491.52 -> 245.76 MHz
  -----------------------------------------------------------------------------
  g_gb : for ch in 0 to NCH-1 generate
    u_gb : entity work.adc_gearbox
      port map (clk_2x => clk_2x, clk_1x => clk_1x, din => ain(ch), dout => words(ch));
  end generate;

  -----------------------------------------------------------------------------
  -- cycle / sample counter : cyc is the cycle index of 'words'
  -----------------------------------------------------------------------------
  process (clk_1x)
  begin
    if rising_edge(clk_1x) then
      if rst = '1' or p_tsr = '1' then
        cyc <= (others => '0');
      else
        cyc <= cyc + 1;
      end if;
      cyc_d(1) <= cyc;
      for i in 2 to DET_LAT loop
        cyc_d(i) <= cyc_d(i-1);
      end loop;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- detectors
  -----------------------------------------------------------------------------
  g_det : for ch in 0 to NCH-1 generate
    u_det : entity work.chan_detect
      port map (
        clk      => clk_1x,
        rst      => rst,
        din      => words(ch),
        thresh   => cfg_thr(ch),
        hit      => hits(ch),
        dist     => dists(ch),
        peak     => peaks(ch),
        peak_clr => p_peak_clr(ch)
      );

    process (clk_1x)
    begin
      if rising_edge(clk_1x) then
        if rst = '1' or p_cclr = '1' then
          hit_cnt(ch) <= (others => '0');
        elsif hits(ch) /= x"0000" then
          hit_cnt(ch) <= hit_cnt(ch) + 1;
        end if;
      end if;
    end process;
  end generate;

  -----------------------------------------------------------------------------
  -- trigger
  -----------------------------------------------------------------------------
  u_trig : entity work.trig_logic
    port map (
      clk        => clk_1x,
      rst        => rst,
      mode_anti  => cfg_mode,
      n_req      => cfg_n,
      win        => cfg_win,
      ch_mask    => cfg_mask,
      arm        => cfg_arm,
      soft_trig  => p_soft,
      cyc_in     => cyc_d(DET_LAT),
      hit        => hits,
      dist       => dists,
      trig_valid => trig_valid,
      trig_pos   => trig_pos,
      trig_mask  => trig_mask,
      trig_src   => trig_src
    );

  -----------------------------------------------------------------------------
  -- capture banks + readout
  -----------------------------------------------------------------------------
  u_cap : entity work.capture_ctrl
    generic map (NB_LOG2 => NB_LOG2)
    port map (
      clk           => clk_1x,
      rst           => rst,
      din           => words,
      din_cyc       => cyc,
      trig_valid    => trig_valid,
      trig_pos      => trig_pos,
      trig_mask     => trig_mask,
      trig_src      => trig_src,
      cap_len_w     => cfg_len_w,
      cfg_win       => cfg_win,
      cfg_n         => cfg_n,
      cfg_mode      => cfg_mode,
      flush         => p_flush,
      rd_start      => p_rds,
      release       => p_rel,
      st_nfull      => st_nfull,
      st_head       => st_head,
      st_capturing  => st_capt,
      st_rd_busy    => st_busy,
      st_prefilled  => st_pref,
      rd_done       => rd_done,
      cnt_trig      => cnt_trig,
      cnt_lost      => cnt_lost,
      m_axis_tdata  => m_axis_tdata,
      m_axis_tkeep  => m_axis_tkeep,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tlast  => m_axis_tlast,
      m_axis_tready => m_axis_tready
    );

  -----------------------------------------------------------------------------
  -- registers
  -----------------------------------------------------------------------------
  u_regs : entity work.trig_regs_axil
    generic map (NB_LOG2 => NB_LOG2)
    port map (
      clk           => clk_1x,
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
      cfg_arm       => cfg_arm,
      cfg_irq_en    => cfg_irq_en,
      cfg_mode_anti => cfg_mode,
      cfg_n         => cfg_n,
      cfg_win       => cfg_win,
      cfg_mask      => cfg_mask,
      cfg_len_w     => cfg_len_w,
      cfg_thresh    => cfg_thr,
      p_soft_trig   => p_soft,
      p_ts_reset    => p_tsr,
      p_flush       => p_flush,
      p_cnt_clear   => p_cclr,
      p_rd_start    => p_rds,
      p_release     => p_rel,
      p_peak_clr    => p_peak_clr,
      st_nfull      => st_nfull,
      st_head       => st_head,
      st_capturing  => st_capt,
      st_rd_busy    => st_busy,
      st_prefilled  => st_pref,
      st_ts         => ts_now,
      st_trig_cnt   => cnt_trig,
      st_lost_cnt   => cnt_lost,
      st_hit_cnt    => hit_cnt,
      st_peak       => peaks,
      st_sysref_cnt => sysref_cnt
    );

  process (clk_1x)
  begin
    if rising_edge(clk_1x) then
      sysref_d <= sysref_1x;
      if rst = '1' then
        sysref_cnt <= (others => '0');
      elsif sysref_1x = '1' and sysref_d = '0' then
        sysref_cnt <= sysref_cnt + 1;
      end if;
      if st_nfull /= 0 and cfg_irq_en = '1' then
        irq <= '1';
      else
        irq <= '0';
      end if;
    end if;
  end process;

end architecture rtl;
