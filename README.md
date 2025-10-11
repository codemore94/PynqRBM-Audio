# PynqRBM-Audio
Restricted Boltzmann Machine Neural Networks Accelerator to recognize downsampled audio samples.
It is meant to be an awesome project, combining the best of RISC-V and Restricted Boltzmann Machine Neural Networks acceleration on Pynq Soc-Fpga.  
This will be https://github.com/codemore94/limits_of_pynq_zynq in cleaner and more clever form. 

Basic concept: Real Hardware consisting of AMD Xilinx's Pynq Zynq D1. On fpga there is implemented both Neural Networks Accelerator and a tiny Risc-V-processor/microcontroller.
Of course also Zynq's Arm exist, it is still question which parts of software should be executed on  ARM hardcore and which on RISC-V softcore on FPGA. 

