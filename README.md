At a high level, this design is a small FPGA SoC that combines three parts:

  - A PicoRV32 soft CPU
  - A tiny self-attention accelerator
  - An RBM CD-1 accelerator

  The top-level integration is in rv_rbm_soc.sv. The CPU runs firmware from on-chip RAM, then controls both accelerators
  through memory-mapped AXI-Lite style registers.

  The intended flow is:

  1. The CPU loads tokens and attention weights into the tiny-attention block.
  2. The tiny-attention block computes a contextualized output vector.
  3. Optionally, it runs a very small training step on a post-attention adapter.
     This does not train full Q/K/V attention. It only updates adapter gain/bias after attention.
  4. The CPU reads the attention output.
  5. The CPU writes that output into the RBM visible layer memory.
  6. The RBM block runs deterministic CD-1 style processing/training.
  7. The RBM raises an interrupt when done.

  So conceptually:

  - tiny_attn_top_axi = context encoder
  - rbm_cd1_top_axi = trainable generative/associative model
  - picorv32 = controller that sequences everything

  Main files:

  - SoC integration: rv_rbm_soc.sv
  - Tiny attention control/datapath:
      - tiny_attn_ctrl_axi.sv
      - tiny_attn_core.sv
      - tiny_attn_top_axi.sv
  - RBM control/datapath:
      - rbm_ctrl_axi_lite3.sv
      - rbm_cd1_top_axi.sv
  - Firmware:
      - sw/rv_soc_full_fw.c

  In one sentence: this is a firmware-controlled FPGA system where tiny attention produces context features and the RBM
  consumes them for learning/inference.
