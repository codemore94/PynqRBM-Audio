Phase 0 — Prep your workspace

1.Create the repo and folders:
mkdir -p PynqAudio-RBM/{fpga/{rtl,bd,mem,sim/scripts},sw_rv/{app,bsp,FreeRTOS-Kernel},training}

2.Tooling you need installed:

Vivado 2023.1 

RISC-V GCC (riscv32-unknown-elf-*)

Python 3.10+ with numpy

3.Phase 1 — Generate lookup tables & golden vectors

From repo root:python training/make_sigmoid_lut.py
python training/make_golden_mem.py

Done when: fpga/mem/sigmoid_q6p10_q0p16.mem and fpga/sim/vectors/{v_mem.mem,w_col.mem,bias.mem,acc_shift.mem} exist.

Phase 2 — Simulate the minimal RBM core

Open your simulator (Vivado XSim is fine) and run the provided TB:

inside Vivado tcl console OR shell
cd fpga
//compile + simulate tb_rbm_core_min.sv (adjust if using another sim)
xvlog -sv rtl/sigmoid_lut.sv rtl/rbm_core_min.sv sim/tb_rbm_core_min.sv
xelab tb_rbm_core_min -s tb
xsim tb -run all
Expect: it prints a p_j=0x.... line and finishes without errors.

Actually one can use as well Intel/Altera's Modelsim in the testbenching, in the subdirectory simulation_evolution_modelsim there are screenshots of the current state of the testbench for rbm_core_min.sv-module. (IDLE->ACC->ACT->IDLE)-state transitions are succesfull by current testbench (at least for Modelsim :D)

Basic
      vlib work

      vlog -sv PynqRBM-Audio/fpga/rtl/compilable/*.sv

      vsim -voptargs=+acc work.tb_rbm_core_min

      add wave -r sim:/tb_rbm_core_min/*

      run -all

should be enough for Modelsim.