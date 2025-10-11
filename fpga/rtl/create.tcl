## `fpga/scripts/build_project.tcl`

```tcl
create_project bolt_ear ./bolt_ear -part xc7z020clg400-1
set_property board_part digilentinc.com:pynq-z1:part0:1.0 [current_project]
read_verilog -sv [glob ../rtl/*.sv]
read_xdc ../bd/constraints.xdc
# Optional: source block design later; start with plain RTL top if you have one
update_compile_order -fileset sources_1
synth_design -top rbm_core_min -part xc7z020clg400-1
opt_design
place_design
route_design
write_bitstream -force bolt_ear.bit
write_hw_platform -fixed -include_bit -force bolt_ear.xsa
```

---
