create_project pynq_audio_rbm_axi ./bolt_ear_axi -part xc7z020clg400-1
set_property board_part digilentinc.com:pynq-z1:part0:1.0 [current_project]
read_verilog -sv [glob ../rtl/*.sv]
read_xdc ../bd/constraints.xdc
synth_design -top top_axi_rbm -part xc7z020clg400-1
opt_design; place_design; route_design
write_bitstream -force pynq_audio_rbm_axi.bit
write_hw_platform -fixed -include_bit -force pynq_audio_rb_axi.xsa
