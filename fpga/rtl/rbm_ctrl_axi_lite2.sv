// Minimal AXI-Lite register file for RBM + Trainer
assign ctrl_soft_rst = REG_CONTROL[1];
assign ctrl_mode_train= REG_CONTROL[2];
assign ctrl_determ = REG_CONTROL[3];
assign ctrl_dma_en = REG_CONTROL[4];


logic [31:0] REG_I_DIM, REG_H_DIM, REG_K_DIM, REG_FRAME_LEN;
logic [31:0] REG_SCALE_SHIFT, REG_RNG_SEED, REG_TILE_IH;
logic [31:0] REG_BATCH, REG_EPOCHS, REG_LR_MOM, REG_WD, REG_STATS;
logic [31:0] REG_W_BASE_LO, REG_W_BASE_HI, REG_B_VIS_BASE, REG_B_HID_BASE;
logic [31:0] REG_DATA_BASE_LO, REG_DATA_BASE_HI, REG_ACCUM_CTRL;


assign i_dim = REG_I_DIM[15:0];
assign h_dim = REG_H_DIM[15:0];
assign k_dim = REG_K_DIM[7:0];
assign frame_len = REG_FRAME_LEN[15:0];
assign scale_shift = REG_SCALE_SHIFT[4:0];
assign rng_seed = REG_RNG_SEED[15:0];
assign tile_i = REG_TILE_IH[15:0];
assign tile_h = REG_TILE_IH[31:16];
assign batch_size = REG_BATCH[15:0];
assign epochs = REG_EPOCHS[15:0];
assign lr = REG_LR_MOM[15:0];
assign mom = REG_LR_MOM[31:16];
assign wd = REG_WD[15:0];
assign accum_clr_pos = REG_ACCUM_CTRL[0];
assign accum_clr_neg = REG_ACCUM_CTRL[1];


assign w_base_lo = REG_W_BASE_LO;
assign w_base_hi = REG_W_BASE_HI;
assign b_vis_base = REG_B_VIS_BASE;
assign b_hid_base = REG_B_HID_BASE;
assign data_base_lo= REG_DATA_BASE_LO;
assign data_base_hi= REG_DATA_BASE_HI;


// IRQ: level when any done flag & enabled
wire any_int = (ie_done & stat_done) |
(ie_batch & stat_batch_done) |
(ie_epoch & stat_epoch_done);
assign irq = any_int;


// AXI-lite minimal protocol (ready/valid strobes)
// NOTE: Replace with your proven regfile if available.
// ... (boilerplate omitted for brevity) ...


// STATUS readback wiring
always_comb begin
REG_STATUS = 32'b0;
REG_STATUS[0] = stat_busy;
REG_STATUS[1] = stat_done;
REG_STATUS[2] = stat_err;
REG_STATUS[3] = stat_batch_done;
REG_STATUS[4] = stat_epoch_done;
end


assign REG_STATS = stat_flags;
endmodule
