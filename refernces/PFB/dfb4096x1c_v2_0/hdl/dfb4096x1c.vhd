-- Generated from Simulink block dfb4096x1c/c_to_ri
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_c_to_ri is
  port (
    c : in std_logic_vector( 36-1 downto 0 );
    re : out std_logic_vector( 18-1 downto 0 );
    im : out std_logic_vector( 18-1 downto 0 )
  );
end dfb4096x1c_c_to_ri;
architecture structural of dfb4096x1c_c_to_ri is 
  signal slice_im_y_net : std_logic_vector( 18-1 downto 0 );
  signal slice_re_y_net : std_logic_vector( 18-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal concat_y_net : std_logic_vector( 36-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
begin
  re <= force_re_output_port_net;
  im <= force_im_output_port_net;
  concat_y_net <= c;
  force_im : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_im_y_net,
    output_port => force_im_output_port_net
  );
  force_re : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_re_y_net,
    output_port => force_re_output_port_net
  );
  slice_im : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => concat_y_net,
    y => slice_im_y_net
  );
  slice_re : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 35,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => concat_y_net,
    y => slice_re_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/edge_detect
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_edge_detect is
  port (
    in_x0 : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    out_x0 : out std_logic_vector( 1-1 downto 0 )
  );
end dfb4096x1c_edge_detect;
architecture structural of dfb4096x1c_edge_detect is 
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal clk_net : std_logic;
  signal ce_net : std_logic;
  signal valid_net : std_logic_vector( 1-1 downto 0 );
  signal edge_op_y_net : std_logic_vector( 1-1 downto 0 );
  signal inverter_op_net : std_logic_vector( 1-1 downto 0 );
begin
  out_x0 <= edge_op_y_net;
  valid_net <= in_x0;
  clk_net <= clk_1;
  ce_net <= ce_1;
  delay : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 1,
    reg_retiming => 0,
    reset => 0,
    width => 1
  )
  port map (
    en => '1',
    rst => '1',
    d => valid_net,
    clk => clk_net,
    ce => ce_net,
    q => delay_q_net
  );
  inverter : entity xil_defaultlib.sysgen_inverter_c4865af945 
  port map (
    clr => '0',
    ip => valid_net,
    clk => clk_net,
    ce => ce_net,
    op => inverter_op_net
  );
  edge_op : entity xil_defaultlib.sysgen_logical_90282c0750 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    d0 => inverter_op_net,
    d1 => delay_q_net,
    y => edge_op_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/edge_detect1
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_edge_detect1 is
  port (
    in_x0 : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    out_x0 : out std_logic_vector( 1-1 downto 0 )
  );
end dfb4096x1c_edge_detect1;
architecture structural of dfb4096x1c_edge_detect1 is 
  signal inverter_op_net : std_logic_vector( 1-1 downto 0 );
  signal ce_net : std_logic;
  signal edge_op_y_net : std_logic_vector( 1-1 downto 0 );
  signal delay1_q_net : std_logic_vector( 1-1 downto 0 );
  signal clk_net : std_logic;
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
begin
  out_x0 <= edge_op_y_net;
  delay1_q_net <= in_x0;
  clk_net <= clk_1;
  ce_net <= ce_1;
  delay : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 1,
    reg_retiming => 0,
    reset => 0,
    width => 1
  )
  port map (
    en => '1',
    rst => '1',
    d => delay1_q_net,
    clk => clk_net,
    ce => ce_net,
    q => delay_q_net
  );
  inverter : entity xil_defaultlib.sysgen_inverter_c4865af945 
  port map (
    clr => '0',
    ip => delay1_q_net,
    clk => clk_net,
    ce => ce_net,
    op => inverter_op_net
  );
  edge_op : entity xil_defaultlib.sysgen_logical_90282c0750 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    d0 => inverter_op_net,
    d1 => delay_q_net,
    y => edge_op_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_coeffs
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_pol1_in1_coeffs is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    sync : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 );
    sync_out : out std_logic_vector( 1-1 downto 0 );
    coeff : out std_logic_vector( 72-1 downto 0 )
  );
end dfb4096x1c_pol1_in1_coeffs;
architecture structural of dfb4096x1c_pol1_in1_coeffs is 
  signal clk_net : std_logic;
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal reinterpret3_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal concat_y_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal counter_op_net : std_logic_vector( 12-1 downto 0 );
  signal register_q_net : std_logic_vector( 72-1 downto 0 );
  signal reinterpret1_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal concat_y_net : std_logic_vector( 72-1 downto 0 );
  signal ce_net : std_logic;
  signal delay1_q_net : std_logic_vector( 36-1 downto 0 );
  signal edge_op_y_net : std_logic_vector( 1-1 downto 0 );
  signal reinterpret2_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal reinterpret4_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal fan_delay2_q_net : std_logic_vector( 12-1 downto 0 );
  signal rom2_data_net : std_logic_vector( 18-1 downto 0 );
  signal rom1_data_net : std_logic_vector( 18-1 downto 0 );
  signal fan_delay1_q_net : std_logic_vector( 12-1 downto 0 );
  signal rom3_data_net : std_logic_vector( 18-1 downto 0 );
  signal fan_delay3_q_net : std_logic_vector( 12-1 downto 0 );
  signal fan_delay4_q_net : std_logic_vector( 12-1 downto 0 );
  signal rom4_data_net : std_logic_vector( 18-1 downto 0 );
begin
  dout <= delay1_q_net;
  sync_out <= delay_q_net;
  coeff <= register_q_net;
  concat_y_net_x0 <= din;
  edge_op_y_net <= sync;
  clk_net <= clk_1;
  ce_net <= ce_1;
  concat : entity xil_defaultlib.sysgen_concat_4b95defe99 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => reinterpret1_output_port_net,
    in1 => reinterpret2_output_port_net,
    in2 => reinterpret3_output_port_net,
    in3 => reinterpret4_output_port_net,
    y => concat_y_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_free 
  generic map (
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i0",
    op_arith => xlUnsigned,
    op_width => 12
  )
  port map (
    en => "1",
    clr => '0',
    rst => edge_op_y_net,
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  delay : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 5,
    reg_retiming => 0,
    reset => 0,
    width => 1
  )
  port map (
    en => '1',
    rst => '1',
    d => edge_op_y_net,
    clk => clk_net,
    ce => ce_net,
    q => delay_q_net
  );
  delay1 : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 5,
    reg_retiming => 0,
    reset => 0,
    width => 36
  )
  port map (
    en => '1',
    rst => '1',
    d => concat_y_net_x0,
    clk => clk_net,
    ce => ce_net,
    q => delay1_q_net
  );
  rom1 : entity xil_defaultlib.dfb4096x1c_xlsprom 
  generic map (
    c_address_width => 12,
    c_width => 18,
    core_name0 => "dfb4096x1c_blk_mem_gen_i0",
    latency => 1
  )
  port map (
    en => "1",
    rst => "0",
    addr => fan_delay1_q_net,
    clk => clk_net,
    ce => ce_net,
    data => rom1_data_net
  );
  rom2 : entity xil_defaultlib.dfb4096x1c_xlsprom 
  generic map (
    c_address_width => 12,
    c_width => 18,
    core_name0 => "dfb4096x1c_blk_mem_gen_i1",
    latency => 1
  )
  port map (
    en => "1",
    rst => "0",
    addr => fan_delay2_q_net,
    clk => clk_net,
    ce => ce_net,
    data => rom2_data_net
  );
  rom3 : entity xil_defaultlib.dfb4096x1c_xlsprom 
  generic map (
    c_address_width => 12,
    c_width => 18,
    core_name0 => "dfb4096x1c_blk_mem_gen_i2",
    latency => 1
  )
  port map (
    en => "1",
    rst => "0",
    addr => fan_delay3_q_net,
    clk => clk_net,
    ce => ce_net,
    data => rom3_data_net
  );
  rom4 : entity xil_defaultlib.dfb4096x1c_xlsprom 
  generic map (
    c_address_width => 12,
    c_width => 18,
    core_name0 => "dfb4096x1c_blk_mem_gen_i3",
    latency => 1
  )
  port map (
    en => "1",
    rst => "0",
    addr => fan_delay4_q_net,
    clk => clk_net,
    ce => ce_net,
    data => rom4_data_net
  );
  register_x0 : entity xil_defaultlib.dfb4096x1c_xlregister 
  generic map (
    d_width => 72,
    init_value => b"000000000000000000000000000000000000000000000000000000000000000000000000"
  )
  port map (
    en => "1",
    rst => "0",
    d => concat_y_net,
    clk => clk_net,
    ce => ce_net,
    q => register_q_net
  );
  reinterpret1 : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => rom1_data_net,
    output_port => reinterpret1_output_port_net
  );
  reinterpret2 : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => rom2_data_net,
    output_port => reinterpret2_output_port_net
  );
  reinterpret3 : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => rom3_data_net,
    output_port => reinterpret3_output_port_net
  );
  reinterpret4 : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => rom4_data_net,
    output_port => reinterpret4_output_port_net
  );
  fan_delay1 : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 2,
    reg_retiming => 0,
    reset => 0,
    width => 12
  )
  port map (
    en => '1',
    rst => '1',
    d => counter_op_net,
    clk => clk_net,
    ce => ce_net,
    q => fan_delay1_q_net
  );
  fan_delay2 : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 2,
    reg_retiming => 0,
    reset => 0,
    width => 12
  )
  port map (
    en => '1',
    rst => '1',
    d => counter_op_net,
    clk => clk_net,
    ce => ce_net,
    q => fan_delay2_q_net
  );
  fan_delay3 : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 2,
    reg_retiming => 0,
    reset => 0,
    width => 12
  )
  port map (
    en => '1',
    rst => '1',
    d => counter_op_net,
    clk => clk_net,
    ce => ce_net,
    q => fan_delay3_q_net
  );
  fan_delay4 : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 2,
    reg_retiming => 0,
    reset => 0,
    width => 12
  )
  port map (
    en => '1',
    rst => '1',
    d => counter_op_net,
    clk => clk_net,
    ce => ce_net,
    q => fan_delay4_q_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_first_tap/c_to_ri
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_c_to_ri_x0 is
  port (
    c : in std_logic_vector( 36-1 downto 0 );
    re : out std_logic_vector( 18-1 downto 0 );
    im : out std_logic_vector( 18-1 downto 0 )
  );
end dfb4096x1c_c_to_ri_x0;
architecture structural of dfb4096x1c_c_to_ri_x0 is 
  signal slice_re_y_net : std_logic_vector( 18-1 downto 0 );
  signal slice_im_y_net : std_logic_vector( 18-1 downto 0 );
  signal delay1_q_net : std_logic_vector( 36-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
begin
  re <= force_re_output_port_net;
  im <= force_im_output_port_net;
  delay1_q_net <= c;
  force_im : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_im_y_net,
    output_port => force_im_output_port_net
  );
  force_re : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_re_y_net,
    output_port => force_re_output_port_net
  );
  slice_im : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => delay1_q_net,
    y => slice_im_y_net
  );
  slice_re : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 35,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => delay1_q_net,
    y => slice_re_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_first_tap/delay_bram
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_delay_bram is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_delay_bram;
architecture structural of dfb4096x1c_delay_bram is 
  signal delay1_q_net : std_logic_vector( 36-1 downto 0 );
  signal clk_net : std_logic;
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal ce_net : std_logic;
  signal constant_op_net : std_logic_vector( 1-1 downto 0 );
  signal counter_op_net : std_logic_vector( 12-1 downto 0 );
