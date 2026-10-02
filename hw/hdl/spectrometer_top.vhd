-------------------------------------------------------------------------------
-- spectrometer_top : integrating spectrometer on ADC channel 0
--
-- Used as a Vivado IP-integrator module reference.
--
--   din_1x (16 samples @ 245.76 MHz) -> 2:1 gearbox -> 32 samples @ 122.88 MHz
--   -> pfb32x16t  : 32-input real polyphase filter bank, 17 coarse channels
--                   (0 and 16 real), each 122.88 MHz wide, centred on
--                   k * 122.88 MHz, sampled at 122.88 MS/s complex
--   -> subband mux (SUBBAND register, 0..16) -> rnd_23_18 (re, im)
--   -> dfb4096x1c : 4096-channel filter bank (30 kHz channels) with power
--                   and vector accumulation over ACC_LEN+1 spectra
--   -> spectrum memory: 2 banks x 4096 x 64 bit (UltraRAM), read by the PS
--      through the AXI-Lite window; irq while a full bank is waiting
--
-- The CSIRO System Generator cores (pfb32x16t_0, rnd_23_18_0, dfb4096x1c_0)
-- are IP-catalog instances created by hw/scripts/build.tcl from the local,
-- untracked folder refernces/PFB.
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
-- pragma translate_off
use std.textio.all;
use ieee.std_logic_textio.all;
-- pragma translate_on

