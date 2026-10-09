-------------------------------------------------------------------------------
-- capture_ctrl : multi-bank capture buffers + event readout stream
--
-- NB = 2**NB_LOG2 banks (default 4).  Each bank is a 1024-word ring buffer
-- (1024 x 16 = 16384 samples) per channel.  Banks are used round robin:
--
--   FULL banks  : head, head+1, ... head+nfull-1   (waiting for readout)
--   ACTIVE bank : head+nfull  (only if nfull < NB) - continuously written
--
-- Trigger at sample T (cycle T/16):  the event window is the L/16 words
--   [S, S+L/16-1]  with  S = T/16 - L/32
-- so the trigger sits at sample offset L/2 + (T mod 16) in the buffer.
-- A trigger is accepted only if the active bank has already been written
-- since word S (pre-trigger fill); writing continues until word S+L/16-1,
-- then the bank is frozen and the next bank becomes active.
-- Triggers arriving while no bank is free / pre-fill is incomplete are
-- counted in cnt_lost.  Triggers during an ongoing post-trigger capture are
-- part of the same event and are ignored.
--
-- Readout (rd_start): streams the head bank as a 128-bit AXI-Stream:
--   64-byte header, then ch0[L], ch1[L] ... ch7[L]  (int16 little endian),
--   tlast on the final beat.  'release' then frees the head bank.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.luna_pkg.all;

entity capture_ctrl is
  generic (
    NB_LOG2 : integer := 2
  );
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    -- sample stream (cycle index din_cyc)
    din           : in  word_arr_t;
    din_cyc       : in  unsigned(CYC_W-1 downto 0);
    -- trigger
    trig_valid    : in  std_logic;
    trig_pos      : in  unsigned(63 downto 0);
    trig_mask     : in  std_logic_vector(NCH-1 downto 0);
    trig_src      : in  std_logic_vector(1 downto 0);
    -- configuration (copied into the event header)
    cap_len_w     : in  unsigned(10 downto 0);     -- L/16 : 256..1024, even
    cfg_win       : in  unsigned(7 downto 0);
    cfg_n         : in  unsigned(3 downto 0);
    cfg_mode      : in  std_logic;
    cfg_veto_en   : in  std_logic;
    cfg_veto_ch   : in  unsigned(2 downto 0);
    -- control
    flush         : in  std_logic;
    rd_start      : in  std_logic;
    release       : in  std_logic;
    -- status
    st_nfull      : out unsigned(NB_LOG2 downto 0);
    st_head       : out unsigned(NB_LOG2-1 downto 0);
    st_capturing  : out std_logic;
    st_rd_busy    : out std_logic;
    st_prefilled  : out std_logic;
    rd_done       : out std_logic;
    cnt_trig      : out unsigned(31 downto 0);
    cnt_lost      : out unsigned(31 downto 0);
    -- readout stream
    m_axis_tdata  : out std_logic_vector(127 downto 0);
    m_axis_tkeep  : out std_logic_vector(15 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tlast  : out std_logic;
    m_axis_tready : in  std_logic
  );
end entity capture_ctrl;