begin
  dout <= ram_data_out_net;
  delay1_q_net <= din;
  clk_net <= clk_1;
  ce_net <= ce_1;
  constant_x0 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_limit 
  generic map (
    cnt_15_0 => 4093,
    cnt_31_16 => 0,
    cnt_47_32 => 0,
    cnt_63_48 => 0,
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i0",
    count_limited => 1,
    op_arith => xlUnsigned,
    op_width => 12
  )
  port map (
    en => "1",
    rst => "0",
    clr => '0',
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  ram : entity xil_defaultlib.dfb4096x1c_xlspram 
  generic map (
    c_address_width => 12,
    c_width => 36,
    core_name0 => "dfb4096x1c_blk_mem_gen_i4",
    latency => 1
  )
  port map (
    en => "1",
    rst => "0",
    addr => counter_op_net,
    data_in => delay1_q_net,
    we => constant_op_net,
    clk => clk_net,
    ce => ce_net,
    data_out => ram_data_out_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_first_tap/ri_to_c
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_ri_to_c is
  port (
    re : in std_logic_vector( 36-1 downto 0 );
    im : in std_logic_vector( 36-1 downto 0 );
    c : out std_logic_vector( 72-1 downto 0 )
  );
end dfb4096x1c_ri_to_c;
architecture structural of dfb4096x1c_ri_to_c is 
  signal reinterpret1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal reinterpret_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal concat_y_net : std_logic_vector( 72-1 downto 0 );
  signal mult_p_net : std_logic_vector( 36-1 downto 0 );
  signal mult1_p_net : std_logic_vector( 36-1 downto 0 );
begin
  c <= concat_y_net;
  mult1_p_net <= re;
  mult_p_net <= im;
  concat : entity xil_defaultlib.sysgen_concat_ce229e075a 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => reinterpret_output_port_net,
    in1 => reinterpret1_output_port_net,
    y => concat_y_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_c5d590c473 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => mult1_p_net,
    output_port => reinterpret_output_port_net
  );
  reinterpret1 : entity xil_defaultlib.sysgen_reinterpret_c5d590c473 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => mult_p_net,
    output_port => reinterpret1_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_first_tap/sync_delay
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_sync_delay is
  port (
    in_x0 : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    out_x0 : out std_logic_vector( 1-1 downto 0 )
  );
end dfb4096x1c_sync_delay;
architecture structural of dfb4096x1c_sync_delay is 
  signal mux_y_net : std_logic_vector( 1-1 downto 0 );
  signal ce_net : std_logic;
  signal clk_net : std_logic;
  signal constant_op_net : std_logic_vector( 13-1 downto 0 );
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal constant1_op_net : std_logic_vector( 13-1 downto 0 );
  signal constant2_op_net : std_logic_vector( 13-1 downto 0 );
  signal relational1_op_net : std_logic_vector( 1-1 downto 0 );
  signal counter_op_net : std_logic_vector( 13-1 downto 0 );
  signal relational_op_net : std_logic_vector( 1-1 downto 0 );
  signal logical_y_net : std_logic_vector( 1-1 downto 0 );
  signal constant3_op_net : std_logic_vector( 1-1 downto 0 );
begin
  out_x0 <= mux_y_net;
  delay_q_net <= in_x0;
  clk_net <= clk_1;
  ce_net <= ce_1;
  constant_x0 : entity xil_defaultlib.sysgen_constant_21d8d41224 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant_op_net
  );
  constant1 : entity xil_defaultlib.sysgen_constant_1d713ba862 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant1_op_net
  );
  constant2 : entity xil_defaultlib.sysgen_constant_55ad87220f 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant2_op_net
  );
  constant3 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant3_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_free 
  generic map (
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i1",
    op_arith => xlUnsigned,
    op_width => 13
  )
  port map (
    rst => "0",
    clr => '0',
    load => delay_q_net,
    din => constant2_op_net,
    en => logical_y_net,
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  logical : entity xil_defaultlib.sysgen_logical_3b5cca45a9 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    d0 => delay_q_net,
    d1 => relational1_op_net,
    y => logical_y_net
  );
  mux : entity xil_defaultlib.sysgen_mux_e3e3f25b52 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    sel => constant3_op_net,
    d0 => delay_q_net,
    d1 => relational_op_net,
    y => mux_y_net
  );
  relational : entity xil_defaultlib.sysgen_relational_e8dd3488d4 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    a => constant_op_net,
    b => counter_op_net,
    op => relational_op_net
  );
  relational1 : entity xil_defaultlib.sysgen_relational_a17fba53df 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    a => counter_op_net,
    b => constant1_op_net,
    op => relational1_op_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_first_tap
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_pol1_in1_first_tap is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    sync : in std_logic_vector( 1-1 downto 0 );
    coeffs : in std_logic_vector( 72-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 );
    sync_out : out std_logic_vector( 1-1 downto 0 );
    coeff_out : out std_logic_vector( 54-1 downto 0 );
    taps_out : out std_logic_vector( 72-1 downto 0 )
  );
