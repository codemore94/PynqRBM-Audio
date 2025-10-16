// Minimal AXI-Lite register file for RBM + Trainer
module rbm_ctrl_axi_lite #(
parameter ADDR_W = 8
)(
input logic ACLK,
input logic ARESETn,
// AXI4-Lite slave
input logic [31:0] S_AWADDR,
input logic S_AWVALID,
output logic S_AWREADY,
input logic [31:0] S_WDATA,
input logic [3:0] S_WSTRB,
input logic S_WVALID,
output logic S_WREADY,
output logic [1:0] S_BRESP,
output logic S_BVALID,
input logic S_BREADY,
input logic [31:0] S_ARADDR,
input logic S_ARVALID,
output logic S_ARREADY,
output logic [31:0] S_RDATA,
output logic [1:0] S_RRESP,
output logic S_RVALID,
input logic S_RREADY,
// Control outs
output logic ctrl_start,
output logic ctrl_soft_rst,
output logic ctrl_mode_train,
output logic ctrl_determ,
output logic ctrl_dma_en,
output logic [15:0] i_dim, h_dim, frame_len,
output logic [7:0] k_dim,
output logic [4:0] scale_shift,
output logic [15:0] rng_seed,
output logic [15:0] tile_i, tile_h,
output logic [15:0] batch_size, epochs,
output logic [15:0] lr, mom, wd,
output logic accum_clr_pos, accum_clr_neg,
output logic [31:0] w_base_lo, w_base_hi,
output logic [31:0] b_vis_base, b_hid_base,
output logic [31:0] data_base_lo, data_base_hi,
// Status ins
input logic stat_busy, stat_done, stat_err,
input logic stat_batch_done, stat_epoch_done,
input logic [31:0] stat_flags,
// IRQ
output logic irq,
input logic ie_done, ie_batch, ie_epoch
);
// Address map (offsets):
// 0x00 CONTROL, 0x04 STATUS, 0x08 I_DIM, 0x0C H_DIM, 0x10 K_DIM, 0x14 FRAME_LEN,
// 0x18 SCALE_SHIFT, 0x1C RNG_SEED, 0x20 INT_EN, 0x24 INT_STATUS,
// 0x28 TILE_IH, 0x2C BATCH_SIZE, 0x30 EPOCHS, 0x34 LR_MOM, 0x38 WEIGHT_DECAY,
// 0x3C STATS, 0x40 W_BASE_LO, 0x44 W_BASE_HI, 0x48 B_VIS_BASE, 0x4C B_HID_BASE,
// 0x50 DATA_BASE_LO, 0x54 DATA_BASE_HI, 0x68 ACCUM_CTRL


// Simple one-cycle ready/valid handshake implementation
// (For brevity, standard AXI-Lite boilerplate is condensed.)


// Registers
logic [31:0] REG_CONTROL, REG_STATUS, REG_INT_EN, REG_INT_ST;
endmodule
