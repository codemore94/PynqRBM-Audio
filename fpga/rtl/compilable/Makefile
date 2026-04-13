SIM ?= iverilog
TB  ?= tb_rbm_cd1_top_axi
TOP ?= rbm_cd1_top_axi
CROSS ?= riscv32-unknown-elf-

SRCS = \
  lfsr16.sv \
  sigmoid.sv \
  rbm_ctrl_axi_lite3.sv \
  rbm_cd1_top_axi.sv \
  tb_rbm_cd1_top_axi.sv

SOC_TB ?= tb_rv_rbm_soc_smoke
SOC_SRCS = \
  ../../../picorv32/picorv32.v \
  ../../../picorv32/picosoc/simpleuart.v \
  lfsr16.sv \
  sigmoid.sv \
  rbm_ctrl_axi_lite3.sv \
  rbm_cd1_top_axi.sv \
  rbm_axil_bridge.sv \
  rv_rbm_soc.sv \
  tb_rv_rbm_soc_smoke.sv

SOC_SMALL_TB ?= tb_rv_rbm_soc_small
SOC_SMALL_SRCS = \
  ../../../picorv32/picorv32.v \
  ../../../picorv32/picosoc/simpleuart.v \
  lfsr16.sv \
  sigmoid.sv \
  rbm_ctrl_axi_lite3.sv \
  rbm_cd1_top_axi.sv \
  rbm_axil_bridge.sv \
  rv_rbm_soc.sv \
  tb_rv_rbm_soc_small.sv

SOC_FULL_TB ?= tb_rv_tiny_attn_rbm_soc_full
SOC_FULL_SRCS = \
  ../../../picorv32/picorv32.v \
  ../../../picorv32/picosoc/simpleuart.v \
  lfsr16.sv \
  sigmoid.sv \
  rbm_ctrl_axi_lite3.sv \
  rbm_cd1_top_axi.sv \
  rbm_axil_bridge.sv \
  tiny_attn_ctrl_axi.sv \
  tiny_attn_core.sv \
  tiny_attn_top_axi.sv \
  rv_rbm_soc.sv \
  tb_rv_tiny_attn_rbm_soc_full.sv

TINY_TB ?= tb_tiny_attn_top_axi
TINY_SRCS = \
  tiny_attn_ctrl_axi.sv \
  tiny_attn_core.sv \
  tiny_attn_top_axi.sv \
  tb_tiny_attn_top_axi.sv

all: sim

sim: $(SRCS)
	$(SIM) -g2012 -s $(TB) -o simv $(SRCS)
	./simv

sim_soc: $(SOC_SRCS)
	$(SIM) -g2012 -s $(SOC_TB) -o simv_soc $(SOC_SRCS)
	./simv_soc

sim_soc_small: $(SOC_SMALL_SRCS)
	$(SIM) -g2012 -s $(SOC_SMALL_TB) -o simv_soc_small $(SOC_SMALL_SRCS)
	./simv_soc_small

sim_soc_full: fw_soc_full $(SOC_FULL_SRCS)
	$(SIM) -g2012 -s $(SOC_FULL_TB) -o simv_soc_full $(SOC_FULL_SRCS)
	./simv_soc_full

sim_tiny: $(TINY_SRCS)
	$(SIM) -g2012 -s $(TINY_TB) -o simv_tiny $(TINY_SRCS)
	./simv_tiny

sim_soc_long: fw_soc
	$(MAKE) sim_soc
	$(MAKE) sim_soc_small

fw_soc: sw/rv_soc_fw.c sw/rbm_regs.h sw/rv_soc_fw.lds sw/rv_soc_start.S
	$(CROSS)gcc -Os -march=rv32imc -mabi=ilp32 -ffreestanding -nostdlib -Wl,-T,sw/rv_soc_fw.lds,--build-id=none -o sw/rv_soc_fw.elf sw/rv_soc_start.S sw/rv_soc_fw.c
	$(CROSS)objcopy -O binary sw/rv_soc_fw.elf sw/rv_soc_fw.bin
	python3 ../../../picorv32/firmware/makehex.py sw/rv_soc_fw.bin 4096 > sw/rv_soc_fw.hex

fw_soc_full: sw/rv_soc_full_fw.c sw/rbm_regs.h sw/rv_soc_fw.lds sw/rv_soc_start.S
	$(CROSS)gcc -Os -march=rv32imc -mabi=ilp32 -ffreestanding -nostdlib -Wl,-T,sw/rv_soc_fw.lds,--build-id=none -o sw/rv_soc_full_fw.elf sw/rv_soc_start.S sw/rv_soc_full_fw.c
	$(CROSS)objcopy -O binary sw/rv_soc_full_fw.elf sw/rv_soc_full_fw.bin
	python3 ../../../picorv32/firmware/makehex.py sw/rv_soc_full_fw.bin 4096 > sw/rv_soc_full_fw.hex

clean:
	rm -f simv simv_soc simv_soc_small simv_soc_full simv_tiny *.vcd sw/rv_soc_fw.elf sw/rv_soc_fw.bin sw/rv_soc_full_fw.elf sw/rv_soc_full_fw.bin
