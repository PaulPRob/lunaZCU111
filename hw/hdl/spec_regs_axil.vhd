-------------------------------------------------------------------------------
-- spec_regs_axil : AXI4-Lite registers + spectrum memory window of the
--                  spectrometer (clk_spec domain, 122.88 MHz)
--
-- Register map (byte offsets, 32-bit registers) - see docs/register_map.md
--   0x000 ID          RO  0x4C535043 ("LSPC")
--   0x004 VERSION     RO  [31:16] major [15:8] minor [7:0] number of banks (2)
--   0x008 CTRL        RW  bit0 ENABLE, bit8 IRQ_EN (levels)
--                         W1 pulses: bit1 RESTART, bit4 CNT_CLEAR
--   0x00C STATUS      RO  [1:0] banks full, bit4 head bank, bit8 enabled,
--                         bit9 running (fine filter bank fed), bit10 writing
--   0x010 SUBBAND     RW  coarse channel 0..16 for the fine filter bank (12);
--                         a write restarts the integration
--   0x014 ACC_LEN     RW  spectra per integration - 1 (179999 = 6.000 s);
--                         a write restarts the integration
--   0x018 RELEASE     WO  bit0 : free the oldest full bank
--   0x01C SPEC_COUNT  RO  integrations stored
--   0x020 LOST_COUNT  RO  integrations lost (both banks full)
--   0x024 RESTARTS    RO  integration restarts
--   0x028 SCRATCH     RW
--   0x02C INPUT       RW  ADC channel 0..7 feeding the filter banks (0);
--                         a write restarts the integration
--   0x030 HEAD_SEQ    RO  oldest full bank: sequence number
--   0x034 HEAD_FLAGS  RO  oldest full bank: bit0 first after restart,
--                         [12:8] subband, [18:16] input ADC channel
--   0x038 HEAD_ACCLEN RO  oldest full bank: ACC_LEN used
--   0x03C HEAD_TS_LO  RO  oldest full bank: sample counter at the end of
--   0x040 HEAD_TS_HI      the integration (trigger-core time base)
--   0x10000 + b*0x8000 + 8*k (+4) : bank b, channel k, power [31:0] ([63:32])
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spec_regs_axil is
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    -- AXI4-Lite slave
    s_axi_awaddr  : in  std_logic_vector(16 downto 0);
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
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;
    -- configuration outputs
    cfg_enable    : out std_logic;
    cfg_irq_en    : out std_logic;
    cfg_subband   : out unsigned(4 downto 0);
    cfg_acc_len   : out unsigned(31 downto 0);
    cfg_input     : out unsigned(2 downto 0);
    -- pulses
    p_restart     : out std_logic;
    p_release     : out std_logic;
    p_cnt_clear   : out std_logic;
    -- status inputs
    st_nfull      : in  unsigned(1 downto 0);
    st_head       : in  std_logic;
    st_running    : in  std_logic;
    st_writing    : in  std_logic;
    st_spec_cnt   : in  unsigned(31 downto 0);
    st_lost_cnt   : in  unsigned(31 downto 0);
    st_restarts   : in  unsigned(31 downto 0);
    hd_seq        : in  unsigned(31 downto 0);
    hd_flags      : in  std_logic_vector(31 downto 0);
    hd_acc_len    : in  unsigned(31 downto 0);
    hd_ts         : in  unsigned(63 downto 0);
    -- spectrum memory read port (latency 2)
    mem_raddr     : out unsigned(12 downto 0);
    mem_dout      : in  std_logic_vector(63 downto 0)
  );
end entity spec_regs_axil;

architecture rtl of spec_regs_axil is

  constant ACC_LEN_DEFAULT : integer := 179999;   -- 180000 x 33.33 us = 6.000 s

  signal r_enable, r_irq_en : std_logic := '0';
  signal r_subband : unsigned(4 downto 0)  := to_unsigned(12, 5);
  signal r_acc_len : unsigned(31 downto 0) := to_unsigned(ACC_LEN_DEFAULT, 32);
  signal r_scratch : std_logic_vector(31 downto 0) := (others => '0');
  signal r_input   : unsigned(2 downto 0)  := (others => '0');

  -- AXI handshake state
  signal aw_ok, w_ok : std_logic := '0';
  signal aw_addr     : std_logic_vector(16 downto 0);
  signal w_data      : std_logic_vector(31 downto 0);
  signal bvalid_i    : std_logic := '0';
  signal rvalid_i    : std_logic := '0';
  signal rbusy       : std_logic := '0';
  signal rdata_i     : std_logic_vector(31 downto 0) := (others => '0');
  signal mem_wait    : integer range 0 to 3 := 0;
  signal mem_hi      : std_logic := '0';

