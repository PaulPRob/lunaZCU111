-------------------------------------------------------------------------------
-- trig_regs_axil : AXI4-Lite register block (clk_1x domain)
--
-- Register map (byte offsets, 32-bit registers) - see docs/register_map.md
--   0x000 ID          RO  0x4C554E41 ("LUNA")
--   0x004 VERSION     RO  [31:16] major [15:8] minor [7:0] number of banks
--   0x008 CTRL        RW  bit0 ARM, bit8 IRQ_EN (levels)
--                         W1 pulses: bit1 SOFT_TRIG, bit2 TS_RESET(+flush),
--                                    bit3 FLUSH, bit4 CNT_CLEAR
--   0x00C STATUS      RO  [3:0] nfull [7:4] head bit8 capturing bit9 rd_busy
--                         bit10 prefilled bit16 armed
--   0x010 MODE        RW  bit0 : 0 = coincidence, 1 = anti-coincidence
--   0x014 COINC_N     RW  1..8
--   0x018 WINDOW      RW  1..255 samples (default 64)
--   0x01C CH_MASK     RW  [7:0] channels taking part in triggering
--   0x020 CAP_LEN     RW  samples per channel, 4096..16384, multiple of 32
--   0x024 READOUT     WO  bit0 : start streaming the oldest full bank
--   0x028 RELEASE     WO  bit0 : free the oldest full bank
--   0x030 TS_LO       RO  current sample counter [31:0] (latches TS_HI)
--   0x034 TS_HI       RO  current sample counter [63:32]
--   0x038 TRIG_COUNT  RO  accepted triggers
--   0x03C LOST_COUNT  RO  triggers lost (no free bank / pre-fill incomplete)
--   0x040+4*i THRESH  RW  channel i threshold, |x| > THRESH is a hit (16 bit)
--   0x060+4*i HITCNT  RO  channel i: clock cycles containing >= 1 hit
--   0x080+4*i PEAK    RO  channel i: max |x| since last read (read clears)
--   0x0A0 SYSREF_CNT  RO  PL SYSREF rising edges seen
--   0x0A4 SCRATCH     RW
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.luna_pkg.all;