end dfb4096x1c_pol1_in1_first_tap;
architecture structural of dfb4096x1c_pol1_in1_first_tap is 
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal delay1_q_net : std_logic_vector( 36-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal mux_y_net : std_logic_vector( 1-1 downto 0 );
  signal slice1_y_net : std_logic_vector( 54-1 downto 0 );
  signal concat_y_net : std_logic_vector( 72-1 downto 0 );
  signal mult1_p_net : std_logic_vector( 36-1 downto 0 );
  signal ce_net : std_logic;
  signal mult_p_net : std_logic_vector( 36-1 downto 0 );
  signal register_q_net : std_logic_vector( 72-1 downto 0 );
  signal clk_net : std_logic;
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal slice_y_net : std_logic_vector( 18-1 downto 0 );
  signal reinterpret_output_port_net : std_logic_vector( 18-1 downto 0 );
begin
  dout <= ram_data_out_net;
  sync_out <= mux_y_net;
  coeff_out <= slice1_y_net;
  taps_out <= concat_y_net;
  delay1_q_net <= din;
  delay_q_net <= sync;
  register_q_net <= coeffs;
  clk_net <= clk_1;
  ce_net <= ce_1;
  c_to_ri : entity xil_defaultlib.dfb4096x1c_c_to_ri_x0 
  port map (
    c => delay1_q_net,
    re => force_re_output_port_net,
    im => force_im_output_port_net
  );
  delay_bram : entity xil_defaultlib.dfb4096x1c_delay_bram 
  port map (
    din => delay1_q_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => ram_data_out_net
  );
  ri_to_c : entity xil_defaultlib.dfb4096x1c_ri_to_c 
  port map (
    re => mult1_p_net,
    im => mult_p_net,
    c => concat_y_net
  );
  sync_delay : entity xil_defaultlib.dfb4096x1c_sync_delay 
  port map (
    in_x0 => delay_q_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    out_x0 => mux_y_net
  );
  mult : entity xil_defaultlib.sysgen_mult_d469dda9e4 
  port map (
    clr => '0',
    a => force_im_output_port_net,
    b => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    p => mult_p_net
  );
  mult1 : entity xil_defaultlib.sysgen_mult_d469dda9e4 
  port map (
    clr => '0',
    a => force_re_output_port_net,
    b => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    p => mult1_p_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_y_net,
    output_port => reinterpret_output_port_net
  );
  slice : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 72,
    y_width => 18
  )
  port map (
    x => register_q_net,
    y => slice_y_net
  );
  slice1 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 71,
    x_width => 72,
    y_width => 54
  )
  port map (
    x => register_q_net,
    y => slice1_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_last_tap/c_to_ri
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_c_to_ri_x1 is
  port (
    c : in std_logic_vector( 36-1 downto 0 );
    re : out std_logic_vector( 18-1 downto 0 );
    im : out std_logic_vector( 18-1 downto 0 )
  );
end dfb4096x1c_c_to_ri_x1;
architecture structural of dfb4096x1c_c_to_ri_x1 is 
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal slice_re_y_net : std_logic_vector( 18-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal slice_im_y_net : std_logic_vector( 18-1 downto 0 );
begin
  re <= force_re_output_port_net;
  im <= force_im_output_port_net;
  ram_data_out_net <= c;
  force_im : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_im_y_net,
    output_port => force_im_output_port_net
  );
  force_re : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_re_y_net,
    output_port => force_re_output_port_net
  );
  slice_im : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => ram_data_out_net,
    y => slice_im_y_net
  );
  slice_re : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 35,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => ram_data_out_net,
    y => slice_re_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_last_tap/pfb_add_tree/adder_tree1
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_adder_tree1 is
  port (
    sync : in std_logic_vector( 1-1 downto 0 );
    din1 : in std_logic_vector( 36-1 downto 0 );
    din2 : in std_logic_vector( 36-1 downto 0 );
    din3 : in std_logic_vector( 36-1 downto 0 );
    din4 : in std_logic_vector( 36-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    sync_out : out std_logic_vector( 1-1 downto 0 );
    dout : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_adder_tree1;
architecture structural of dfb4096x1c_adder_tree1 is 
  signal clk_net : std_logic;
  signal ce_net : std_logic;
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal reint2_1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal addr3_s_net : std_logic_vector( 36-1 downto 0 );
  signal reint0_1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal reint1_1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal reint3_1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal sync_delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal addr2_s_net : std_logic_vector( 36-1 downto 0 );
  signal addr1_s_net : std_logic_vector( 36-1 downto 0 );
begin
  sync_out <= sync_delay_q_net;
  dout <= addr3_s_net;
  delay_q_net <= sync;
  reint0_1_output_port_net <= din1;
  reint1_1_output_port_net <= din2;
  reint2_1_output_port_net <= din3;
  reint3_1_output_port_net <= din4;
  clk_net <= clk_1;
  ce_net <= ce_1;
  addr1 : entity xil_defaultlib.dfb4096x1c_xladdsub 
  generic map (
    a_arith => xlSigned,
    a_bin_pt => 34,
    a_width => 36,
    b_arith => xlSigned,
    b_bin_pt => 34,
    b_width => 36,
    c_has_c_out => 0,
    c_latency => 1,
    c_output_width => 37,
    core_name0 => "dfb4096x1c_c_addsub_v12_0_i0",
    extra_registers => 1,
    full_s_arith => 2,
    full_s_width => 37,
    latency => 2,
    overflow => 1,
    quantization => 1,
    s_arith => xlSigned,
    s_bin_pt => 34,
    s_width => 36
  )
  port map (
    clr => '0',
    en => "1",
    a => reint0_1_output_port_net,
    b => reint1_1_output_port_net,
    clk => clk_net,
    ce => ce_net,
    s => addr1_s_net
  );
  addr2 : entity xil_defaultlib.dfb4096x1c_xladdsub 
  generic map (
    a_arith => xlSigned,
    a_bin_pt => 34,
    a_width => 36,
    b_arith => xlSigned,
    b_bin_pt => 34,
    b_width => 36,
    c_has_c_out => 0,
    c_latency => 1,
    c_output_width => 37,
    core_name0 => "dfb4096x1c_c_addsub_v12_0_i0",
    extra_registers => 1,
    full_s_arith => 2,
    full_s_width => 37,
    latency => 2,
    overflow => 1,
    quantization => 1,
    s_arith => xlSigned,
    s_bin_pt => 34,
    s_width => 36
  )
  port map (
    clr => '0',
    en => "1",
    a => reint2_1_output_port_net,
    b => reint3_1_output_port_net,
    clk => clk_net,
    ce => ce_net,
    s => addr2_s_net
  );
  addr3 : entity xil_defaultlib.dfb4096x1c_xladdsub 
  generic map (
    a_arith => xlSigned,
    a_bin_pt => 34,
    a_width => 36,
    b_arith => xlSigned,
    b_bin_pt => 34,
    b_width => 36,
    c_has_c_out => 0,
    c_latency => 1,
    c_output_width => 37,
    core_name0 => "dfb4096x1c_c_addsub_v12_0_i0",
    extra_registers => 1,
    full_s_arith => 2,
    full_s_width => 37,
    latency => 2,
    overflow => 1,
    quantization => 1,
    s_arith => xlSigned,
    s_bin_pt => 34,
    s_width => 36
  )
  port map (
    clr => '0',
    en => "1",
    a => addr1_s_net,
    b => addr2_s_net,
    clk => clk_net,
    ce => ce_net,
    s => addr3_s_net
  );
  sync_delay : entity xil_defaultlib.sysgen_delay_2657e6ac48 
  port map (
    clr => '0',
    d => delay_q_net,
    clk => clk_net,
    ce => ce_net,
    q => sync_delay_q_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_last_tap/pfb_add_tree/adder_tree2
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_adder_tree2 is
  port (
    sync : in std_logic_vector( 1-1 downto 0 );
    din1 : in std_logic_vector( 36-1 downto 0 );
    din2 : in std_logic_vector( 36-1 downto 0 );
    din3 : in std_logic_vector( 36-1 downto 0 );
    din4 : in std_logic_vector( 36-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_adder_tree2;
architecture structural of dfb4096x1c_adder_tree2 is 
  signal ce_net : std_logic;
  signal clk_net : std_logic;
  signal reint2_2_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal addr1_s_net : std_logic_vector( 36-1 downto 0 );
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal reint3_2_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal addr3_s_net : std_logic_vector( 36-1 downto 0 );
  signal reint0_2_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal addr2_s_net : std_logic_vector( 36-1 downto 0 );
  signal reint1_2_output_port_net : std_logic_vector( 36-1 downto 0 );
begin
  dout <= addr3_s_net;
  delay_q_net <= sync;
  reint0_2_output_port_net <= din1;
  reint1_2_output_port_net <= din2;
  reint2_2_output_port_net <= din3;
  reint3_2_output_port_net <= din4;
  clk_net <= clk_1;
  ce_net <= ce_1;
  addr1 : entity xil_defaultlib.dfb4096x1c_xladdsub 
  generic map (
    a_arith => xlSigned,
    a_bin_pt => 34,
    a_width => 36,
    b_arith => xlSigned,
    b_bin_pt => 34,
    b_width => 36,
    c_has_c_out => 0,
    c_latency => 1,
    c_output_width => 37,
    core_name0 => "dfb4096x1c_c_addsub_v12_0_i0",
    extra_registers => 1,
    full_s_arith => 2,
    full_s_width => 37,
    latency => 2,
    overflow => 1,
    quantization => 1,
    s_arith => xlSigned,
    s_bin_pt => 34,
    s_width => 36
  )
  port map (
    clr => '0',
    en => "1",
    a => reint0_2_output_port_net,
    b => reint1_2_output_port_net,
    clk => clk_net,
    ce => ce_net,
    s => addr1_s_net
  );
  addr2 : entity xil_defaultlib.dfb4096x1c_xladdsub 
  generic map (
    a_arith => xlSigned,
    a_bin_pt => 34,
    a_width => 36,
    b_arith => xlSigned,
    b_bin_pt => 34,
    b_width => 36,
    c_has_c_out => 0,
    c_latency => 1,
    c_output_width => 37,
    core_name0 => "dfb4096x1c_c_addsub_v12_0_i0",
    extra_registers => 1,
    full_s_arith => 2,
    full_s_width => 37,
    latency => 2,
    overflow => 1,
    quantization => 1,
    s_arith => xlSigned,
    s_bin_pt => 34,
    s_width => 36
  )
  port map (
    clr => '0',
    en => "1",
    a => reint2_2_output_port_net,
    b => reint3_2_output_port_net,
    clk => clk_net,
    ce => ce_net,
    s => addr2_s_net
  );
  addr3 : entity xil_defaultlib.dfb4096x1c_xladdsub 
  generic map (
    a_arith => xlSigned,
    a_bin_pt => 34,
    a_width => 36,
    b_arith => xlSigned,
    b_bin_pt => 34,
    b_width => 36,
    c_has_c_out => 0,
    c_latency => 1,
    c_output_width => 37,
    core_name0 => "dfb4096x1c_c_addsub_v12_0_i0",
    extra_registers => 1,
    full_s_arith => 2,
    full_s_width => 37,
    latency => 2,
    overflow => 1,
    quantization => 1,
    s_arith => xlSigned,
    s_bin_pt => 34,
    s_width => 36
  )
  port map (
    clr => '0',
    en => "1",
    a => addr1_s_net,
    b => addr2_s_net,
    clk => clk_net,
    ce => ce_net,
    s => addr3_s_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_last_tap/pfb_add_tree/ri_to_c
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_ri_to_c_x0 is
  port (
    re : in std_logic_vector( 18-1 downto 0 );
    im : in std_logic_vector( 18-1 downto 0 );
    c : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_ri_to_c_x0;
architecture structural of dfb4096x1c_ri_to_c_x0 is 
  signal convert2_dout_net : std_logic_vector( 18-1 downto 0 );
  signal concat_y_net : std_logic_vector( 36-1 downto 0 );
  signal convert1_dout_net : std_logic_vector( 18-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
begin
  c <= concat_y_net;
  convert1_dout_net <= re;
  convert2_dout_net <= im;
  concat : entity xil_defaultlib.sysgen_concat_e06ee35a33 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => force_re_output_port_net,
    in1 => force_im_output_port_net,
    y => concat_y_net
  );
  force_im : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => convert2_dout_net,
    output_port => force_im_output_port_net
  );
  force_re : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => convert1_dout_net,
    output_port => force_re_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_last_tap/pfb_add_tree
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_pfb_add_tree is
  port (
    din : in std_logic_vector( 288-1 downto 0 );
    sync : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 );
    sync_out : out std_logic_vector( 1-1 downto 0 )
  );
end dfb4096x1c_pfb_add_tree;
architecture structural of dfb4096x1c_pfb_add_tree is 
  signal slice1_2_y_net : std_logic_vector( 36-1 downto 0 );
  signal concat_y_net : std_logic_vector( 288-1 downto 0 );
  signal addr3_s_net : std_logic_vector( 36-1 downto 0 );
  signal reint0_1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal reint2_1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal slice0_2_y_net : std_logic_vector( 36-1 downto 0 );
  signal addr3_s_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal slice1_1_y_net : std_logic_vector( 36-1 downto 0 );
  signal ce_net : std_logic;
  signal clk_net : std_logic;
  signal reint1_2_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal reint2_2_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal reint0_2_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal sync_delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal convert1_dout_net : std_logic_vector( 18-1 downto 0 );
  signal reint3_2_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal convert2_dout_net : std_logic_vector( 18-1 downto 0 );
  signal reint1_1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal reint3_1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal delay1_q_net : std_logic_vector( 1-1 downto 0 );
  signal concat_y_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal slice0_1_y_net : std_logic_vector( 36-1 downto 0 );
  signal slice3_1_y_net : std_logic_vector( 36-1 downto 0 );
  signal scale1_op_net : std_logic_vector( 36-1 downto 0 );
  signal slice2_2_y_net : std_logic_vector( 36-1 downto 0 );
  signal slice2_1_y_net : std_logic_vector( 36-1 downto 0 );
  signal scale2_op_net : std_logic_vector( 36-1 downto 0 );
  signal slice3_2_y_net : std_logic_vector( 36-1 downto 0 );
begin
  dout <= concat_y_net_x0;
  sync_out <= delay1_q_net;
  concat_y_net <= din;
  delay_q_net <= sync;
  clk_net <= clk_1;
  ce_net <= ce_1;
  adder_tree1 : entity xil_defaultlib.dfb4096x1c_adder_tree1 
  port map (
    sync => delay_q_net,
    din1 => reint0_1_output_port_net,
    din2 => reint1_1_output_port_net,
    din3 => reint2_1_output_port_net,
    din4 => reint3_1_output_port_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    sync_out => sync_delay_q_net,
    dout => addr3_s_net
  );
  adder_tree2 : entity xil_defaultlib.dfb4096x1c_adder_tree2 
  port map (
    sync => delay_q_net,
    din1 => reint0_2_output_port_net,
    din2 => reint1_2_output_port_net,
    din3 => reint2_2_output_port_net,
    din4 => reint3_2_output_port_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => addr3_s_net_x0
  );
  ri_to_c : entity xil_defaultlib.dfb4096x1c_ri_to_c_x0 
  port map (
    re => convert1_dout_net,
    im => convert2_dout_net,
    c => concat_y_net_x0
  );
  reint0_1 : entity xil_defaultlib.sysgen_reinterpret_abcbde553c 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice0_1_y_net,
    output_port => reint0_1_output_port_net
  );
  reint0_2 : entity xil_defaultlib.sysgen_reinterpret_abcbde553c 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice0_2_y_net,
    output_port => reint0_2_output_port_net
  );
  reint1_1 : entity xil_defaultlib.sysgen_reinterpret_abcbde553c 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice1_1_y_net,
    output_port => reint1_1_output_port_net
  );
  reint1_2 : entity xil_defaultlib.sysgen_reinterpret_abcbde553c 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice1_2_y_net,
    output_port => reint1_2_output_port_net
  );
  reint2_1 : entity xil_defaultlib.sysgen_reinterpret_abcbde553c 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice2_1_y_net,
    output_port => reint2_1_output_port_net
  );
  reint2_2 : entity xil_defaultlib.sysgen_reinterpret_abcbde553c 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice2_2_y_net,
    output_port => reint2_2_output_port_net
  );
  reint3_1 : entity xil_defaultlib.sysgen_reinterpret_abcbde553c 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice3_1_y_net,
    output_port => reint3_1_output_port_net
  );
  reint3_2 : entity xil_defaultlib.sysgen_reinterpret_abcbde553c 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice3_2_y_net,
    output_port => reint3_2_output_port_net
  );
  slice0_1 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 252,
    new_msb => 287,
    x_width => 288,
    y_width => 36
  )
  port map (
    x => concat_y_net,
    y => slice0_1_y_net
  );
  slice0_2 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 216,
    new_msb => 251,
    x_width => 288,
    y_width => 36
  )
  port map (
    x => concat_y_net,
    y => slice0_2_y_net
  );
  slice1_1 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 180,
    new_msb => 215,
    x_width => 288,
    y_width => 36
  )
  port map (
    x => concat_y_net,
    y => slice1_1_y_net
  );
  slice1_2 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 144,
    new_msb => 179,
    x_width => 288,
    y_width => 36
  )
  port map (
    x => concat_y_net,
    y => slice1_2_y_net
  );
  slice2_1 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 108,
    new_msb => 143,
    x_width => 288,
    y_width => 36
  )
  port map (
    x => concat_y_net,
    y => slice2_1_y_net
  );
  slice2_2 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 72,
    new_msb => 107,
    x_width => 288,
    y_width => 36
  )
  port map (
    x => concat_y_net,
    y => slice2_2_y_net
  );
  slice3_1 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 36,
    new_msb => 71,
    x_width => 288,
    y_width => 36
  )
  port map (
    x => concat_y_net,
    y => slice3_1_y_net
  );
  slice3_2 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 35,
    x_width => 288,
    y_width => 36
  )
  port map (
    x => concat_y_net,
    y => slice3_2_y_net
  );
  convert1 : entity xil_defaultlib.dfb4096x1c_xlconvert_pipeline 
  generic map (
    bool_conversion => 0,
    din_arith => 2,
    din_bin_pt => 35,
    din_width => 36,
    dout_arith => 2,
    dout_bin_pt => 17,
    dout_width => 18,
    latency => 2,
    overflow => xlWrap,
    quantization => xlRoundBanker
  )
  port map (
    clr => '0',
    en => "1",
    din => scale1_op_net,
    clk => clk_net,
    ce => ce_net,
    dout => convert1_dout_net
  );
  convert2 : entity xil_defaultlib.dfb4096x1c_xlconvert 
  generic map (
    bool_conversion => 0,
    din_arith => 2,
    din_bin_pt => 35,
    din_width => 36,
    dout_arith => 2,
    dout_bin_pt => 17,
    dout_width => 18,
    latency => 2,
    overflow => xlWrap,
    quantization => xlRoundBanker
  )
  port map (
    clr => '0',
    en => "1",
    din => scale2_op_net,
    clk => clk_net,
    ce => ce_net,
    dout => convert2_dout_net
  );
  delay1 : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 2,
    reg_retiming => 0,
    reset => 0,
    width => 1
  )
  port map (
    en => '1',
    rst => '1',
    d => sync_delay_q_net,
    clk => clk_net,
    ce => ce_net,
    q => delay1_q_net
  );
  scale1 : entity xil_defaultlib.sysgen_scale_5d0459de9f 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    ip => addr3_s_net,
    op => scale1_op_net
  );
  scale2 : entity xil_defaultlib.sysgen_scale_5d0459de9f 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    ip => addr3_s_net_x0,
    op => scale2_op_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_last_tap/ri_to_c
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_ri_to_c_x1 is
  port (
    re : in std_logic_vector( 36-1 downto 0 );
    im : in std_logic_vector( 36-1 downto 0 );
    c : out std_logic_vector( 72-1 downto 0 )
  );
end dfb4096x1c_ri_to_c_x1;
architecture structural of dfb4096x1c_ri_to_c_x1 is 
  signal concat_y_net : std_logic_vector( 72-1 downto 0 );
  signal reinterpret1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal mult_p_net : std_logic_vector( 36-1 downto 0 );
  signal mult1_p_net : std_logic_vector( 36-1 downto 0 );
  signal reinterpret_output_port_net : std_logic_vector( 36-1 downto 0 );
