// Minimal AXI-Lite register file for RBM + Trainer
module rbm_ctrl_axi_lite #(
  parameter ADDR_W = 8
)(
  input  logic           ACLK,
  input  logic           ARESETn,
  // AXI4-Lite slave
  input  logic [31:0]    S_AWADDR,
  input  logic           S_AWVALID,
  output logic           S_AWREADY,
  input  logic [31:0]    S_WDATA,
  input  logic [3:0]     S_WSTRB,
  input  logic           S_WVALID,
  output logic           S_WREADY,
  output logic [1:0]     S_BRESP,
  output logic           S_BVALID,
  input  logic           S_BREADY,
  input  logic [31:0]    S_ARADDR,
  input  logic           S_ARVALID,
  output logic           S_ARREADY,
  output logic [31:0]    S_RDATA,
  output logic [1:0]     S_RRESP,
  output logic           S_RVALID,
  input  logic           S_RREADY,
  // Control outs
  output logic           ctrl_start,
  output logic           ctrl_soft_rst,
  output logic           ctrl_mode_train,
  output logic           ctrl_determ,
  output logic           ctrl_dma_en,
  output logic [15:0]    i_dim, h_dim, frame_len,
  output logic [7:0]     k_dim,
  output logic [4:0]     scale_shift,
  output logic [15:0]    rng_seed,
  output logic [15:0]    tile_i, tile_h,
  output logic [15:0]    batch_size, epochs,
  output logic [15:0]    lr, mom, wd,
  output logic           accum_clr_pos, accum_clr_neg,
  output logic [31:0]    w_base_lo, w_base_hi,
  output logic [31:0]    b_vis_base, b_hid_base,
  output logic [31:0]    data_base_lo, data_base_hi,
  // Status ins
  input  logic           stat_busy, stat_done, stat_err,
  input  logic           stat_batch_done, stat_epoch_done,
  input  logic [31:0]    stat_flags,
  // IRQ
  output logic           irq,
  input  logic           ie_done, ie_batch, ie_epoch
  ,
  // Memory window
  output logic [31:0]    mem_addr,
  output logic [31:0]    mem_wdata,
  output logic           mem_wen,
  output logic [2:0]     mem_sel,
  input  logic [31:0]    mem_rdata
);
  // Address map (offsets):
  // 0x00 CONTROL, 0x04 STATUS, 0x08 I_DIM, 0x0C H_DIM, 0x10 K_DIM, 0x14 FRAME_LEN,
  // 0x18 SCALE_SHIFT, 0x1C RNG_SEED, 0x20 INT_EN, 0x24 INT_STATUS,
  // 0x28 TILE_IH, 0x2C BATCH_SIZE, 0x30 EPOCHS, 0x34 LR_MOM, 0x38 WEIGHT_DECAY,
  // 0x3C STATS, 0x40 W_BASE_LO, 0x44 W_BASE_HI, 0x48 B_VIS_BASE, 0x4C B_HID_BASE,
  // 0x50 DATA_BASE_LO, 0x54 DATA_BASE_HI, 0x68 ACCUM_CTRL,
  // 0x6C MEM_ADDR, 0x70 MEM_WDATA, 0x74 MEM_RDATA, 0x78 MEM_CTRL

  // Simple AXI-Lite read/write with internal address capture.

  // Registers
  logic [31:0] REG_CONTROL, REG_STATUS, REG_INT_EN, REG_INT_ST;
  assign ctrl_start     = REG_CONTROL[0];
  assign ctrl_soft_rst  = REG_CONTROL[1];
  assign ctrl_mode_train= REG_CONTROL[2];
  assign ctrl_determ    = REG_CONTROL[3];
  assign ctrl_dma_en    = REG_CONTROL[4];

  logic [31:0] REG_I_DIM, REG_H_DIM, REG_K_DIM, REG_FRAME_LEN;
  logic [31:0] REG_SCALE_SHIFT, REG_RNG_SEED, REG_TILE_IH;
  logic [31:0] REG_BATCH, REG_EPOCHS, REG_LR_MOM, REG_WD, REG_STATS;
  logic [31:0] REG_W_BASE_LO, REG_W_BASE_HI, REG_B_VIS_BASE, REG_B_HID_BASE;
  logic [31:0] REG_DATA_BASE_LO, REG_DATA_BASE_HI, REG_ACCUM_CTRL;
  logic [31:0] REG_MEM_ADDR, REG_MEM_WDATA, REG_MEM_CTRL;

  assign i_dim       = REG_I_DIM[15:0];
  assign h_dim       = REG_H_DIM[15:0];
  assign k_dim       = REG_K_DIM[7:0];
  assign frame_len   = REG_FRAME_LEN[15:0];
  assign scale_shift = REG_SCALE_SHIFT[4:0];
  assign rng_seed    = REG_RNG_SEED[15:0];
  assign tile_i      = REG_TILE_IH[15:0];
  assign tile_h      = REG_TILE_IH[31:16];
  assign batch_size  = REG_BATCH[15:0];
  assign epochs      = REG_EPOCHS[15:0];
  assign lr          = REG_LR_MOM[15:0];
  assign mom         = REG_LR_MOM[31:16];
  assign wd          = REG_WD[15:0];
  assign accum_clr_pos = REG_ACCUM_CTRL[0];
  assign accum_clr_neg = REG_ACCUM_CTRL[1];

  assign w_base_lo   = REG_W_BASE_LO;
  assign w_base_hi   = REG_W_BASE_HI;
  assign b_vis_base  = REG_B_VIS_BASE;
  assign b_hid_base  = REG_B_HID_BASE;
  assign data_base_lo= REG_DATA_BASE_LO;
  assign data_base_hi= REG_DATA_BASE_HI;

  assign mem_addr  = REG_MEM_ADDR;
  assign mem_wdata = REG_MEM_WDATA;
  assign mem_sel   = REG_MEM_CTRL[2:0];

  // IRQ: level when any done flag & enabled
  wire any_int = (ie_done  & stat_done) |
                 (ie_batch & stat_batch_done) |
                 (ie_epoch & stat_epoch_done);
  assign irq = any_int;

  // AXI-lite minimal protocol (ready/valid strobes)
  // Single-beat read/write, no outstanding transactions.
  logic [ADDR_W-1:0] awaddr_latched, araddr_latched;

  assign S_BRESP = 2'b00;
  assign S_RRESP = 2'b00;

  always_ff @(posedge ACLK) begin
    if (!ARESETn) begin
      S_AWREADY <= 1'b1;
      S_WREADY  <= 1'b1;
      S_BVALID  <= 1'b0;
      S_ARREADY <= 1'b1;
      S_RVALID  <= 1'b0;
      S_RDATA   <= 32'b0;
      awaddr_latched <= '0;
      araddr_latched <= '0;
      REG_CONTROL <= 32'b0;
      REG_INT_EN  <= 32'b0;
      REG_INT_ST  <= 32'b0;
      REG_I_DIM   <= 32'd256;
      REG_H_DIM   <= 32'd256;
      REG_K_DIM   <= 32'd1;
      REG_FRAME_LEN <= 32'd1;
      REG_SCALE_SHIFT <= 32'd0;
      REG_RNG_SEED <= 32'd1;
      REG_TILE_IH <= 32'd0;
      REG_BATCH   <= 32'd1;
      REG_EPOCHS  <= 32'd1;
      REG_LR_MOM  <= 32'd0;
      REG_WD      <= 32'd0;
      REG_W_BASE_LO <= 32'd0;
      REG_W_BASE_HI <= 32'd0;
      REG_B_VIS_BASE <= 32'd0;
      REG_B_HID_BASE <= 32'd0;
      REG_DATA_BASE_LO <= 32'd0;
      REG_DATA_BASE_HI <= 32'd0;
      REG_ACCUM_CTRL <= 32'd0;
      REG_MEM_ADDR <= 32'd0;
      REG_MEM_WDATA <= 32'd0;
      REG_MEM_CTRL <= 32'd0;
      mem_wen <= 1'b0;
    end else begin
      mem_wen <= 1'b0;

      // Write channel
      if (S_AWVALID && S_WVALID && !S_BVALID) begin
        awaddr_latched <= S_AWADDR[ADDR_W-1:0];
        S_BVALID <= 1'b1;
        // decode write
        case (S_AWADDR[ADDR_W-1:2])
          6'h00: REG_CONTROL <= apply_wstrb(REG_CONTROL, S_WDATA, S_WSTRB);
          6'h02: REG_I_DIM   <= apply_wstrb(REG_I_DIM, S_WDATA, S_WSTRB);
          6'h03: REG_H_DIM   <= apply_wstrb(REG_H_DIM, S_WDATA, S_WSTRB);
          6'h04: REG_K_DIM   <= apply_wstrb(REG_K_DIM, S_WDATA, S_WSTRB);
          6'h05: REG_FRAME_LEN <= apply_wstrb(REG_FRAME_LEN, S_WDATA, S_WSTRB);
          6'h06: REG_SCALE_SHIFT <= apply_wstrb(REG_SCALE_SHIFT, S_WDATA, S_WSTRB);
          6'h07: REG_RNG_SEED <= apply_wstrb(REG_RNG_SEED, S_WDATA, S_WSTRB);
          6'h08: REG_INT_EN  <= apply_wstrb(REG_INT_EN, S_WDATA, S_WSTRB);
          6'h0A: REG_TILE_IH <= apply_wstrb(REG_TILE_IH, S_WDATA, S_WSTRB);
          6'h0B: REG_BATCH   <= apply_wstrb(REG_BATCH, S_WDATA, S_WSTRB);
          6'h0C: REG_EPOCHS  <= apply_wstrb(REG_EPOCHS, S_WDATA, S_WSTRB);
          6'h0D: REG_LR_MOM  <= apply_wstrb(REG_LR_MOM, S_WDATA, S_WSTRB);
          6'h0E: REG_WD      <= apply_wstrb(REG_WD, S_WDATA, S_WSTRB);
          6'h10: REG_W_BASE_LO <= apply_wstrb(REG_W_BASE_LO, S_WDATA, S_WSTRB);
          6'h11: REG_W_BASE_HI <= apply_wstrb(REG_W_BASE_HI, S_WDATA, S_WSTRB);
          6'h12: REG_B_VIS_BASE <= apply_wstrb(REG_B_VIS_BASE, S_WDATA, S_WSTRB);
          6'h13: REG_B_HID_BASE <= apply_wstrb(REG_B_HID_BASE, S_WDATA, S_WSTRB);
          6'h14: REG_DATA_BASE_LO <= apply_wstrb(REG_DATA_BASE_LO, S_WDATA, S_WSTRB);
          6'h15: REG_DATA_BASE_HI <= apply_wstrb(REG_DATA_BASE_HI, S_WDATA, S_WSTRB);
          6'h1A: REG_ACCUM_CTRL <= apply_wstrb(REG_ACCUM_CTRL, S_WDATA, S_WSTRB);
          6'h1B: REG_MEM_ADDR <= apply_wstrb(REG_MEM_ADDR, S_WDATA, S_WSTRB);
          6'h1C: begin
            REG_MEM_WDATA <= apply_wstrb(REG_MEM_WDATA, S_WDATA, S_WSTRB);
            mem_wen <= 1'b1;
          end
          6'h1E: REG_MEM_CTRL <= apply_wstrb(REG_MEM_CTRL, S_WDATA, S_WSTRB);
          default: ;
        endcase
      end else if (S_BVALID && S_BREADY) begin
        S_BVALID <= 1'b0;
      end

      // Read channel
      if (S_ARVALID && !S_RVALID) begin
        araddr_latched <= S_ARADDR[ADDR_W-1:0];
        S_RVALID <= 1'b1;
        case (S_ARADDR[ADDR_W-1:2])
          6'h00: S_RDATA <= REG_CONTROL;
          6'h01: S_RDATA <= REG_STATUS;
          6'h02: S_RDATA <= REG_I_DIM;
          6'h03: S_RDATA <= REG_H_DIM;
          6'h04: S_RDATA <= REG_K_DIM;
          6'h05: S_RDATA <= REG_FRAME_LEN;
          6'h06: S_RDATA <= REG_SCALE_SHIFT;
          6'h07: S_RDATA <= REG_RNG_SEED;
          6'h08: S_RDATA <= REG_INT_EN;
          6'h09: S_RDATA <= REG_INT_ST;
          6'h0A: S_RDATA <= REG_TILE_IH;
          6'h0B: S_RDATA <= REG_BATCH;
          6'h0C: S_RDATA <= REG_EPOCHS;
          6'h0D: S_RDATA <= REG_LR_MOM;
          6'h0E: S_RDATA <= REG_WD;
          6'h0F: S_RDATA <= REG_STATS;
          6'h10: S_RDATA <= REG_W_BASE_LO;
          6'h11: S_RDATA <= REG_W_BASE_HI;
          6'h12: S_RDATA <= REG_B_VIS_BASE;
          6'h13: S_RDATA <= REG_B_HID_BASE;
          6'h14: S_RDATA <= REG_DATA_BASE_LO;
          6'h15: S_RDATA <= REG_DATA_BASE_HI;
          6'h1A: S_RDATA <= REG_ACCUM_CTRL;
          6'h1B: S_RDATA <= REG_MEM_ADDR;
          6'h1C: S_RDATA <= REG_MEM_WDATA;
          6'h1D: S_RDATA <= mem_rdata;
          6'h1E: S_RDATA <= REG_MEM_CTRL;
          default: S_RDATA <= 32'b0;
        endcase
      end else if (S_RVALID && S_RREADY) begin
        S_RVALID <= 1'b0;
      end
    end
  end

  function automatic [31:0] apply_wstrb(
    input [31:0] cur,
    input [31:0] wdata,
    input [3:0]  wstrb
  );
    begin
      apply_wstrb = cur;
      if (wstrb[0]) apply_wstrb[7:0]   = wdata[7:0];
      if (wstrb[1]) apply_wstrb[15:8]  = wdata[15:8];
      if (wstrb[2]) apply_wstrb[23:16] = wdata[23:16];
      if (wstrb[3]) apply_wstrb[31:24] = wdata[31:24];
    end
  endfunction

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
