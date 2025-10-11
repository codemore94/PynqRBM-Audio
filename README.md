# PynqRBM-Audio
Restricted Boltzmann Machine Neural Networks Accelerator to recognize downsampled audio samples.
It is meant to be an awesome project, combining the best of RISC-V and Restricted Boltzmann Machine Neural Networks acceleration on Pynq Soc-Fpga.  
This will be https://github.com/codemore94/limits_of_pynq_zynq in cleaner and more clever form. 

Basic concept: Real Hardware consisting of AMD Xilinx's Pynq Zynq D1. On fpga there is implemented both Neural Networks Accelerator and a tiny Risc-V-processor/microcontroller.
Of course also Zynq's Arm exist, it is still question which parts of software should be executed on  ARM hardcore and which on RISC-V softcore on FPGA. 

If possible also part of training is done on fpga-side, but since memory bandwith really becomes as bottleneck, most of training for big sized datasets should be executed by CPU
or GPU. 
The communication between FPGA accelerated Neural Networks, Risc-V softcore, ARM and host computer will be exciting :) Most likely AXI-Stream is the best choice for communication 
internally for SOC but possibly outside the SOC there could be at least in the beginning UART or SPI. 
Also the choices for SW are still to be answered, Risc-V softcore could be very light, so maybe even MMU does not exist and therefore instead of Linux FreeRTOS or other RTOS is 
favored. Still ARM itself would easily run even generic Linux distribution, that could communicate with host computer. 