begin
  c <= concat_y_net;
  mult1_p_net <= re;
  mult_p_net <= im;
  concat : entity xil_defaultlib.sysgen_concat_ce229e075a 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => reinterpret_output_port_net,
    in1 => reinterpret1_output_port_net,
    y => concat_y_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_c5d590c473 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => mult1_p_net,
    output_port => reinterpret_output_port_net
  );
  reinterpret1 : entity xil_defaultlib.sysgen_reinterpret_c5d590c473 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => mult_p_net,
    output_port => reinterpret1_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_last_tap
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_pol1_in1_last_tap is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    sync : in std_logic_vector( 1-1 downto 0 );
    coeff : in std_logic_vector( 18-1 downto 0 );
    taps : in std_logic_vector( 216-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 );
    sync_out : out std_logic_vector( 1-1 downto 0 )
  );
end dfb4096x1c_pol1_in1_last_tap;
architecture structural of dfb4096x1c_pol1_in1_last_tap is 
  signal concat_y_net_x1 : std_logic_vector( 36-1 downto 0 );
  signal mux_y_net : std_logic_vector( 1-1 downto 0 );
  signal concat_y_net_x2 : std_logic_vector( 288-1 downto 0 );
  signal mult1_p_net : std_logic_vector( 36-1 downto 0 );
  signal clk_net : std_logic;
  signal mult_p_net : std_logic_vector( 36-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal delay1_q_net : std_logic_vector( 1-1 downto 0 );
  signal concat_y_net : std_logic_vector( 216-1 downto 0 );
  signal concat_y_net_x0 : std_logic_vector( 72-1 downto 0 );
  signal slice1_y_net : std_logic_vector( 18-1 downto 0 );
  signal ce_net : std_logic;
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal reinterpret_output_port_net : std_logic_vector( 18-1 downto 0 );
begin
  dout <= concat_y_net_x1;
  sync_out <= delay1_q_net;
  ram_data_out_net <= din;
  mux_y_net <= sync;
  slice1_y_net <= coeff;
  concat_y_net <= taps;
  clk_net <= clk_1;
  ce_net <= ce_1;
  c_to_ri : entity xil_defaultlib.dfb4096x1c_c_to_ri_x1 
  port map (
    c => ram_data_out_net,
    re => force_re_output_port_net,
    im => force_im_output_port_net
  );
  pfb_add_tree : entity xil_defaultlib.dfb4096x1c_pfb_add_tree 
  port map (
    din => concat_y_net_x2,
    sync => delay_q_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => concat_y_net_x1,
    sync_out => delay1_q_net
  );
  ri_to_c : entity xil_defaultlib.dfb4096x1c_ri_to_c_x1 
  port map (
    re => mult1_p_net,
    im => mult_p_net,
    c => concat_y_net_x0
  );
  concat : entity xil_defaultlib.sysgen_concat_4c4034e106 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => concat_y_net_x0,
    in1 => concat_y_net,
    y => concat_y_net_x2
  );
  delay : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 3,
    reg_retiming => 0,
    reset => 0,
    width => 1
  )
  port map (
    en => '1',
    rst => '1',
    d => mux_y_net,
    clk => clk_net,
    ce => ce_net,
    q => delay_q_net
  );
  mult : entity xil_defaultlib.sysgen_mult_d469dda9e4 
  port map (
    clr => '0',
    a => force_im_output_port_net,
    b => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    p => mult_p_net
  );
  mult1 : entity xil_defaultlib.sysgen_mult_d469dda9e4 
  port map (
    clr => '0',
    a => force_re_output_port_net,
    b => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    p => mult1_p_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice1_y_net,
    output_port => reinterpret_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap2/c_to_ri
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_c_to_ri_x2 is
  port (
    c : in std_logic_vector( 36-1 downto 0 );
    re : out std_logic_vector( 18-1 downto 0 );
    im : out std_logic_vector( 18-1 downto 0 )
  );
end dfb4096x1c_c_to_ri_x2;
architecture structural of dfb4096x1c_c_to_ri_x2 is 
  signal slice_im_y_net : std_logic_vector( 18-1 downto 0 );
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal slice_re_y_net : std_logic_vector( 18-1 downto 0 );
begin
  re <= force_re_output_port_net;
  im <= force_im_output_port_net;
  ram_data_out_net <= c;
  force_im : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_im_y_net,
    output_port => force_im_output_port_net
  );
  force_re : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_re_y_net,
    output_port => force_re_output_port_net
  );
  slice_im : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => ram_data_out_net,
    y => slice_im_y_net
  );
  slice_re : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 35,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => ram_data_out_net,
    y => slice_re_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap2/delay_bram
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_delay_bram_x0 is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_delay_bram_x0;
architecture structural of dfb4096x1c_delay_bram_x0 is 
  signal constant_op_net : std_logic_vector( 1-1 downto 0 );
  signal clk_net : std_logic;
  signal ram_data_out_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal counter_op_net : std_logic_vector( 12-1 downto 0 );
  signal ce_net : std_logic;
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
begin
  dout <= ram_data_out_net;
  ram_data_out_net_x0 <= din;
  clk_net <= clk_1;
  ce_net <= ce_1;
  constant_x0 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_limit 
  generic map (
    cnt_15_0 => 4093,
    cnt_31_16 => 0,
    cnt_47_32 => 0,
    cnt_63_48 => 0,
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i0",
    count_limited => 1,
    op_arith => xlUnsigned,
    op_width => 12
  )
  port map (
    en => "1",
    rst => "0",
    clr => '0',
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  ram : entity xil_defaultlib.dfb4096x1c_xlspram 
  generic map (
    c_address_width => 12,
    c_width => 36,
    core_name0 => "dfb4096x1c_blk_mem_gen_i4",
    latency => 1
  )
  port map (
    en => "1",
    rst => "0",
    addr => counter_op_net,
    data_in => ram_data_out_net_x0,
    we => constant_op_net,
    clk => clk_net,
    ce => ce_net,
    data_out => ram_data_out_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap2/ri_to_c
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_ri_to_c_x2 is
  port (
    re : in std_logic_vector( 36-1 downto 0 );
    im : in std_logic_vector( 36-1 downto 0 );
    c : out std_logic_vector( 72-1 downto 0 )
  );
end dfb4096x1c_ri_to_c_x2;
architecture structural of dfb4096x1c_ri_to_c_x2 is 
  signal reinterpret_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal reinterpret1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal mult_p_net : std_logic_vector( 36-1 downto 0 );
  signal concat_y_net : std_logic_vector( 72-1 downto 0 );
  signal mult1_p_net : std_logic_vector( 36-1 downto 0 );
begin
  c <= concat_y_net;
  mult1_p_net <= re;
  mult_p_net <= im;
  concat : entity xil_defaultlib.sysgen_concat_ce229e075a 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => reinterpret_output_port_net,
    in1 => reinterpret1_output_port_net,
    y => concat_y_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_c5d590c473 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => mult1_p_net,
    output_port => reinterpret_output_port_net
  );
  reinterpret1 : entity xil_defaultlib.sysgen_reinterpret_c5d590c473 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => mult_p_net,
    output_port => reinterpret1_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap2/sync_delay
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_sync_delay_x0 is
  port (
    in_x0 : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    out_x0 : out std_logic_vector( 1-1 downto 0 )
  );
end dfb4096x1c_sync_delay_x0;
architecture structural of dfb4096x1c_sync_delay_x0 is 
  signal constant2_op_net : std_logic_vector( 13-1 downto 0 );
  signal constant_op_net : std_logic_vector( 13-1 downto 0 );
  signal mux_y_net : std_logic_vector( 1-1 downto 0 );
  signal clk_net : std_logic;
  signal ce_net : std_logic;
  signal counter_op_net : std_logic_vector( 13-1 downto 0 );
  signal constant3_op_net : std_logic_vector( 1-1 downto 0 );
  signal logical_y_net : std_logic_vector( 1-1 downto 0 );
  signal mux_y_net_x0 : std_logic_vector( 1-1 downto 0 );
  signal constant1_op_net : std_logic_vector( 13-1 downto 0 );
  signal relational1_op_net : std_logic_vector( 1-1 downto 0 );
  signal relational_op_net : std_logic_vector( 1-1 downto 0 );
begin
  out_x0 <= mux_y_net;
  mux_y_net_x0 <= in_x0;
  clk_net <= clk_1;
  ce_net <= ce_1;
  constant_x0 : entity xil_defaultlib.sysgen_constant_21d8d41224 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant_op_net
  );
  constant1 : entity xil_defaultlib.sysgen_constant_1d713ba862 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant1_op_net
  );
  constant2 : entity xil_defaultlib.sysgen_constant_55ad87220f 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant2_op_net
  );
  constant3 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant3_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_free 
  generic map (
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i1",
    op_arith => xlUnsigned,
    op_width => 13
  )
  port map (
    rst => "0",
    clr => '0',
    load => mux_y_net_x0,
    din => constant2_op_net,
    en => logical_y_net,
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  logical : entity xil_defaultlib.sysgen_logical_3b5cca45a9 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    d0 => mux_y_net_x0,
    d1 => relational1_op_net,
    y => logical_y_net
  );
  mux : entity xil_defaultlib.sysgen_mux_e3e3f25b52 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    sel => constant3_op_net,
    d0 => mux_y_net_x0,
    d1 => relational_op_net,
    y => mux_y_net
  );
  relational : entity xil_defaultlib.sysgen_relational_e8dd3488d4 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    a => constant_op_net,
    b => counter_op_net,
    op => relational_op_net
  );
  relational1 : entity xil_defaultlib.sysgen_relational_a17fba53df 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    a => counter_op_net,
    b => constant1_op_net,
    op => relational1_op_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap2
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_pol1_in1_tap2 is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    sync : in std_logic_vector( 1-1 downto 0 );
    coeff : in std_logic_vector( 54-1 downto 0 );
    taps : in std_logic_vector( 72-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 );
    sync_out : out std_logic_vector( 1-1 downto 0 );
    coeff_out : out std_logic_vector( 36-1 downto 0 );
    taps_out : out std_logic_vector( 144-1 downto 0 )
  );
end dfb4096x1c_pol1_in1_tap2;
architecture structural of dfb4096x1c_pol1_in1_tap2 is 
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal mux_y_net_x0 : std_logic_vector( 1-1 downto 0 );
  signal clk_net : std_logic;
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal slice1_y_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal ce_net : std_logic;
  signal concat_y_net : std_logic_vector( 144-1 downto 0 );
  signal reinterpret_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal ram_data_out_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal mux_y_net : std_logic_vector( 1-1 downto 0 );
  signal slice1_y_net : std_logic_vector( 54-1 downto 0 );
  signal concat_y_net_x0 : std_logic_vector( 72-1 downto 0 );
  signal concat_y_net_x1 : std_logic_vector( 72-1 downto 0 );
  signal mult1_p_net : std_logic_vector( 36-1 downto 0 );
  signal mult_p_net : std_logic_vector( 36-1 downto 0 );
  signal slice_y_net : std_logic_vector( 18-1 downto 0 );
