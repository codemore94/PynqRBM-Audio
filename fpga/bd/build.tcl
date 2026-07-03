# Vivado non-project implementation flow for the PL-only SoC (rv_rbm_soc).
#
# Run from fpga/bd/:
#   vivado -mode batch -source build.tcl
#
# Produces utilization / timing / power reports in ./impl_out. The top-level
# has wide simulation trace buses, so synthesis runs in out-of-context mode:
# no pin constraints are needed and no bitstream is produced. To build a
# device image, wrap rv_rbm_soc in a small board top (clk/resetn/uart only),
# add pin locations to constraints.xdc, and drop -mode out_of_context.
#
# Power methodology:
#   1. This script always writes a vectorless power report (power.rpt).
#      Treat it as an upper-bound sanity check only — its confidence is Low.
#   2. For a truthful number, run a post-implementation functional sim of
#      the routed netlist (write_verilog -mode funcsim), capture switching
#      activity to impl_out/activity.saif (xsim: log_saif / open_saif), and
#      rerun this script: the SAIF is picked up automatically below and the
#      report confidence rises to High.

set rtl_dir  [file normalize ../rtl/compilable]
set pico_dir [file normalize ../../picorv32]
set out_dir  [file normalize ./impl_out]
file mkdir $out_dir

create_project -in_memory -part xc7z020clg400-1

read_verilog $pico_dir/picorv32.v
read_verilog $pico_dir/picosoc/simpleuart.v
read_verilog -sv [list \
  $rtl_dir/lfsr16.sv \
  $rtl_dir/sigmoid.sv \
  $rtl_dir/rbm_ctrl_axi_lite3.sv \
  $rtl_dir/rbm_cd1_top_axi.sv \
  $rtl_dir/rbm_axil_bridge.sv \
  $rtl_dir/tiny_attn_ctrl_axi.sv \
  $rtl_dir/tiny_attn_core.sv \
  $rtl_dir/tiny_attn_top_axi.sv \
  $rtl_dir/rv_rbm_soc.sv \
]

# Make the sigmoid ROM image findable by $readmemh during synthesis.
read_mem $rtl_dir/sigmoid_q6p10_q0p16.mem

read_xdc constraints.xdc

synth_design -top rv_rbm_soc -part xc7z020clg400-1 -mode out_of_context \
  -generic FW_HEX=$rtl_dir/sw/rv_soc_fw.hex

opt_design
place_design
route_design

report_utilization    -file $out_dir/utilization.rpt
report_timing_summary -file $out_dir/timing_summary.rpt -delay_type min_max

if {[file exists $out_dir/activity.saif]} {
  puts "INFO: using switching activity from $out_dir/activity.saif"
  read_saif $out_dir/activity.saif
} else {
  puts "WARNING: no SAIF found — power.rpt is a low-confidence vectorless estimate"
}
report_power -file $out_dir/power.rpt

write_checkpoint -force $out_dir/rv_rbm_soc_routed.dcp
puts "DONE: reports in $out_dir"
