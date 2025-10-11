# Run inside the Vivado project after synthesis sources are added
# This packages top_axi_rbm as an AXI4-Lite IP for block design use.


set proj_name pynq_audio_rbm
set ip_name rbm_trainer_axi
set top_name top_axi_rbm


# Create IP packager project
ipx::package_project -root_dir ./ip_repo/${ip_name} -vendor user.org -library user -taxonomy /UserIP -import_files
set_property name ${ip_name} [ipx::current_core]
set_property display_name "RBM Trainer AXI" [ipx::current_core]
set_property description "RBM forward/core with AXI4-Lite control (bring-up)" [ipx::current_core]


# Associate top module
ipx::add_file_group -type verilog synthesis [ipx::current_core]
ipx::add_file_group -type verilog simulation [ipx::current_core]
set files [list \
../fpga/rtl/top_axi_rbm.sv \
../fpga/rtl/rbm_ctrl_axi_lite.sv \
../fpga/rtl/rbm_core_min.sv \
../fpga/rtl/sigmoid_lut.sv \
../fpga/rtl/lfsr16.sv]
foreach f $files { ipx::add_file $f [ipx::get_file_groups -of_objects [ipx::current_core] synthesis] }
foreach f $files { ipx::add_file $f [ipx::get_file_groups -of_objects [ipx::current_core] simulation] }


# Infer AXI4-Lite interface
set ctrl_if [ipx::add_bus_interface S_AXI [ipx::current_core]]
ipx::associate_bus_interfaces -busif S_AXI -clock aclk [ipx::current_core]
# Map ports (expects names S_AXIL_*)
# If Vivado cannot infer automatically, add port maps:
# ipx::add_port_map AWADDR S_AXIL_AWADDR [ipx::get_bus_interfaces S_AXI]
# ... (repeat for AWVALID, AWREADY, WDATA, WSTRB, WVALID, WREADY, BRESP, BVALID, BREADY, ARADDR, ARVALID, ARREADY, RDATA, RRESP, RVALID, RREADY)


# Clocks/Resets
set aclk_if [ipx::add_bus_interface aclk [ipx::current_core]]
set_property interface_mode slave $aclk_if
set_property abstraction_type_vlnv xilinx.com:signal:clock_rtl:1.0 $aclk_if
ipx::add_port_map CLK aclk $aclk_if


set arst_if [ipx::add_bus_interface aresetn [ipx::current_core]]
set_property interface_mode slave $arst_if
set_property abstraction_type_vlnv xilinx.com:signal:reset_rtl:1.0 $arst_if
ipx::add_port_map RST aresetn $arst_if


# Validate and save IP
ipx::check_integrity [ipx::current_core]
ipx::save_core [ipx::current_core]


# Add repo to project
set_property ip_repo_paths [concat [get_property ip_repo_paths [current_fileset]] "[file normalize ./ip_repo]"] [current_project]
update_ip_catalog
puts "Packed IP ${ip_name} and updated repo."