begin
  dout <= ram_data_out_net_x0;
  sync_out <= mux_y_net_x0;
  coeff_out <= slice1_y_net_x0;
  taps_out <= concat_y_net;
  ram_data_out_net <= din;
  mux_y_net <= sync;
  slice1_y_net <= coeff;
  concat_y_net_x0 <= taps;
  clk_net <= clk_1;
  ce_net <= ce_1;
  c_to_ri : entity xil_defaultlib.dfb4096x1c_c_to_ri_x2 
  port map (
    c => ram_data_out_net,
    re => force_re_output_port_net,
    im => force_im_output_port_net
  );
  delay_bram : entity xil_defaultlib.dfb4096x1c_delay_bram_x0 
  port map (
    din => ram_data_out_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => ram_data_out_net_x0
  );
  ri_to_c : entity xil_defaultlib.dfb4096x1c_ri_to_c_x2 
  port map (
    re => mult1_p_net,
    im => mult_p_net,
    c => concat_y_net_x1
  );
  sync_delay : entity xil_defaultlib.dfb4096x1c_sync_delay_x0 
  port map (
    in_x0 => mux_y_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    out_x0 => mux_y_net_x0
  );
  concat : entity xil_defaultlib.sysgen_concat_93e1fe96b0 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => concat_y_net_x1,
    in1 => concat_y_net_x0,
    y => concat_y_net
  );
  mult : entity xil_defaultlib.sysgen_mult_d469dda9e4 
  port map (
    clr => '0',
    a => force_im_output_port_net,
    b => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    p => mult_p_net
  );
  mult1 : entity xil_defaultlib.sysgen_mult_d469dda9e4 
  port map (
    clr => '0',
    a => force_re_output_port_net,
    b => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    p => mult1_p_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_y_net,
    output_port => reinterpret_output_port_net
  );
  slice : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 54,
    y_width => 18
  )
  port map (
    x => slice1_y_net,
    y => slice_y_net
  );
  slice1 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 53,
    x_width => 54,
    y_width => 36
  )
  port map (
    x => slice1_y_net,
    y => slice1_y_net_x0
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap3/c_to_ri
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_c_to_ri_x3 is
  port (
    c : in std_logic_vector( 36-1 downto 0 );
    re : out std_logic_vector( 18-1 downto 0 );
    im : out std_logic_vector( 18-1 downto 0 )
  );
end dfb4096x1c_c_to_ri_x3;
architecture structural of dfb4096x1c_c_to_ri_x3 is 
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal slice_im_y_net : std_logic_vector( 18-1 downto 0 );
  signal slice_re_y_net : std_logic_vector( 18-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
begin
  re <= force_re_output_port_net;
  im <= force_im_output_port_net;
  ram_data_out_net <= c;
  force_im : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_im_y_net,
    output_port => force_im_output_port_net
  );
  force_re : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_re_y_net,
    output_port => force_re_output_port_net
  );
  slice_im : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => ram_data_out_net,
    y => slice_im_y_net
  );
  slice_re : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 35,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => ram_data_out_net,
    y => slice_re_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap3/delay_bram
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_delay_bram_x1 is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_delay_bram_x1;
architecture structural of dfb4096x1c_delay_bram_x1 is 
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal ram_data_out_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal clk_net : std_logic;
  signal ce_net : std_logic;
  signal counter_op_net : std_logic_vector( 12-1 downto 0 );
  signal constant_op_net : std_logic_vector( 1-1 downto 0 );
begin
  dout <= ram_data_out_net;
  ram_data_out_net_x0 <= din;
  clk_net <= clk_1;
  ce_net <= ce_1;
  constant_x0 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_limit 
  generic map (
    cnt_15_0 => 4093,
    cnt_31_16 => 0,
    cnt_47_32 => 0,
    cnt_63_48 => 0,
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i0",
    count_limited => 1,
    op_arith => xlUnsigned,
    op_width => 12
  )
  port map (
    en => "1",
    rst => "0",
    clr => '0',
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  ram : entity xil_defaultlib.dfb4096x1c_xlspram 
  generic map (
    c_address_width => 12,
    c_width => 36,
    core_name0 => "dfb4096x1c_blk_mem_gen_i4",
    latency => 1
  )
  port map (
    en => "1",
    rst => "0",
    addr => counter_op_net,
    data_in => ram_data_out_net_x0,
    we => constant_op_net,
    clk => clk_net,
    ce => ce_net,
    data_out => ram_data_out_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap3/ri_to_c
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_ri_to_c_x3 is
  port (
    re : in std_logic_vector( 36-1 downto 0 );
    im : in std_logic_vector( 36-1 downto 0 );
    c : out std_logic_vector( 72-1 downto 0 )
  );
end dfb4096x1c_ri_to_c_x3;
architecture structural of dfb4096x1c_ri_to_c_x3 is 
  signal reinterpret_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal mult_p_net : std_logic_vector( 36-1 downto 0 );
  signal mult1_p_net : std_logic_vector( 36-1 downto 0 );
  signal concat_y_net : std_logic_vector( 72-1 downto 0 );
  signal reinterpret1_output_port_net : std_logic_vector( 36-1 downto 0 );
begin
  c <= concat_y_net;
  mult1_p_net <= re;
  mult_p_net <= im;
  concat : entity xil_defaultlib.sysgen_concat_ce229e075a 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => reinterpret_output_port_net,
    in1 => reinterpret1_output_port_net,
    y => concat_y_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_c5d590c473 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => mult1_p_net,
    output_port => reinterpret_output_port_net
  );
  reinterpret1 : entity xil_defaultlib.sysgen_reinterpret_c5d590c473 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => mult_p_net,
    output_port => reinterpret1_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap3/sync_delay
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_sync_delay_x1 is
  port (
    in_x0 : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    out_x0 : out std_logic_vector( 1-1 downto 0 )
  );
end dfb4096x1c_sync_delay_x1;
architecture structural of dfb4096x1c_sync_delay_x1 is 
  signal counter_op_net : std_logic_vector( 13-1 downto 0 );
  signal mux_y_net : std_logic_vector( 1-1 downto 0 );
  signal ce_net : std_logic;
  signal clk_net : std_logic;
  signal constant_op_net : std_logic_vector( 13-1 downto 0 );
  signal constant2_op_net : std_logic_vector( 13-1 downto 0 );
  signal logical_y_net : std_logic_vector( 1-1 downto 0 );
  signal constant3_op_net : std_logic_vector( 1-1 downto 0 );
  signal constant1_op_net : std_logic_vector( 13-1 downto 0 );
  signal mux_y_net_x0 : std_logic_vector( 1-1 downto 0 );
  signal relational_op_net : std_logic_vector( 1-1 downto 0 );
  signal relational1_op_net : std_logic_vector( 1-1 downto 0 );
begin
  out_x0 <= mux_y_net;
  mux_y_net_x0 <= in_x0;
  clk_net <= clk_1;
  ce_net <= ce_1;
  constant_x0 : entity xil_defaultlib.sysgen_constant_21d8d41224 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant_op_net
  );
  constant1 : entity xil_defaultlib.sysgen_constant_1d713ba862 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant1_op_net
  );
  constant2 : entity xil_defaultlib.sysgen_constant_55ad87220f 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant2_op_net
  );
  constant3 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant3_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_free 
  generic map (
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i1",
    op_arith => xlUnsigned,
    op_width => 13
  )
  port map (
    rst => "0",
    clr => '0',
    load => mux_y_net_x0,
    din => constant2_op_net,
    en => logical_y_net,
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  logical : entity xil_defaultlib.sysgen_logical_3b5cca45a9 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    d0 => mux_y_net_x0,
    d1 => relational1_op_net,
    y => logical_y_net
  );
  mux : entity xil_defaultlib.sysgen_mux_e3e3f25b52 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    sel => constant3_op_net,
    d0 => mux_y_net_x0,
    d1 => relational_op_net,
    y => mux_y_net
  );
  relational : entity xil_defaultlib.sysgen_relational_e8dd3488d4 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    a => constant_op_net,
    b => counter_op_net,
    op => relational_op_net
  );
  relational1 : entity xil_defaultlib.sysgen_relational_a17fba53df 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    a => counter_op_net,
    b => constant1_op_net,
    op => relational1_op_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir/pol1_in1_tap3
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_pol1_in1_tap3 is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    sync : in std_logic_vector( 1-1 downto 0 );
    coeff : in std_logic_vector( 36-1 downto 0 );
    taps : in std_logic_vector( 144-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 36-1 downto 0 );
    sync_out : out std_logic_vector( 1-1 downto 0 );
    coeff_out : out std_logic_vector( 18-1 downto 0 );
    taps_out : out std_logic_vector( 216-1 downto 0 )
  );
end dfb4096x1c_pol1_in1_tap3;
architecture structural of dfb4096x1c_pol1_in1_tap3 is 
  signal concat_y_net_x0 : std_logic_vector( 144-1 downto 0 );
  signal mux_y_net_x0 : std_logic_vector( 1-1 downto 0 );
  signal slice1_y_net_x0 : std_logic_vector( 18-1 downto 0 );
  signal mult_p_net : std_logic_vector( 36-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal concat_y_net : std_logic_vector( 216-1 downto 0 );
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal ce_net : std_logic;
  signal ram_data_out_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal mux_y_net : std_logic_vector( 1-1 downto 0 );
  signal slice1_y_net : std_logic_vector( 36-1 downto 0 );
  signal clk_net : std_logic;
  signal concat_y_net_x1 : std_logic_vector( 72-1 downto 0 );
  signal mult1_p_net : std_logic_vector( 36-1 downto 0 );
  signal reinterpret_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal slice_y_net : std_logic_vector( 18-1 downto 0 );
begin
  dout <= ram_data_out_net_x0;
  sync_out <= mux_y_net_x0;
  coeff_out <= slice1_y_net_x0;
  taps_out <= concat_y_net;
  ram_data_out_net <= din;
  mux_y_net <= sync;
  slice1_y_net <= coeff;
  concat_y_net_x0 <= taps;
  clk_net <= clk_1;
  ce_net <= ce_1;
  c_to_ri : entity xil_defaultlib.dfb4096x1c_c_to_ri_x3 
  port map (
    c => ram_data_out_net,
    re => force_re_output_port_net,
    im => force_im_output_port_net
  );
  delay_bram : entity xil_defaultlib.dfb4096x1c_delay_bram_x1 
  port map (
    din => ram_data_out_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => ram_data_out_net_x0
  );
  ri_to_c : entity xil_defaultlib.dfb4096x1c_ri_to_c_x3 
  port map (
    re => mult1_p_net,
    im => mult_p_net,
    c => concat_y_net_x1
  );
  sync_delay : entity xil_defaultlib.dfb4096x1c_sync_delay_x1 
  port map (
    in_x0 => mux_y_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    out_x0 => mux_y_net_x0
  );
  concat : entity xil_defaultlib.sysgen_concat_4f7b6c034e 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => concat_y_net_x1,
    in1 => concat_y_net_x0,
    y => concat_y_net
  );
  mult : entity xil_defaultlib.sysgen_mult_d469dda9e4 
  port map (
    clr => '0',
    a => force_im_output_port_net,
    b => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    p => mult_p_net
  );
  mult1 : entity xil_defaultlib.sysgen_mult_d469dda9e4 
  port map (
    clr => '0',
    a => force_re_output_port_net,
    b => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    p => mult1_p_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_y_net,
    output_port => reinterpret_output_port_net
  );
  slice : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => slice1_y_net,
    y => slice_y_net
  );
  slice1 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 35,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => slice1_y_net,
    y => slice1_y_net_x0
  );