begin

  s_axi_awready <= not aw_ok and not bvalid_i;
  s_axi_wready  <= not w_ok and not bvalid_i;
  s_axi_bresp   <= "00";
  s_axi_bvalid  <= bvalid_i;
  s_axi_arready <= not rvalid_i and not rbusy;
  s_axi_rresp   <= "00";
  s_axi_rvalid  <= rvalid_i;
  s_axi_rdata   <= rdata_i;

  -----------------------------------------------------------------------------
  -- write channel
  -----------------------------------------------------------------------------
  process (clk)
    variable a : integer range 0 to 1023;
    variable v : unsigned(31 downto 0);
  begin
    if rising_edge(clk) then
      p_restart   <= '0';
      p_release   <= '0';
      p_cnt_clear <= '0';

      if s_axi_awvalid = '1' and aw_ok = '0' and bvalid_i = '0' then
        aw_ok   <= '1';
        aw_addr <= s_axi_awaddr;
      end if;
      if s_axi_wvalid = '1' and w_ok = '0' and bvalid_i = '0' then
        w_ok   <= '1';
        w_data <= s_axi_wdata;
      end if;

      if aw_ok = '1' and w_ok = '1' then
        aw_ok    <= '0';
        w_ok     <= '0';
        bvalid_i <= '1';
        a := to_integer(unsigned(aw_addr(11 downto 2)));
        v := unsigned(w_data);
        if aw_addr(16) = '0' then          -- the memory window is read only
          case a is
            when 16#008#/4 =>
              r_enable    <= w_data(0);
              p_restart   <= w_data(1);
              p_cnt_clear <= w_data(4);
              r_irq_en    <= w_data(8);
            when 16#010#/4 =>
              if v > 16 then
                r_subband <= to_unsigned(16, 5);
              else
                r_subband <= v(4 downto 0);
              end if;
              p_restart <= '1';
            when 16#014#/4 =>
              r_acc_len <= v;
              p_restart <= '1';
            when 16#018#/4 =>
              p_release <= w_data(0);
            when 16#028#/4 =>
              r_scratch <= w_data;
            when 16#02C#/4 =>
              r_input   <= v(2 downto 0);
              p_restart <= '1';
            when others =>
              null;
          end case;
        end if;
      end if;

      if bvalid_i = '1' and s_axi_bready = '1' then
        bvalid_i <= '0';
      end if;

      if rst = '1' then
        aw_ok    <= '0';
        w_ok     <= '0';
        bvalid_i <= '0';
        r_enable <= '0';
        r_irq_en <= '0';
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- read channel (registers: 1 cycle, memory window: 3 cycles)
  -----------------------------------------------------------------------------
  process (clk)
    variable a : integer range 0 to 1023;
    variable d : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      if s_axi_arvalid = '1' and rvalid_i = '0' and rbusy = '0' then
        if s_axi_araddr(16) = '1' then
          mem_raddr <= unsigned(s_axi_araddr(15 downto 3));
          mem_hi    <= s_axi_araddr(2);
          mem_wait  <= 3;
          rbusy     <= '1';
        else
          a := to_integer(unsigned(s_axi_araddr(11 downto 2)));
          d := (others => '0');
          case a is
            when 16#000#/4 => d := x"4C535043";
            when 16#004#/4 => d := x"0001" & x"01" & x"02";
            when 16#008#/4 => d(0) := r_enable; d(8) := r_irq_en;
            when 16#00C#/4 =>
              d(1 downto 0) := std_logic_vector(st_nfull);
              d(4)  := st_head;
              d(8)  := r_enable;
              d(9)  := st_running;
              d(10) := st_writing;
            when 16#010#/4 => d := std_logic_vector(resize(r_subband, 32));
            when 16#014#/4 => d := std_logic_vector(r_acc_len);
            when 16#01C#/4 => d := std_logic_vector(st_spec_cnt);
            when 16#020#/4 => d := std_logic_vector(st_lost_cnt);
            when 16#024#/4 => d := std_logic_vector(st_restarts);
            when 16#028#/4 => d := r_scratch;
            when 16#02C#/4 => d := std_logic_vector(resize(r_input, 32));
            when 16#030#/4 => d := std_logic_vector(hd_seq);
            when 16#034#/4 => d := hd_flags;
            when 16#038#/4 => d := std_logic_vector(hd_acc_len);
            when 16#03C#/4 => d := std_logic_vector(hd_ts(31 downto 0));
            when 16#040#/4 => d := std_logic_vector(hd_ts(63 downto 32));
            when others    => null;
          end case;
          rdata_i  <= d;
          rvalid_i <= '1';
        end if;
      elsif rbusy = '1' then
        if mem_wait = 1 then
          if mem_hi = '1' then
            rdata_i <= mem_dout(63 downto 32);
          else
            rdata_i <= mem_dout(31 downto 0);
          end if;
          rvalid_i <= '1';
          rbusy    <= '0';
        end if;
        mem_wait <= mem_wait - 1;
      elsif rvalid_i = '1' and s_axi_rready = '1' then
        rvalid_i <= '0';
      end if;
      if rst = '1' then
        rvalid_i <= '0';
        rbusy    <= '0';
        mem_wait <= 0;
      end if;
    end if;
  end process;

  cfg_enable  <= r_enable;
  cfg_irq_en  <= r_irq_en;
  cfg_subband <= r_subband;
  cfg_acc_len <= r_acc_len;
  cfg_input   <= r_input;

end architecture rtl;
