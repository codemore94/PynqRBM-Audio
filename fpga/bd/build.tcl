create_project pynq_rbm_audio ./pynq_rbm_audio -part xc7z020clg400-1
set_property board_part digilentinc.com:pynq-z1:part0:1.0 [current_project]
read_verilog -sv [glob ../rtl/*.sv]
read_xdc ../bd/constraints.xdc
# Block design (PS + AXI interconnect + UART/Timer + BRAM + accel)
source ../bd/create_bd.tcl
update_compile_order -fileset sources_1
synth_design -top top_pl -part xc7z020clg400-1
opt_design
place_design
route_design
write_bitstream -force pynq_rbm_audio.bit
write_hw_platform -fixed -include_bit -force pynq_rbm_audio.xsa