end structural;
-- Generated from Simulink block dfb4096x1c/pfb_fir
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_pfb_fir is
  port (
    sync : in std_logic_vector( 1-1 downto 0 );
    pol1_in1 : in std_logic_vector( 36-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    sync_out : out std_logic_vector( 1-1 downto 0 );
    pol1_out1 : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_pfb_fir;
architecture structural of dfb4096x1c_pfb_fir is 
  signal concat_y_net_x0 : std_logic_vector( 216-1 downto 0 );
  signal mux_y_net_x0 : std_logic_vector( 1-1 downto 0 );
  signal concat_y_net : std_logic_vector( 36-1 downto 0 );
  signal clk_net : std_logic;
  signal mux_y_net : std_logic_vector( 1-1 downto 0 );
  signal delay1_q_net : std_logic_vector( 1-1 downto 0 );
  signal slice1_y_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal concat_y_net_x1 : std_logic_vector( 144-1 downto 0 );
  signal register_q_net : std_logic_vector( 72-1 downto 0 );
  signal delay1_q_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal delay_q_net : std_logic_vector( 1-1 downto 0 );
  signal ram_data_out_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal concat_y_net_x3 : std_logic_vector( 72-1 downto 0 );
  signal slice1_y_net_x1 : std_logic_vector( 54-1 downto 0 );
  signal ram_data_out_net : std_logic_vector( 36-1 downto 0 );
  signal edge_op_y_net : std_logic_vector( 1-1 downto 0 );
  signal ram_data_out_net_x1 : std_logic_vector( 36-1 downto 0 );
  signal concat_y_net_x2 : std_logic_vector( 36-1 downto 0 );
  signal ce_net : std_logic;
  signal mux_y_net_x1 : std_logic_vector( 1-1 downto 0 );
  signal slice1_y_net : std_logic_vector( 18-1 downto 0 );
begin
  sync_out <= delay1_q_net;
  pol1_out1 <= concat_y_net_x2;
  edge_op_y_net <= sync;
  concat_y_net <= pol1_in1;
  clk_net <= clk_1;
  ce_net <= ce_1;
  pol1_in1_coeffs : entity xil_defaultlib.dfb4096x1c_pol1_in1_coeffs 
  port map (
    din => concat_y_net,
    sync => edge_op_y_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => delay1_q_net_x0,
    sync_out => delay_q_net,
    coeff => register_q_net
  );
  pol1_in1_first_tap : entity xil_defaultlib.dfb4096x1c_pol1_in1_first_tap 
  port map (
    din => delay1_q_net_x0,
    sync => delay_q_net,
    coeffs => register_q_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => ram_data_out_net_x1,
    sync_out => mux_y_net_x1,
    coeff_out => slice1_y_net_x1,
    taps_out => concat_y_net_x3
  );
  pol1_in1_last_tap : entity xil_defaultlib.dfb4096x1c_pol1_in1_last_tap 
  port map (
    din => ram_data_out_net,
    sync => mux_y_net,
    coeff => slice1_y_net,
    taps => concat_y_net_x0,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => concat_y_net_x2,
    sync_out => delay1_q_net
  );
  pol1_in1_tap2 : entity xil_defaultlib.dfb4096x1c_pol1_in1_tap2 
  port map (
    din => ram_data_out_net_x1,
    sync => mux_y_net_x1,
    coeff => slice1_y_net_x1,
    taps => concat_y_net_x3,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => ram_data_out_net_x0,
    sync_out => mux_y_net_x0,
    coeff_out => slice1_y_net_x0,
    taps_out => concat_y_net_x1
  );
  pol1_in1_tap3 : entity xil_defaultlib.dfb4096x1c_pol1_in1_tap3 
  port map (
    din => ram_data_out_net_x0,
    sync => mux_y_net_x0,
    coeff => slice1_y_net_x0,
    taps => concat_y_net_x1,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => ram_data_out_net,
    sync_out => mux_y_net,
    coeff_out => slice1_y_net,
    taps_out => concat_y_net_x0
  );
end structural;
-- Generated from Simulink block dfb4096x1c/power_dsp48e
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_power_dsp48e is
  port (
    c : in std_logic_vector( 36-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    p : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_power_dsp48e;
architecture structural of dfb4096x1c_power_dsp48e is 
  signal slice_real_y_net : std_logic_vector( 18-1 downto 0 );
  signal constant1_op_net : std_logic_vector( 4-1 downto 0 );
  signal reinterp_power_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal constant2_op_net : std_logic_vector( 4-1 downto 0 );
  signal clk_net : std_logic;
  signal ce_net : std_logic;
  signal constant3_op_net : std_logic_vector( 7-1 downto 0 );
  signal concat_y_net : std_logic_vector( 36-1 downto 0 );
  signal constant4_op_net : std_logic_vector( 3-1 downto 0 );
  signal convert4_dout_net : std_logic_vector( 18-1 downto 0 );
  signal constant5_op_net : std_logic_vector( 1-1 downto 0 );
  signal constant7_op_net : std_logic_vector( 3-1 downto 0 );
  signal constant6_op_net : std_logic_vector( 7-1 downto 0 );
  signal reinterp_imag_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal convert_dout_net : std_logic_vector( 30-1 downto 0 );
  signal reinterp_real_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal convert2_dout_net : std_logic_vector( 30-1 downto 0 );
  signal constant8_op_net : std_logic_vector( 1-1 downto 0 );
  signal convert3_dout_net : std_logic_vector( 18-1 downto 0 );
  signal slice_power_y_net : std_logic_vector( 36-1 downto 0 );
  signal slice_imag_y_net : std_logic_vector( 18-1 downto 0 );
  signal dsp48e_0_pcout_net : std_logic_vector( 48-1 downto 0 );
  signal dsp48e_0_p_net : std_logic_vector( 48-1 downto 0 );
  signal dsp48e_1_p_net : std_logic_vector( 48-1 downto 0 );
begin
  p <= reinterp_power_output_port_net;
  concat_y_net <= c;
  clk_net <= clk_1;
  ce_net <= ce_1;
  constant1 : entity xil_defaultlib.sysgen_constant_b9c3043202 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant1_op_net
  );
  constant2 : entity xil_defaultlib.sysgen_constant_b9c3043202 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant2_op_net
  );
  constant3 : entity xil_defaultlib.sysgen_constant_033a5513b2 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant3_op_net
  );
  constant4 : entity xil_defaultlib.sysgen_constant_50a8255018 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant4_op_net
  );
  constant5 : entity xil_defaultlib.sysgen_constant_e46dde62b8 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant5_op_net
  );
  constant6 : entity xil_defaultlib.sysgen_constant_e734df7e8b 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant6_op_net
  );
  constant7 : entity xil_defaultlib.sysgen_constant_50a8255018 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant7_op_net
  );
  constant8 : entity xil_defaultlib.sysgen_constant_e46dde62b8 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant8_op_net
  );
  convert : entity xil_defaultlib.dfb4096x1c_xlconvert 
  generic map (
    bool_conversion => 0,
    din_arith => 2,
    din_bin_pt => 0,
    din_width => 18,
    dout_arith => 2,
    dout_bin_pt => 0,
    dout_width => 30,
    latency => 0,
    overflow => xlWrap,
    quantization => xlTruncate
  )
  port map (
    clr => '0',
    en => "1",
    din => reinterp_real_output_port_net,
    clk => clk_net,
    ce => ce_net,
    dout => convert_dout_net
  );
  convert2 : entity xil_defaultlib.dfb4096x1c_xlconvert 
  generic map (
    bool_conversion => 0,
    din_arith => 2,
    din_bin_pt => 0,
    din_width => 18,
    dout_arith => 2,
    dout_bin_pt => 0,
    dout_width => 30,
    latency => 0,
    overflow => xlWrap,
    quantization => xlTruncate
  )
  port map (
    clr => '0',
    en => "1",
    din => reinterp_imag_output_port_net,
    clk => clk_net,
    ce => ce_net,
    dout => convert2_dout_net
  );
  convert3 : entity xil_defaultlib.dfb4096x1c_xlconvert 
  generic map (
    bool_conversion => 0,
    din_arith => 2,
    din_bin_pt => 0,
    din_width => 18,
    dout_arith => 2,
    dout_bin_pt => 0,
    dout_width => 18,
    latency => 0,
    overflow => xlWrap,
    quantization => xlTruncate
  )
  port map (
    clr => '0',
    en => "1",
    din => reinterp_real_output_port_net,
    clk => clk_net,
    ce => ce_net,
    dout => convert3_dout_net
  );
  convert4 : entity xil_defaultlib.dfb4096x1c_xlconvert 
  generic map (
    bool_conversion => 0,
    din_arith => 2,
    din_bin_pt => 0,
    din_width => 18,
    dout_arith => 2,
    dout_bin_pt => 0,
    dout_width => 18,
    latency => 0,
    overflow => xlWrap,
    quantization => xlTruncate
  )
  port map (
    clr => '0',
    en => "1",
    din => reinterp_imag_output_port_net,
    clk => clk_net,
    ce => ce_net,
    dout => convert4_dout_net
  );
  dsp48e_0 : entity xil_defaultlib.dfb4096x1c_xldsp48e 
  generic map (
    a_input => "DIRECT",
    acascreg => 1,
    alumodereg => 1,
    areg => 1,
    autoreset_pattern_detect => FALSE,
    autoreset_pattern_detect_optinv => "MATCH",
    b_input => "DIRECT",
    bcascreg => 1,
    breg => 1,
    carryinreg => 1,
    carryinselreg => 1,
    carryout_width => 4,
    creg => 0,
    mreg => 1,
    opmodereg => 1,
    preg => 1,
    sel_mask => "MASK",
    sel_pattern => "PATTERN",
    use_c_port => 0,
    use_mult => "MULT_S",
    use_op => 0,
    use_pattern_detect => "NO_PATDET",
    use_simd => "ONE48"
  )
  port map (
    en => "1",
    cea1 => "1",
    cea2 => "1",
    ceb1 => "1",
    ceb2 => "1",
    cec => "1",
    cem => "1",
    cealumode => "1",
    cemultcarryin => "1",
    cectrl => "1",
    cecarryin => "1",
    cep => "1",
    rst => "0",
    rsta => "0",
    rstb => "0",
    rstc => "0",
    rstm => "0",
    rstctrl => "0",
    rstcarryin => "0",
    rstalumode => "0",
    rstp => "0",
    a => convert2_dout_net,
    b => convert4_dout_net,
    opmode => constant6_op_net,
    alumode => constant1_op_net,
    carryin => constant8_op_net,
    carryinsel => constant7_op_net,
    clk => clk_net,
    ce => ce_net,
    p => dsp48e_0_p_net,
    pcout => dsp48e_0_pcout_net
  );
  dsp48e_1 : entity xil_defaultlib.dfb4096x1c_xldsp48e 
  generic map (
    a_input => "DIRECT",
    acascreg => 2,
    alumodereg => 1,
    areg => 2,
    autoreset_pattern_detect => FALSE,
    autoreset_pattern_detect_optinv => "MATCH",
    b_input => "DIRECT",
    bcascreg => 2,
    breg => 2,
    carryinreg => 1,
    carryinselreg => 1,
    carryout_width => 4,
    creg => 0,
    mreg => 1,
    opmodereg => 1,
    preg => 1,
    sel_mask => "MASK",
    sel_pattern => "PATTERN",
    use_c_port => 0,
    use_mult => "MULT_S",
    use_op => 0,
    use_pattern_detect => "NO_PATDET",
    use_simd => "ONE48"
  )
  port map (
    en => "1",
    cea1 => "1",
    cea2 => "1",
    ceb1 => "1",
    ceb2 => "1",
    cec => "1",
    cem => "1",
    cealumode => "1",
    cemultcarryin => "1",
    cectrl => "1",
    cecarryin => "1",
    cep => "1",
    rst => "0",
    rsta => "0",
    rstb => "0",
    rstc => "0",
    rstm => "0",
    rstctrl => "0",
    rstcarryin => "0",
    rstalumode => "0",
    rstp => "0",
    a => convert_dout_net,
    b => convert3_dout_net,
    pcin => dsp48e_0_pcout_net,
    opmode => constant3_op_net,
    alumode => constant2_op_net,
    carryin => constant5_op_net,
    carryinsel => constant4_op_net,
    clk => clk_net,
    ce => ce_net,
    p => dsp48e_1_p_net
  );
  reinterp_imag : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_imag_y_net,
    output_port => reinterp_imag_output_port_net
  );
  reinterp_power : entity xil_defaultlib.sysgen_reinterpret_e1948a914e 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_power_y_net,
    output_port => reinterp_power_output_port_net
  );
  reinterp_real : entity xil_defaultlib.sysgen_reinterpret_57b295c8f5 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice_real_y_net,
    output_port => reinterp_real_output_port_net
  );
  slice_imag : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 17,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => concat_y_net,
    y => slice_imag_y_net
  );
  slice_power : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 35,
    x_width => 48,
    y_width => 36
  )
  port map (
    x => dsp48e_1_p_net,
    y => slice_power_y_net
  );
  slice_real : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 18,
    new_msb => 35,
    x_width => 36,
    y_width => 18
  )
  port map (
    x => concat_y_net,
    y => slice_real_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/ri_to_c
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_ri_to_c_x4 is
  port (
    re : in std_logic_vector( 18-1 downto 0 );
    im : in std_logic_vector( 18-1 downto 0 );
    c : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_ri_to_c_x4;
architecture structural of dfb4096x1c_ri_to_c_x4 is 
  signal in_re_net : std_logic_vector( 18-1 downto 0 );
  signal concat_y_net : std_logic_vector( 36-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal in_im_net : std_logic_vector( 18-1 downto 0 );
begin
  c <= concat_y_net;
  in_re_net <= re;
  in_im_net <= im;
  concat : entity xil_defaultlib.sysgen_concat_e06ee35a33 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => force_re_output_port_net,
    in1 => force_im_output_port_net,
    y => concat_y_net
  );
  force_im : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => in_im_net,
    output_port => force_im_output_port_net
  );
  force_re : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => in_re_net,
    output_port => force_re_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/ri_to_c1
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_ri_to_c1 is
  port (
    re : in std_logic_vector( 18-1 downto 0 );
    im : in std_logic_vector( 18-1 downto 0 );
    c : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_ri_to_c1;
architecture structural of dfb4096x1c_ri_to_c1 is 
  signal concat_y_net : std_logic_vector( 36-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal fast_fourier_transform_9_1_m_axis_data_tdata_xn_im_0_net : std_logic_vector( 18-1 downto 0 );
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal fast_fourier_transform_9_1_m_axis_data_tdata_xn_re_0_net : std_logic_vector( 18-1 downto 0 );
begin
  c <= concat_y_net;
  fast_fourier_transform_9_1_m_axis_data_tdata_xn_re_0_net <= re;
  fast_fourier_transform_9_1_m_axis_data_tdata_xn_im_0_net <= im;
  concat : entity xil_defaultlib.sysgen_concat_e06ee35a33 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    in0 => force_re_output_port_net,
    in1 => force_im_output_port_net,
    y => concat_y_net
  );
  force_im : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => fast_fourier_transform_9_1_m_axis_data_tdata_xn_im_0_net,
    output_port => force_im_output_port_net
  );
  force_re : entity xil_defaultlib.sysgen_reinterpret_79bea74b70 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => fast_fourier_transform_9_1_m_axis_data_tdata_xn_re_0_net,
    output_port => force_re_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/vacc/Cram
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_cram is
  port (
    in1 : in std_logic_vector( 64-1 downto 0 );
    out_x0 : out std_logic_vector( 64-1 downto 0 )
  );
end dfb4096x1c_cram;
architecture structural of dfb4096x1c_cram is 
  signal reinterp1_output_port_net : std_logic_vector( 64-1 downto 0 );
  signal adder_s_net : std_logic_vector( 64-1 downto 0 );
begin
  out_x0 <= reinterp1_output_port_net;
  adder_s_net <= in1;
  reinterp1 : entity xil_defaultlib.sysgen_reinterpret_21d94dbe18 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => adder_s_net,
    output_port => reinterp1_output_port_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/vacc/Uncram
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_uncram is
  port (
    in_x0 : in std_logic_vector( 36-1 downto 0 );
    out1 : out std_logic_vector( 36-1 downto 0 )
  );
end dfb4096x1c_uncram;
architecture structural of dfb4096x1c_uncram is 
  signal dindelay_q_net : std_logic_vector( 36-1 downto 0 );
  signal reinterp1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal slice1_y_net : std_logic_vector( 36-1 downto 0 );
begin
  out1 <= reinterp1_output_port_net;
  dindelay_q_net <= in_x0;
  reinterp1 : entity xil_defaultlib.sysgen_reinterpret_e1948a914e 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => slice1_y_net,
    output_port => reinterp1_output_port_net
  );
  slice1 : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 35,
    x_width => 36,
    y_width => 36
  )
  port map (
    x => dindelay_q_net,
    y => slice1_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/vacc/vacc_core1
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_vacc_core1 is
  port (
    din : in std_logic_vector( 36-1 downto 0 );
    acc_en : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    dout : out std_logic_vector( 64-1 downto 0 )
  );
end dfb4096x1c_vacc_core1;
architecture structural of dfb4096x1c_vacc_core1 is 
  signal constant_op_net : std_logic_vector( 1-1 downto 0 );
  signal bram_data_out_net : std_logic_vector( 64-1 downto 0 );
  signal ce_net : std_logic;
  signal clk_net : std_logic;
  signal accencompare_op_net : std_logic_vector( 1-1 downto 0 );
  signal adder_s_net : std_logic_vector( 64-1 downto 0 );
  signal mux_y_net : std_logic_vector( 64-1 downto 0 );
  signal constant2_op_net : std_logic_vector( 1-1 downto 0 );
  signal reinterp1_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal counter_op_net : std_logic_vector( 12-1 downto 0 );
begin
  dout <= adder_s_net;
  reinterp1_output_port_net <= din;
  accencompare_op_net <= acc_en;
  clk_net <= clk_1;
  ce_net <= ce_1;
  adder : entity xil_defaultlib.sysgen_addsub_38c9f7fe09 
  port map (
    clr => '0',
    a => reinterp1_output_port_net,
    b => mux_y_net,
    clk => clk_net,
    ce => ce_net,
    s => adder_s_net
  );
  bram : entity xil_defaultlib.dfb4096x1c_xlspram 
  generic map (
    c_address_width => 12,
    c_width => 64,
    core_name0 => "dfb4096x1c_blk_mem_gen_i5",
    latency => 2
  )
  port map (
    en => "1",
    rst => "0",
    addr => counter_op_net,
    data_in => adder_s_net,
    we => constant2_op_net,
    clk => clk_net,
    ce => ce_net,
    data_out => bram_data_out_net
  );
  constant_x0 : entity xil_defaultlib.sysgen_constant_e46dde62b8 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant_op_net
  );
  constant2 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant2_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_limit 
  generic map (
    cnt_15_0 => 4087,
    cnt_31_16 => 0,
    cnt_47_32 => 0,
    cnt_63_48 => 0,
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i0",
    count_limited => 1,
    op_arith => xlUnsigned,
    op_width => 12
  )
  port map (
    en => "1",
    rst => "0",
    clr => '0',
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  mux : entity xil_defaultlib.sysgen_mux_3e19badf3f 
  port map (
    clr => '0',
    sel => accencompare_op_net,
    d0 => constant_op_net,
    d1 => bram_data_out_net,
    clk => clk_net,
    ce => ce_net,
    y => mux_y_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c/vacc
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_vacc is
  port (
    sync : in std_logic_vector( 1-1 downto 0 );
    din : in std_logic_vector( 36-1 downto 0 );
    acc_len : in std_logic_vector( 32-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    valid : out std_logic_vector( 1-1 downto 0 );
    dout : out std_logic_vector( 64-1 downto 0 )
  );
end dfb4096x1c_vacc;
architecture structural of dfb4096x1c_vacc is 
  signal clk_net : std_logic;
  signal dindelay_q_net : std_logic_vector( 36-1 downto 0 );
  signal ce_net : std_logic;
  signal slice_y_net : std_logic_vector( 32-1 downto 0 );
  signal reinterp1_output_port_net : std_logic_vector( 64-1 downto 0 );
  signal validdelay_q_net : std_logic_vector( 1-1 downto 0 );
  signal reinterpret_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal syncdelay_q_net : std_logic_vector( 1-1 downto 0 );
  signal synccompare_op_net : std_logic_vector( 1-1 downto 0 );
  signal adder_s_net : std_logic_vector( 64-1 downto 0 );
  signal edge_op_y_net : std_logic_vector( 1-1 downto 0 );
  signal accencompare_op_net : std_logic_vector( 1-1 downto 0 );
  signal zero_op_net : std_logic_vector( 8-1 downto 0 );
  signal reinterp1_output_port_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal and_y_net : std_logic_vector( 1-1 downto 0 );
  signal validcompare_op_net : std_logic_vector( 1-1 downto 0 );
  signal or_y_net : std_logic_vector( 1-1 downto 0 );
  signal acc_len_net : std_logic_vector( 32-1 downto 0 );
  signal counter_op_net : std_logic_vector( 44-1 downto 0 );
  signal syncconst_op_net : std_logic_vector( 12-1 downto 0 );
  signal slicelow_y_net : std_logic_vector( 12-1 downto 0 );
begin
  valid <= validdelay_q_net;
  dout <= reinterp1_output_port_net;
  edge_op_y_net <= sync;
  reinterpret_output_port_net <= din;
  acc_len_net <= acc_len;
  clk_net <= clk_1;
  ce_net <= ce_1;
  cram : entity xil_defaultlib.dfb4096x1c_cram 
  port map (
    in1 => adder_s_net,
    out_x0 => reinterp1_output_port_net
  );
  uncram : entity xil_defaultlib.dfb4096x1c_uncram 
  port map (
    in_x0 => dindelay_q_net,
    out1 => reinterp1_output_port_net_x0
  );
  vacc_core1 : entity xil_defaultlib.dfb4096x1c_vacc_core1 
  port map (
    din => reinterp1_output_port_net_x0,
    acc_en => accencompare_op_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    dout => adder_s_net
  );
  and_x0 : entity xil_defaultlib.sysgen_logical_cf4e873cb4 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    d0 => validcompare_op_net,
    d1 => synccompare_op_net,
    y => and_y_net
  );
  accencompare : entity xil_defaultlib.sysgen_relational_b64a210c95 
  port map (
    clr => '0',
    a => slice_y_net,
    b => zero_op_net,
    clk => clk_net,
    ce => ce_net,
    op => accencompare_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_free 
  generic map (
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i2",
    op_arith => xlUnsigned,
    op_width => 44
  )
  port map (
    en => "1",
    clr => '0',
    rst => or_y_net,
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  dindelay : entity xil_defaultlib.sysgen_delay_0b44b0be1e 
  port map (
    clr => '0',
    d => reinterpret_output_port_net,
    clk => clk_net,
    ce => ce_net,
    q => dindelay_q_net
  );
  or_x0 : entity xil_defaultlib.sysgen_logical_3b5cca45a9 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    d0 => syncdelay_q_net,
    d1 => and_y_net,
    y => or_y_net
  );
  slice : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 12,
    new_msb => 43,
    x_width => 44,
    y_width => 32
  )
  port map (
    x => counter_op_net,
    y => slice_y_net
  );
  slicelow : entity xil_defaultlib.dfb4096x1c_xlslice 
  generic map (
    new_lsb => 0,
    new_msb => 11,
    x_width => 44,
    y_width => 12
  )
  port map (
    x => counter_op_net,
    y => slicelow_y_net
  );
  synccompare : entity xil_defaultlib.sysgen_relational_834b22a171 
  port map (
    clr => '0',
    a => slicelow_y_net,
    b => syncconst_op_net,
    clk => clk_net,
    ce => ce_net,
    op => synccompare_op_net
  );
  syncconst : entity xil_defaultlib.sysgen_constant_f8237bcd95 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => syncconst_op_net
  );
  syncdelay : entity xil_defaultlib.sysgen_delay_00fe4c8180 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    d => edge_op_y_net,
    q => syncdelay_q_net
  );
  validcompare : entity xil_defaultlib.sysgen_relational_4c9fe83120 
  port map (
    clr => '0',
    a => acc_len_net,
    b => slice_y_net,
    clk => clk_net,
    ce => ce_net,
    op => validcompare_op_net
  );
  validdelay : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 5,
    reg_retiming => 0,
    reset => 0,
    width => 1
  )
  port map (
    en => '1',
    rst => '1',
    d => validcompare_op_net,
    clk => clk_net,
    ce => ce_net,
    q => validdelay_q_net
  );
  zero : entity xil_defaultlib.sysgen_constant_67dab248fc 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => zero_op_net
  );