entity spectrometer_top is
  generic (
    SIM_DUMP   : boolean := false;  -- simulation only: log memory writes
    SIM_NO_PFB : boolean := false   -- simulation only: replace the (slow)
                                    -- PFB model by zeros
  );
  port (
    clk_1x        : in  std_logic;  -- 245.76 MHz
    clk_spec      : in  std_logic;  -- 122.88 MHz, same MMCM, phase aligned
    aresetn       : in  std_logic;  -- clk_spec domain, active low

    din_1x        : in  std_logic_vector(255 downto 0);  -- ADC ch 0, lane 0 oldest
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

  component pfb32x16t_0
    port (
      in0  : in std_logic_vector(11 downto 0); in1  : in std_logic_vector(11 downto 0);
      in2  : in std_logic_vector(11 downto 0); in3  : in std_logic_vector(11 downto 0);
      in4  : in std_logic_vector(11 downto 0); in5  : in std_logic_vector(11 downto 0);
      in6  : in std_logic_vector(11 downto 0); in7  : in std_logic_vector(11 downto 0);
      in8  : in std_logic_vector(11 downto 0); in9  : in std_logic_vector(11 downto 0);
      in10 : in std_logic_vector(11 downto 0); in11 : in std_logic_vector(11 downto 0);
      in12 : in std_logic_vector(11 downto 0); in13 : in std_logic_vector(11 downto 0);
      in14 : in std_logic_vector(11 downto 0); in15 : in std_logic_vector(11 downto 0);
      in16 : in std_logic_vector(11 downto 0); in17 : in std_logic_vector(11 downto 0);
      in18 : in std_logic_vector(11 downto 0); in19 : in std_logic_vector(11 downto 0);
      in20 : in std_logic_vector(11 downto 0); in21 : in std_logic_vector(11 downto 0);
      in22 : in std_logic_vector(11 downto 0); in23 : in std_logic_vector(11 downto 0);
      in24 : in std_logic_vector(11 downto 0); in25 : in std_logic_vector(11 downto 0);
      in26 : in std_logic_vector(11 downto 0); in27 : in std_logic_vector(11 downto 0);
      in28 : in std_logic_vector(11 downto 0); in29 : in std_logic_vector(11 downto 0);
      in30 : in std_logic_vector(11 downto 0); in31 : in std_logic_vector(11 downto 0);
      valid_in : in std_logic_vector(0 downto 0);
      clk      : in std_logic;
      out0re  : out std_logic_vector(22 downto 0); out0im  : out std_logic_vector(22 downto 0);
      out1re  : out std_logic_vector(22 downto 0); out1im  : out std_logic_vector(22 downto 0);
      out2re  : out std_logic_vector(22 downto 0); out2im  : out std_logic_vector(22 downto 0);
      out3re  : out std_logic_vector(22 downto 0); out3im  : out std_logic_vector(22 downto 0);
      out4re  : out std_logic_vector(22 downto 0); out4im  : out std_logic_vector(22 downto 0);
      out5re  : out std_logic_vector(22 downto 0); out5im  : out std_logic_vector(22 downto 0);
      out6re  : out std_logic_vector(22 downto 0); out6im  : out std_logic_vector(22 downto 0);
      out7re  : out std_logic_vector(22 downto 0); out7im  : out std_logic_vector(22 downto 0);
      out8re  : out std_logic_vector(22 downto 0); out8im  : out std_logic_vector(22 downto 0);
      out9re  : out std_logic_vector(22 downto 0); out9im  : out std_logic_vector(22 downto 0);
      out10re : out std_logic_vector(22 downto 0); out10im : out std_logic_vector(22 downto 0);
      out11re : out std_logic_vector(22 downto 0); out11im : out std_logic_vector(22 downto 0);
      out12re : out std_logic_vector(22 downto 0); out12im : out std_logic_vector(22 downto 0);
      out13re : out std_logic_vector(22 downto 0); out13im : out std_logic_vector(22 downto 0);
      out14re : out std_logic_vector(22 downto 0); out14im : out std_logic_vector(22 downto 0);
      out15re : out std_logic_vector(22 downto 0); out15im : out std_logic_vector(22 downto 0);
      out16re : out std_logic_vector(22 downto 0); out16im : out std_logic_vector(22 downto 0);
      valid_out : out std_logic_vector(0 downto 0)
    );
  end component;

  component rnd_23_18_0
    port (
      in23  : in  std_logic_vector(22 downto 0);
      clk   : in  std_logic;
      out18 : out std_logic_vector(17 downto 0)
    );
  end component;

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

  constant RND_LAT     : integer := 2;      -- rnd_23_18 latency
  constant RESTART_LEN : integer := 32;     -- clk_spec cycles 'valid' is held low
  constant NFINE       : integer := 4096;   -- fine channels = cycles per spectrum
  constant SETTLE_SPECTRA : integer := 6;   -- ignore outputs this long after a start
  constant SETTLE_CYC  : integer := SETTLE_SPECTRA * NFINE;

  type s12_arr_t is array (0 to 31) of std_logic_vector(11 downto 0);
  type s23_arr_t is array (0 to 16) of std_logic_vector(22 downto 0);

  signal rst : std_logic := '1';

  -- gearbox
  signal g_prev   : std_logic_vector(255 downto 0) := (others => '0');
  signal g_pair   : std_logic_vector(511 downto 0) := (others => '0');
  signal g_ph     : std_logic := '0';
  signal ts_r     : std_logic_vector(63 downto 0) := (others => '0');
  signal pfb_word : std_logic_vector(511 downto 0) := (others => '0');
  signal ts_s     : unsigned(63 downto 0) := (others => '0');

  -- coarse filter bank
  signal pin      : s12_arr_t;
  signal pfb_vin  : std_logic_vector(0 downto 0) := "0";
  signal pfb_vout : std_logic_vector(0 downto 0);
  signal ore, oim : s23_arr_t;
  signal sel_re, sel_im : std_logic_vector(22 downto 0) := (others => '0');
  signal fin_re, fin_im : std_logic_vector(17 downto 0);
  signal vdly     : std_logic_vector(RND_LAT downto 0) := (others => '0');

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
  -- 16 samples @ 245.76 MHz -> 32 samples @ 122.88 MHz
  -- clk_1x and clk_spec come from the same MMCM (phase aligned, 2:1).  g_pair
  -- changes every second clk_1x cycle and is stable for two clk_1x cycles, so
  -- each clk_spec edge captures every pair exactly once whatever the phase
  -- of g_ph.  The older word goes to lanes 0..15.
  -----------------------------------------------------------------------------
  process (clk_1x)
  begin
    if rising_edge(clk_1x) then
      g_prev <= din_1x;
      g_ph   <= not g_ph;
      if g_ph = '1' then
        g_pair <= din_1x & g_prev;
      end if;
      ts_r <= ts_1x;
    end if;
  end process;

  process (clk_spec)
  begin
    if rising_edge(clk_spec) then
      pfb_word <= g_pair;
      ts_s     <= unsigned(ts_r);
      pfb_vin(0) <= not rst;
    end if;
  end process;

  -- 12-bit ADC code = bits 15..4 of each 16-bit lane
  g_pin : for i in 0 to 31 generate
    pin(i) <= pfb_word(16*i+15 downto 16*i+4);
  end generate;

  g_nopfb : if SIM_NO_PFB generate
    ore      <= (others => (others => '0'));
    oim      <= (others => (others => '0'));
    pfb_vout <= pfb_vin;
  end generate;

  g_pfb : if not SIM_NO_PFB generate
  u_pfb : pfb32x16t_0
    port map (
      in0  => pin(0),  in1  => pin(1),  in2  => pin(2),  in3  => pin(3),
      in4  => pin(4),  in5  => pin(5),  in6  => pin(6),  in7  => pin(7),
      in8  => pin(8),  in9  => pin(9),  in10 => pin(10), in11 => pin(11),
      in12 => pin(12), in13 => pin(13), in14 => pin(14), in15 => pin(15),
      in16 => pin(16), in17 => pin(17), in18 => pin(18), in19 => pin(19),
      in20 => pin(20), in21 => pin(21), in22 => pin(22), in23 => pin(23),
      in24 => pin(24), in25 => pin(25), in26 => pin(26), in27 => pin(27),
      in28 => pin(28), in29 => pin(29), in30 => pin(30), in31 => pin(31),
      valid_in => pfb_vin,
      clk      => clk_spec,
      out0re  => ore(0),  out0im  => oim(0),
      out1re  => ore(1),  out1im  => oim(1),
      out2re  => ore(2),  out2im  => oim(2),
      out3re  => ore(3),  out3im  => oim(3),
      out4re  => ore(4),  out4im  => oim(4),
      out5re  => ore(5),  out5im  => oim(5),
      out6re  => ore(6),  out6im  => oim(6),
      out7re  => ore(7),  out7im  => oim(7),
      out8re  => ore(8),  out8im  => oim(8),
      out9re  => ore(9),  out9im  => oim(9),
      out10re => ore(10), out10im => oim(10),
      out11re => ore(11), out11im => oim(11),
      out12re => ore(12), out12im => oim(12),
      out13re => ore(13), out13im => oim(13),
      out14re => ore(14), out14im => oim(14),
      out15re => ore(15), out15im => oim(15),
      out16re => ore(16), out16im => oim(16),
      valid_out => pfb_vout
    );
  end generate;

  -----------------------------------------------------------------------------
  -- subband select: channels 0 (DC) and 16 (Nyquist) are real
  -----------------------------------------------------------------------------
  process (clk_spec)
    variable k : integer range 0 to 31;
  begin
    if rising_edge(clk_spec) then
      k := to_integer(cfg_subband);
      if k = 0 or k >= 16 then
        if k = 0 then
          sel_re <= ore(0);
        else
          sel_re <= ore(16);
        end if;
        sel_im <= (others => '0');
      else
        sel_re <= ore(k);
        sel_im <= oim(k);
      end if;
      -- valid follows the data through the mux (1) and the rounding (RND_LAT)
      vdly <= vdly(RND_LAT-1 downto 0) & pfb_vout(0);
    end if;
  end process;

  u_rnd_re : rnd_23_18_0 port map (in23 => sel_re, clk => clk_spec, out18 => fin_re);
  u_rnd_im : rnd_23_18_0 port map (in23 => sel_im, clk => clk_spec, out18 => fin_im);

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
        dfb_valid <= vdly(RND_LAT);
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
      in_im         => fin_im,
      in_re         => fin_re,
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
      p_restart     => p_restart,
      p_release     => p_release,
      p_cnt_clear   => p_cnt_clear,
      st_nfull      => nfull,
      st_head       => head,
      st_running    => dfb_valid,
      st_writing    => writing,
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
  --   "W <bank> <addr> <data hex>" and "C <seq> <first> <subband> <acc_len>"
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
        if pfb_vout(0) /= pv then pv := pfb_vout(0); ev("pfb_valid_out", pv); end if;
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
        if not seen_pfb and unsigned(ore(12)) /= 0 then
          seen_pfb := true; ev("pfb_out12_nonzero", '1');
        end if;
        if not seen_fin and unsigned(fin_re) /= 0 then
          seen_fin := true; ev("dfb_in_nonzero", '1');
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
          writeline(f, l);
        end if;
      end if;
    end process;
  end generate;
  -- pragma translate_on

end architecture rtl;
