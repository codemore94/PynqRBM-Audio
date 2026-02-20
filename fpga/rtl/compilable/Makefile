SIM ?= iverilog
TB  ?= tb_rbm_cd1_top_axi
TOP ?= rbm_cd1_top_axi

SRCS = \
  lfsr16.sv \
  sigmoid.sv \
  rbm_ctrl_axi_lite3.sv \
  rbm_cd1_top_axi.sv \
  tb_rbm_cd1_top_axi.sv

all: sim

sim: $(SRCS)
	$(SIM) -g2012 -s $(TB) -o simv $(SRCS)
	./simv

clean:
	rm -f simv *.vcd
