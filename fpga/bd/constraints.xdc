# Timing constraints for rv_rbm_soc (PL-only SoC).
#
# A real clock definition is mandatory: without it implementation is not
# timing-driven and report_power falls back to blind vectorless toggle
# rates, which is how the bogus multi-hundred-watt estimates happen.
#
# 25 MHz matches the PYNQ-Z1 fabric clock configured in create_bd.tcl.
# The tiny_attn adapter-update path chains three dependent multiplies in one
# cycle (~38 ns of logic), so 100 MHz cannot close timing; 25 MHz has margin.
create_clock -period 40.000 -name sys_clk [get_ports clk]

# Asynchronous external reset; timed paths from it are not meaningful.
set_false_path -from [get_ports resetn]

# When targeting a real bitstream (not the out-of-context flow in
# build.tcl), add board pin locations here, e.g. for PYNQ-Z1:
#   set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports clk]