end structural;
-- Generated from Simulink block dfb4096x1c_struct
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_struct is
  port (
    acc_len : in std_logic_vector( 32-1 downto 0 );
    in_im : in std_logic_vector( 18-1 downto 0 );
    in_re : in std_logic_vector( 18-1 downto 0 );
    valid : in std_logic_vector( 1-1 downto 0 );
    clk_1 : in std_logic;
    ce_1 : in std_logic;
    new_acc_out : out std_logic_vector( 1-1 downto 0 );
    spec_data_out : out std_logic_vector( 64-1 downto 0 );
    vacc_ram_addr : out std_logic_vector( 12-1 downto 0 )
  );
end dfb4096x1c_struct;
architecture structural of dfb4096x1c_struct is 
  signal register1_q_net : std_logic_vector( 36-1 downto 0 );
  signal fast_fourier_transform_9_1_m_axis_data_tvalid_net : std_logic_vector( 1-1 downto 0 );
  signal constant2_op_net : std_logic_vector( 1-1 downto 0 );
  signal constant4_op_net : std_logic_vector( 1-1 downto 0 );
  signal register_q_net : std_logic_vector( 1-1 downto 0 );
  signal inverter1_op_net : std_logic_vector( 1-1 downto 0 );
  signal validdelay_q_net : std_logic_vector( 1-1 downto 0 );
  signal valid_net : std_logic_vector( 1-1 downto 0 );
  signal in_im_net : std_logic_vector( 18-1 downto 0 );
  signal in_re_net : std_logic_vector( 18-1 downto 0 );
  signal acc_len_net : std_logic_vector( 32-1 downto 0 );
  signal reinterp1_output_port_net : std_logic_vector( 64-1 downto 0 );
  signal counter_op_net : std_logic_vector( 12-1 downto 0 );
  signal force_im_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal concat_y_net : std_logic_vector( 36-1 downto 0 );
  signal edge_op_y_net_x0 : std_logic_vector( 1-1 downto 0 );
  signal edge_op_y_net : std_logic_vector( 1-1 downto 0 );
  signal clk_net : std_logic;
  signal force_re_output_port_net : std_logic_vector( 18-1 downto 0 );
  signal delay1_q_net_x0 : std_logic_vector( 1-1 downto 0 );
  signal concat_y_net_x1 : std_logic_vector( 36-1 downto 0 );
  signal reinterp_power_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal concat_y_net_x0 : std_logic_vector( 36-1 downto 0 );
  signal fast_fourier_transform_9_1_m_axis_data_tdata_xn_re_0_net : std_logic_vector( 18-1 downto 0 );
  signal fast_fourier_transform_9_1_m_axis_data_tdata_xn_im_0_net : std_logic_vector( 18-1 downto 0 );
  signal delay1_q_net : std_logic_vector( 1-1 downto 0 );
  signal ce_net : std_logic;
  signal reinterpret_output_port_net : std_logic_vector( 36-1 downto 0 );
  signal constant_op_net : std_logic_vector( 1-1 downto 0 );
  signal constant1_op_net : std_logic_vector( 12-1 downto 0 );
  signal fast_fourier_transform_9_1_event_data_in_channel_halt_net : std_logic;
  signal fast_fourier_transform_9_1_event_frame_started_net : std_logic;
  signal fast_fourier_transform_9_1_m_axis_data_tuser_xk_index_net : std_logic_vector( 12-1 downto 0 );
  signal fast_fourier_transform_9_1_event_tlast_missing_net : std_logic;
  signal fast_fourier_transform_9_1_s_axis_data_tready_net : std_logic;
  signal fast_fourier_transform_9_1_m_axis_data_tlast_net : std_logic;
  signal fast_fourier_transform_9_1_event_tlast_unexpected_net : std_logic;
  signal fast_fourier_transform_9_1_s_axis_config_tready_net : std_logic;