architecture rtl of capture_ctrl is

  constant NB : integer := 2**NB_LOG2;
  constant AW : integer := NB_LOG2 + RING_AW;

  subtype cyc_t is unsigned(CYC_W-1 downto 0);

  -- per-bank event headers
  type u64_nb_t  is array (0 to NB-1) of unsigned(63 downto 0);
  type cyc_nb_t  is array (0 to NB-1) of cyc_t;
  type u32_nb_t  is array (0 to NB-1) of unsigned(31 downto 0);
  type u11_nb_t  is array (0 to NB-1) of unsigned(10 downto 0);
  type slv8_nb_t is array (0 to NB-1) of std_logic_vector(7 downto 0);
  type slv2_nb_t is array (0 to NB-1) of std_logic_vector(1 downto 0);
  type u8_nb_t   is array (0 to NB-1) of unsigned(7 downto 0);
  type u4_nb_t   is array (0 to NB-1) of unsigned(3 downto 0);

  signal h_trig  : u64_nb_t;
  signal h_start : cyc_nb_t;
  signal h_len   : u11_nb_t;
  signal h_seq   : u32_nb_t;
  signal h_lost  : u32_nb_t;
  signal h_tcnt  : u32_nb_t;
  signal h_mask  : slv8_nb_t;
  signal h_src   : slv2_nb_t;
  signal h_win   : u8_nb_t;
  signal h_n     : u4_nb_t;
  signal h_mode  : std_logic_vector(NB-1 downto 0);
  type veto_arr_t is array (0 to NB-1) of std_logic_vector(7 downto 0);
  signal h_veto  : veto_arr_t;                 -- bit7 enable, [2:0] channel

  -- bank state
  signal head         : unsigned(NB_LOG2-1 downto 0) := (others => '0');
  signal nfull        : unsigned(NB_LOG2 downto 0)   := (others => '0');
  signal capturing    : std_logic := '0';
  signal cap_end      : cyc_t := (others => '0');
  signal active_start : cyc_t := (others => '0');
  signal active_valid : std_logic;
  signal active_idx   : unsigned(NB_LOG2-1 downto 0);

  signal seq_cnt  : unsigned(31 downto 0) := (others => '0');
  signal trig_cnt : unsigned(31 downto 0) := (others => '0');
  signal lost_cnt : unsigned(31 downto 0) := (others => '0');

  -- trigger stage 1
  signal t1_valid : std_logic := '0';
  signal t1_pos   : unsigned(63 downto 0);
  signal t1_s     : cyc_t;
  signal t1_e     : cyc_t;
  signal t1_mask  : std_logic_vector(NCH-1 downto 0);
  signal t1_src   : std_logic_vector(1 downto 0);
  signal t1_len   : unsigned(10 downto 0);

  -- memory
  signal w_en   : std_logic := '0';
  signal w_addr : unsigned(AW-1 downto 0);
  signal w_data : word_arr_t;
  signal r_addr : unsigned(AW-1 downto 0) := (others => '0');
  signal r_data : word_arr_t;

  -- readout
  type rs_t is (RS_IDLE, RS_HDR0, RS_HDR1, RS_DATA, RS_WAIT);
  signal rs        : rs_t := RS_IDLE;
  signal rd_busy   : std_logic := '0';
  signal rd_bank   : unsigned(NB_LOG2-1 downto 0);
  signal rd_len    : unsigned(10 downto 0);
  signal rd_start0 : unsigned(RING_AW-1 downto 0);
  signal rd_ch     : integer range 0 to NCH-1;
  signal rd_k      : unsigned(10 downto 0);
  signal hdr0, hdr1: std_logic_vector(WORD_W-1 downto 0);

  type chpipe_t is array (0 to 2) of integer range 0 to NCH-1;
  signal p_v   : std_logic_vector(2 downto 0) := (others => '0');
  signal p_ch  : chpipe_t;

  constant FD : integer := 16;
  type fifo_t is array (0 to FD-1) of std_logic_vector(WORD_W-1 downto 0);
  signal fifo     : fifo_t;
  signal f_wp     : unsigned(3 downto 0) := (others => '0');
  signal f_rp     : unsigned(3 downto 0) := (others => '0');
  signal f_cnt    : unsigned(4 downto 0) := (others => '0');
  signal f_push   : std_logic;
  signal f_pop    : std_logic;
  signal f_din    : std_logic_vector(WORD_W-1 downto 0);
  signal half     : std_logic := '0';
  signal out_cnt  : unsigned(13 downto 0) := (others => '0');  -- words sent
  signal out_tot  : unsigned(13 downto 0) := (others => '0');  -- 2 + 8*len
  signal tvalid_i : std_logic;
  signal tlast_i  : std_logic;
  signal inflight : unsigned(2 downto 0);