entity trig_regs_axil is
  generic (
    NB_LOG2 : integer := 2
  );
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    -- AXI4-Lite slave
    s_axi_awaddr  : in  std_logic_vector(11 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata   : in  std_logic_vector(31 downto 0);
    s_axi_wstrb   : in  std_logic_vector(3 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;
    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;
    s_axi_araddr  : in  std_logic_vector(11 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;
    s_axi_rdata   : out std_logic_vector(31 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic;
    -- configuration outputs
    cfg_arm       : out std_logic;
    cfg_irq_en    : out std_logic;
    cfg_mode_anti : out std_logic;
    cfg_n         : out unsigned(3 downto 0);
    cfg_win       : out unsigned(7 downto 0);
    cfg_mask      : out std_logic_vector(NCH-1 downto 0);
    cfg_len_w     : out unsigned(10 downto 0);
    cfg_thresh    : out u16_arr_t;
    -- pulses
    p_soft_trig   : out std_logic;
    p_ts_reset    : out std_logic;
    p_flush       : out std_logic;
    p_cnt_clear   : out std_logic;
    p_rd_start    : out std_logic;
    p_release     : out std_logic;
    p_peak_clr    : out std_logic_vector(NCH-1 downto 0);
    -- status inputs
    st_nfull      : in  unsigned(NB_LOG2 downto 0);
    st_head       : in  unsigned(NB_LOG2-1 downto 0);
    st_capturing  : in  std_logic;
    st_rd_busy    : in  std_logic;
    st_prefilled  : in  std_logic;
    st_ts         : in  unsigned(63 downto 0);
    st_trig_cnt   : in  unsigned(31 downto 0);
    st_lost_cnt   : in  unsigned(31 downto 0);
    st_hit_cnt    : in  u32_arr_t;
    st_peak       : in  u16_arr_t;
    st_sysref_cnt : in  unsigned(31 downto 0)
  );
end entity trig_regs_axil;

architecture rtl of trig_regs_axil is

  signal r_arm, r_irq_en, r_mode : std_logic := '0';
  signal r_n      : unsigned(3 downto 0) := to_unsigned(2, 4);
  signal r_win    : unsigned(7 downto 0) := to_unsigned(64, 8);
  signal r_mask   : std_logic_vector(NCH-1 downto 0) := (others => '1');
  signal r_len_w  : unsigned(10 downto 0) := to_unsigned(1024, 11);
  signal r_thresh : u16_arr_t := (others => to_unsigned(16#4000#, 16));
  signal r_scratch: std_logic_vector(31 downto 0) := (others => '0');
  signal ts_hi_l  : unsigned(31 downto 0) := (others => '0');

  -- AXI handshake state
  signal aw_ok, w_ok : std_logic := '0';
  signal aw_addr     : std_logic_vector(11 downto 0);
  signal w_data      : std_logic_vector(31 downto 0);
  signal bvalid_i    : std_logic := '0';
  signal rvalid_i    : std_logic := '0';
  signal rdata_i     : std_logic_vector(31 downto 0) := (others => '0');

begin

  s_axi_awready <= not aw_ok and not bvalid_i;
  s_axi_wready  <= not w_ok and not bvalid_i;
  s_axi_bresp   <= "00";
  s_axi_bvalid  <= bvalid_i;
  s_axi_arready <= not rvalid_i;
  s_axi_rresp   <= "00";
  s_axi_rvalid  <= rvalid_i;
  s_axi_rdata   <= rdata_i;

  -----------------------------------------------------------------------------
  -- write channel
  -----------------------------------------------------------------------------
  process (clk)
    variable a  : integer range 0 to 1023;
    variable v  : unsigned(31 downto 0);
    variable nw : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      p_soft_trig <= '0';
      p_ts_reset  <= '0';
      p_flush     <= '0';
      p_cnt_clear <= '0';
      p_rd_start  <= '0';
      p_release   <= '0';

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
        case a is
          when 16#008#/4 =>
            r_arm       <= w_data(0);
            p_soft_trig <= w_data(1);
            p_ts_reset  <= w_data(2);
            p_flush     <= w_data(3) or w_data(2);
            p_cnt_clear <= w_data(4);
            r_irq_en    <= w_data(8);
          when 16#010#/4 =>
            r_mode <= w_data(0);
          when 16#014#/4 =>
            if v = 0 then
              r_n <= to_unsigned(1, 4);
            elsif v > NCH then
              r_n <= to_unsigned(NCH, 4);
            else
              r_n <= v(3 downto 0);
            end if;
          when 16#018#/4 =>
            if v = 0 then
              r_win <= to_unsigned(1, 8);
            elsif v > 255 then
              r_win <= to_unsigned(255, 8);
            else
              r_win <= v(7 downto 0);
            end if;
          when 16#01C#/4 =>
            r_mask <= w_data(NCH-1 downto 0);
          when 16#020#/4 =>
            -- samples -> words (L/16), clamp to 256..1024 and force even
            if v < 4096 then
              nw := to_unsigned(256, 16);
            elsif v > 16384 then
              nw := to_unsigned(1024, 16);
            else
              nw := v(19 downto 4);
            end if;
            nw(0) := '0';
            r_len_w <= nw(10 downto 0);
          when 16#024#/4 =>
            p_rd_start <= w_data(0);
          when 16#028#/4 =>
            p_release <= w_data(0);
          when 16#0A4#/4 =>
            r_scratch <= w_data;
          when others =>
            if a >= 16#040#/4 and a < 16#040#/4 + NCH then
              r_thresh(a - 16#040#/4) <= v(15 downto 0);
            end if;
        end case;
      end if;

      if bvalid_i = '1' and s_axi_bready = '1' then
        bvalid_i <= '0';
      end if;

      if rst = '1' then
        aw_ok    <= '0';
        w_ok     <= '0';
        bvalid_i <= '0';
        r_arm    <= '0';
        r_irq_en <= '0';
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- read channel
  -----------------------------------------------------------------------------
  process (clk)
    variable a : integer range 0 to 1023;
    variable d : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk) then
      p_peak_clr <= (others => '0');
      if s_axi_arvalid = '1' and rvalid_i = '0' then
        a := to_integer(unsigned(s_axi_araddr(11 downto 2)));
        d := (others => '0');
        case a is
          when 16#000#/4 => d := x"4C554E41";
          when 16#004#/4 => d := x"0001" & x"00" & std_logic_vector(to_unsigned(2**NB_LOG2, 8));
          when 16#008#/4 => d(0) := r_arm; d(8) := r_irq_en;
          when 16#00C#/4 =>
            d(3 downto 0) := std_logic_vector(resize(st_nfull, 4));
            d(7 downto 4) := std_logic_vector(resize(st_head, 4));
            d(8)  := st_capturing;
            d(9)  := st_rd_busy;
            d(10) := st_prefilled;
            d(16) := r_arm;
          when 16#010#/4 => d(0) := r_mode;
          when 16#014#/4 => d := std_logic_vector(resize(r_n, 32));
          when 16#018#/4 => d := std_logic_vector(resize(r_win, 32));
          when 16#01C#/4 => d(NCH-1 downto 0) := r_mask;
          when 16#020#/4 => d := std_logic_vector(resize(r_len_w & "0000", 32));
          when 16#030#/4 =>
            d := std_logic_vector(st_ts(31 downto 0));
            ts_hi_l <= st_ts(63 downto 32);
          when 16#034#/4 => d := std_logic_vector(ts_hi_l);
          when 16#038#/4 => d := std_logic_vector(st_trig_cnt);
          when 16#03C#/4 => d := std_logic_vector(st_lost_cnt);
          when 16#0A0#/4 => d := std_logic_vector(st_sysref_cnt);
          when 16#0A4#/4 => d := r_scratch;
          when others =>
            if a >= 16#040#/4 and a < 16#040#/4 + NCH then
              d := std_logic_vector(resize(r_thresh(a - 16#040#/4), 32));
            elsif a >= 16#060#/4 and a < 16#060#/4 + NCH then
              d := std_logic_vector(st_hit_cnt(a - 16#060#/4));
            elsif a >= 16#080#/4 and a < 16#080#/4 + NCH then
              d := std_logic_vector(resize(st_peak(a - 16#080#/4), 32));
              p_peak_clr(a - 16#080#/4) <= '1';
            end if;
        end case;
        rdata_i  <= d;
        rvalid_i <= '1';
      elsif rvalid_i = '1' and s_axi_rready = '1' then
        rvalid_i <= '0';
      end if;
      if rst = '1' then
        rvalid_i <= '0';
      end if;
    end if;
  end process;

  cfg_arm       <= r_arm;
  cfg_irq_en    <= r_irq_en;
  cfg_mode_anti <= r_mode;
  cfg_n         <= r_n;
  cfg_win       <= r_win;
  cfg_mask      <= r_mask;
  cfg_len_w     <= r_len_w;
  cfg_thresh    <= r_thresh;

end architecture rtl;
