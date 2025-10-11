create_project pynq_audio_rbm ./pynq_audio_rbm -part xc7z020clg400-1
set_property board_part digilentinc.com:pynq-z1:part0:1.0 [current_project]
read_verilog -sv [glob ../rtl/*.sv]
read_xdc ../bd/constraints.xdc
# Optional: source block design later; start with plain RTL top if you have one
update_compile_order -fileset sources_1
synth_design -top rbm_core_min -part xc7z020clg400-1
opt_design
place_design
route_design
write_bitstream -force pynq_audio_rbm.bit
write_hw_platform -fixed -include_bit -force pynq_audio_rbm.xsa
