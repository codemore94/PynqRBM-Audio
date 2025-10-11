create_bd_design "bd_pl"
# Use clk_wiz to make 100 MHz
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list CONFIG.PRIM_IN_FREQ {100.0} CONFIG.CLK_OUT1_REQUESTED_OUT_FREQ {100.0}] [get_bd_cells clk_wiz_0]
# AXI interconnect + UART + Timer + BRAM will be added when you package the core as AXI IP
validate_bd_design
save_bd_design