begin
  acc_len_net <= acc_len;
  in_im_net <= in_im;
  in_re_net <= in_re;
  new_acc_out <= validdelay_q_net;
  spec_data_out <= reinterp1_output_port_net;
  vacc_ram_addr <= counter_op_net;
  valid_net <= valid;
  clk_net <= clk_1;
  ce_net <= ce_1;
  c_to_ri : entity xil_defaultlib.dfb4096x1c_c_to_ri 
  port map (
    c => concat_y_net,
    re => force_re_output_port_net,
    im => force_im_output_port_net
  );
  edge_detect : entity xil_defaultlib.dfb4096x1c_edge_detect 
  port map (
    in_x0 => valid_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    out_x0 => edge_op_y_net_x0
  );
  edge_detect1 : entity xil_defaultlib.dfb4096x1c_edge_detect1 
  port map (
    in_x0 => delay1_q_net_x0,
    clk_1 => clk_net,
    ce_1 => ce_net,
    out_x0 => edge_op_y_net
  );
  pfb_fir : entity xil_defaultlib.dfb4096x1c_pfb_fir 
  port map (
    sync => edge_op_y_net_x0,
    pol1_in1 => concat_y_net_x1,
    clk_1 => clk_net,
    ce_1 => ce_net,
    sync_out => delay1_q_net,
    pol1_out1 => concat_y_net
  );
  power_dsp48e : entity xil_defaultlib.dfb4096x1c_power_dsp48e 
  port map (
    c => concat_y_net_x0,
    clk_1 => clk_net,
    ce_1 => ce_net,
    p => reinterp_power_output_port_net
  );
  ri_to_c : entity xil_defaultlib.dfb4096x1c_ri_to_c_x4 
  port map (
    re => in_re_net,
    im => in_im_net,
    c => concat_y_net_x1
  );
  ri_to_c1 : entity xil_defaultlib.dfb4096x1c_ri_to_c1 
  port map (
    re => fast_fourier_transform_9_1_m_axis_data_tdata_xn_re_0_net,
    im => fast_fourier_transform_9_1_m_axis_data_tdata_xn_im_0_net,
    c => concat_y_net_x0
  );
  vacc : entity xil_defaultlib.dfb4096x1c_vacc 
  port map (
    sync => edge_op_y_net,
    din => reinterpret_output_port_net,
    acc_len => acc_len_net,
    clk_1 => clk_net,
    ce_1 => ce_net,
    valid => validdelay_q_net,
    dout => reinterp1_output_port_net
  );
  constant_x0 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant_op_net
  );
  constant1 : entity xil_defaultlib.sysgen_constant_b2880ab933 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant1_op_net
  );
  constant2 : entity xil_defaultlib.sysgen_constant_f19b4c04f3 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant2_op_net
  );
  constant4 : entity xil_defaultlib.sysgen_constant_e46dde62b8 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    op => constant4_op_net
  );
  counter : entity xil_defaultlib.dfb4096x1c_xlcounter_free 
  generic map (
    core_name0 => "dfb4096x1c_c_counter_binary_v12_0_i0",
    op_arith => xlUnsigned,
    op_width => 12
  )
  port map (
    clr => '0',
    rst => inverter1_op_net,
    en => validdelay_q_net,
    clk => clk_net,
    ce => ce_net,
    op => counter_op_net
  );
  delay1 : entity xil_defaultlib.dfb4096x1c_xldelay 
  generic map (
    latency => 4,
    reg_retiming => 0,
    reset => 0,
    width => 1
  )
  port map (
    en => '1',
    rst => '1',
    d => fast_fourier_transform_9_1_m_axis_data_tvalid_net,
    clk => clk_net,
    ce => ce_net,
    q => delay1_q_net_x0
  );
  inverter1 : entity xil_defaultlib.sysgen_inverter_c4865af945 
  port map (
    clr => '0',
    ip => validdelay_q_net,
    clk => clk_net,
    ce => ce_net,
    op => inverter1_op_net
  );
  register_x0 : entity xil_defaultlib.dfb4096x1c_xlregister 
  generic map (
    d_width => 1,
    init_value => b"0"
  )
  port map (
    d => constant2_op_net,
    rst => edge_op_y_net_x0,
    en => delay1_q_net,
    clk => clk_net,
    ce => ce_net,
    q => register_q_net
  );
  register1 : entity xil_defaultlib.dfb4096x1c_xlregister 
  generic map (
    d_width => 36,
    init_value => b"000000000000000000000000000000000000"
  )
  port map (
    en => "1",
    rst => "0",
    d => reinterp_power_output_port_net,
    clk => clk_net,
    ce => ce_net,
    q => register1_q_net
  );
  reinterpret : entity xil_defaultlib.sysgen_reinterpret_e1948a914e 
  port map (
    clk => '0',
    ce => '0',
    clr => '0',
    input_port => register1_q_net,
    output_port => reinterpret_output_port_net
  );
  fast_fourier_transform_9_1 : entity xil_defaultlib.xlfast_fourier_transform_5ecb86f1d5416778e3c4335beeaa3ff6 
  port map (
    s_axis_config_tdata_scale_sch => constant1_op_net,
    s_axis_config_tdata_fwd_inv => constant_op_net,
    s_axis_config_tvalid => edge_op_y_net_x0(0),
    s_axis_data_tdata_xn_im_0 => force_im_output_port_net,
    s_axis_data_tdata_xn_re_0 => force_re_output_port_net,
    s_axis_data_tvalid => register_q_net(0),
    s_axis_data_tlast => constant4_op_net(0),
    clk => clk_net,
    ce => ce_net,
    s_axis_config_tready => fast_fourier_transform_9_1_s_axis_config_tready_net,
    s_axis_data_tready => fast_fourier_transform_9_1_s_axis_data_tready_net,
    m_axis_data_tdata_xn_im_0 => fast_fourier_transform_9_1_m_axis_data_tdata_xn_im_0_net,
    m_axis_data_tdata_xn_re_0 => fast_fourier_transform_9_1_m_axis_data_tdata_xn_re_0_net,
    m_axis_data_tuser_xk_index => fast_fourier_transform_9_1_m_axis_data_tuser_xk_index_net,
    m_axis_data_tvalid => fast_fourier_transform_9_1_m_axis_data_tvalid_net(0),
    m_axis_data_tlast => fast_fourier_transform_9_1_m_axis_data_tlast_net,
    event_frame_started => fast_fourier_transform_9_1_event_frame_started_net,
    event_tlast_unexpected => fast_fourier_transform_9_1_event_tlast_unexpected_net,
    event_tlast_missing => fast_fourier_transform_9_1_event_tlast_missing_net,
    event_data_in_channel_halt => fast_fourier_transform_9_1_event_data_in_channel_halt_net
  );
end structural;
-- Generated from Simulink block 
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c_default_clock_driver is
  port (
    dfb4096x1c_sysclk : in std_logic;
    dfb4096x1c_sysce : in std_logic;
    dfb4096x1c_sysclr : in std_logic;
    dfb4096x1c_clk1 : out std_logic;
    dfb4096x1c_ce1 : out std_logic
  );
end dfb4096x1c_default_clock_driver;
architecture structural of dfb4096x1c_default_clock_driver is 
begin
  clockdriver : entity xil_defaultlib.xlclockdriver 
  generic map (
    period => 1,
    log_2_period => 1
  )
  port map (
    sysclk => dfb4096x1c_sysclk,
    sysce => dfb4096x1c_sysce,
    sysclr => dfb4096x1c_sysclr,
    clk => dfb4096x1c_clk1,
    ce => dfb4096x1c_ce1
  );
end structural;
-- Generated from Simulink block 
library IEEE;
use IEEE.std_logic_1164.all;
library xil_defaultlib;
use xil_defaultlib.conv_pkg.all;
entity dfb4096x1c is
  port (
    acc_len : in std_logic_vector( 32-1 downto 0 );
    in_im : in std_logic_vector( 18-1 downto 0 );
    in_re : in std_logic_vector( 18-1 downto 0 );
    valid : in std_logic;
    clk : in std_logic;
    new_acc_out : out std_logic;
    spec_data_out : out std_logic_vector( 64-1 downto 0 );
    vacc_ram_addr : out std_logic_vector( 12-1 downto 0 )
  );
end dfb4096x1c;
architecture structural of dfb4096x1c is 
  attribute core_generation_info : string;
  attribute core_generation_info of structural : architecture is "dfb4096x1c,sysgen_core_2018_2,{,compilation=IP Catalog,block_icon_display=Default,family=zynquplusRFSOC,part=xczu28dr,speed=-2-e,package=ffvg1517,synthesis_language=vhdl,hdl_library=xil_defaultlib,synthesis_strategy=Vivado Synthesis Defaults,implementation_strategy=Vivado Implementation Defaults,testbench=1,interface_doc=0,ce_clr=0,clock_period=7.8125,system_simulink_period=1,waveform_viewer=0,axilite_interface=0,ip_catalog_plugin=0,hwcosim_burst_mode=0,simulation_time=60000,addsub=7,concat=11,constant=31,convert=6,counter=10,delay=17,dsp48e=2,inv=3,logical=7,mult=8,mux=4,register=3,reinterpret=46,relational=9,scale=2,slice=30,spram=4,sprom=4,xfft_v9_1=1,}";
  signal ce_1_net : std_logic;
  signal clk_1_net : std_logic;
begin
  dfb4096x1c_default_clock_driver : entity xil_defaultlib.dfb4096x1c_default_clock_driver 
  port map (
    dfb4096x1c_sysclk => clk,
    dfb4096x1c_sysce => '1',
    dfb4096x1c_sysclr => '0',
    dfb4096x1c_clk1 => clk_1_net,
    dfb4096x1c_ce1 => ce_1_net
  );
  dfb4096x1c_struct : entity xil_defaultlib.dfb4096x1c_struct 
  port map (
    acc_len => acc_len,
    in_im => in_im,
    in_re => in_re,
    valid(0) => valid,
    clk_1 => clk_1_net,
    ce_1 => ce_1_net,
    new_acc_out(0) => new_acc_out,
    spec_data_out => spec_data_out,
    vacc_ram_addr => vacc_ram_addr
  );
end structural;