begin

  active_valid <= '1' when nfull < NB else '0';
  active_idx   <= head + nfull(NB_LOG2-1 downto 0);

  ---------------------------------------------------------------------------
  -- capture memories (one per channel)
  ---------------------------------------------------------------------------
  g_mem : for ch in 0 to NCH-1 generate
    u_mem : entity work.capture_mem
      generic map (AW => AW, DW => WORD_W)
      port map (
        clk   => clk,
        we    => w_en,
        waddr => w_addr,
        wdata => w_data(ch),
        raddr => r_addr,
        dout  => r_data(ch)
      );
  end generate;

  ---------------------------------------------------------------------------
  -- trigger pre-computation (stage 1)
  ---------------------------------------------------------------------------
  process (clk)
    variable tcyc : cyc_t;
    variable hl   : cyc_t;
  begin
    if rising_edge(clk) then
      tcyc := trig_pos(63 downto 4);
      hl   := resize(cap_len_w(10 downto 1), CYC_W);
      t1_valid <= trig_valid and not rst;
      t1_pos   <= trig_pos;
      t1_s     <= tcyc - hl;
      t1_e     <= tcyc + hl - 1;
      t1_mask  <= trig_mask;
      t1_src   <= trig_src;
      t1_len   <= cap_len_w;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- bank state machine + memory write
  ---------------------------------------------------------------------------
  process (clk)
    variable inc, dec : boolean;
    variable ai       : integer range 0 to NB-1;
  begin
    if rising_edge(clk) then
      -- memory write (registered)
      w_en   <= active_valid;
      w_addr <= active_idx & din_cyc(RING_AW-1 downto 0);
      w_data <= din;

      inc := false;
      dec := false;
      ai  := to_integer(active_idx);

      -- end of post-trigger capture: last word is written this cycle
      if capturing = '1' and din_cyc = cap_end then
        capturing <= '0';
        inc := true;
      end if;

      -- trigger decision
      if t1_valid = '1' then
        if capturing = '1' then
          null;                                 -- same event
        elsif active_valid = '0' then
          lost_cnt <= lost_cnt + 1;             -- all banks full
        elsif t1_s >= active_start then
          capturing    <= '1';
          cap_end      <= t1_e;
          h_trig(ai)   <= t1_pos;
          h_start(ai)  <= t1_s;
          h_len(ai)    <= t1_len;
          h_seq(ai)    <= seq_cnt;
          h_lost(ai)   <= lost_cnt;
          h_tcnt(ai)   <= trig_cnt + 1;
          h_mask(ai)   <= t1_mask;
          h_src(ai)    <= t1_src;
          h_win(ai)    <= cfg_win;
          h_n(ai)      <= cfg_n;
          h_mode(ai)   <= cfg_mode;
          h_veto(ai)   <= cfg_veto_en & "0000" & std_logic_vector(cfg_veto_ch);
          seq_cnt      <= seq_cnt + 1;
          trig_cnt     <= trig_cnt + 1;
        else
          lost_cnt <= lost_cnt + 1;             -- pre-trigger fill incomplete
        end if;
      end if;

      if release = '1' and nfull /= 0 and rd_busy = '0' then
        dec := true;
      end if;

      if inc and not dec then
        nfull <= nfull + 1;
      elsif dec and not inc then
        nfull <= nfull - 1;
      end if;
      if dec then
        head <= head + 1;
      end if;
      -- a (new) active bank starts filling from the next word
      if inc or (dec and nfull = NB) then
        active_start <= din_cyc + 1;
      end if;

      if rst = '1' or flush = '1' then
        head         <= (others => '0');
        nfull        <= (others => '0');
        capturing    <= '0';
        active_start <= din_cyc + 1;
        w_en         <= '0';
      end if;
      if rst = '1' then
        seq_cnt  <= (others => '0');
        trig_cnt <= (others => '0');
        lost_cnt <= (others => '0');
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- readout : read issue side
  ---------------------------------------------------------------------------
  inflight <= ("00" & p_v(0)) + ("00" & p_v(1)) + ("00" & p_v(2));

  process (clk)
    variable b : integer range 0 to NB-1;
  begin
    if rising_edge(clk) then
      rd_done <= '0';
      p_v(0)  <= '0';
      p_v(2 downto 1) <= p_v(1 downto 0);
      p_ch(1) <= p_ch(0);
      p_ch(2) <= p_ch(1);

      case rs is
        when RS_IDLE =>
          if rd_start = '1' and nfull /= 0 then
            b         := to_integer(head);
            rd_bank   <= head;
            rd_busy   <= '1';
            rd_len    <= h_len(b);
            rd_start0 <= h_start(b)(RING_AW-1 downto 0);
            rd_ch     <= 0;
            rd_k      <= (others => '0');
            out_tot   <= resize(h_len(b) & "000", 14) + 2;
            -- header word 0 (bytes 0..31)
            hdr0 <= std_logic_vector(h_start(b)) & "0000"                       -- start sample
                    & std_logic_vector(h_trig(b))                                -- trigger sample
                    & std_logic_vector(resize(h_len(b) & "0000", 32))            -- n samples
                    & std_logic_vector(h_seq(b))                                 -- event seq
                    & x"0040" & x"0002"                                          -- hdr bytes, version
                    & x"414E554C";                                               -- "LUNA"
            -- header word 1 (bytes 32..63)
            hdr1 <= std_logic_vector(to_unsigned(0, 88))
                    & h_veto(b)                                                  -- veto
                    & std_logic_vector(h_tcnt(b))                                -- trigger count
                    & std_logic_vector(h_lost(b))                                -- lost count
                    & "0000000" & h_mode(b)                                      -- mode
                    & "0000" & std_logic_vector(h_n(b))                          -- coinc N
                    & x"00" & std_logic_vector(h_win(b))                         -- window
                    & std_logic_vector(resize(head, 8))                          -- bank
                    & x"08"                                                      -- n channels
                    & "000000" & h_src(b)                                        -- trigger source
                    & h_mask(b)                                                  -- trigger mask
                    & std_logic_vector(h_trig(b)(31 downto 0) -
                                       (h_start(b)(27 downto 0) & "0000"));      -- trig offset
            rs <= RS_HDR0;
          end if;

        when RS_HDR0 =>
          rs <= RS_HDR1;

        when RS_HDR1 =>
          rs <= RS_DATA;

        when RS_DATA =>
          if f_cnt + inflight < FD - 4 then
            r_addr  <= rd_bank & (rd_start0 + rd_k(RING_AW-1 downto 0));
            p_v(0)  <= '1';
            p_ch(0) <= rd_ch;
            if rd_k = rd_len - 1 then
              rd_k <= (others => '0');
              if rd_ch = NCH-1 then
                rs <= RS_WAIT;
              else
                rd_ch <= rd_ch + 1;
              end if;
            else
              rd_k <= rd_k + 1;
            end if;
          end if;

        when RS_WAIT =>
          if f_pop = '1' and half = '1' and out_cnt = out_tot - 1 then
            rs      <= RS_IDLE;
            rd_busy <= '0';
            rd_done <= '1';
          end if;
      end case;

      if rst = '1' or flush = '1' then
        rs      <= RS_IDLE;
        rd_busy <= '0';
        p_v     <= (others => '0');
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- readout FIFO (16 x 256) and 256 -> 128 bit output
  ---------------------------------------------------------------------------
  f_push <= '1' when rs = RS_HDR0 or rs = RS_HDR1 or p_v(2) = '1' else '0';
  f_din  <= hdr0 when rs = RS_HDR0 else
            hdr1 when rs = RS_HDR1 else
            r_data(p_ch(2));

  tvalid_i <= '1' when f_cnt /= 0 else '0';
  f_pop    <= tvalid_i and m_axis_tready and half;
  tlast_i  <= '1' when half = '1' and out_cnt = out_tot - 1 else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if f_push = '1' then
        fifo(to_integer(f_wp)) <= f_din;
        f_wp <= f_wp + 1;
      end if;
      if f_pop = '1' then
        f_rp <= f_rp + 1;
      end if;
      if f_push = '1' and f_pop = '0' then
        f_cnt <= f_cnt + 1;
      elsif f_push = '0' and f_pop = '1' then
        f_cnt <= f_cnt - 1;
      end if;

      if tvalid_i = '1' and m_axis_tready = '1' then
        half <= not half;
        if half = '1' then
          out_cnt <= out_cnt + 1;
        end if;
      end if;
      if rs = RS_IDLE then
        out_cnt <= (others => '0');
      end if;

      if rst = '1' or flush = '1' then
        f_wp  <= (others => '0');
        f_rp  <= (others => '0');
        f_cnt <= (others => '0');
        half  <= '0';
      end if;
    end if;
  end process;

  m_axis_tdata  <= fifo(to_integer(f_rp))(127 downto 0) when half = '0' else
                   fifo(to_integer(f_rp))(255 downto 128);
  m_axis_tkeep  <= (others => '1');
  m_axis_tvalid <= tvalid_i;
  m_axis_tlast  <= tlast_i;

  st_nfull     <= nfull;
  st_head      <= head;
  st_capturing <= capturing;
  st_rd_busy   <= rd_busy;
  st_prefilled <= '1' when active_valid = '1' and
                           din_cyc >= active_start + resize(cap_len_w(10 downto 1), CYC_W)
                  else '0';
  cnt_trig     <= trig_cnt;
  cnt_lost     <= lost_cnt;

end architecture rtl;
