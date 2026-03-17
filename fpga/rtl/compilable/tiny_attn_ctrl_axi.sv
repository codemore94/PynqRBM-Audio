// Minimal AXI-Lite register file for tiny self-attention
module tiny_attn_ctrl_axi #(
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
  output logic           ctrl_use_out_proj,
  output logic           ctrl_causal,
  output logic [15:0]    seq_len,
  output logic [15:0]    d_model,
  output logic [15:0]    d_head,
  output logic [7:0]     score_shift,
  output logic [15:0]    norm_bias,
  output logic [31:0]    token_base_lo,
  output logic [31:0]    token_base_hi,
  output logic [31:0]    wq_base,
  output logic [31:0]    wk_base,
  output logic [31:0]    wv_base,
  output logic [31:0]    wo_base,
  output logic [31:0]    out_base,
  // Status ins
  input  logic           stat_busy,
  input  logic           stat_done,
  input  logic           stat_err,
  input  logic [31:0]    stat_cycles,
  input  logic [31:0]    stat_macs,
  input  logic [31:0]    stat_stalls,
  // IRQ
  output logic           irq,
  // Memory window
  output logic [31:0]    mem_addr,
  output logic [31:0]    mem_wdata,
  output logic           mem_wen,
  output logic [2:0]     mem_sel,
  input  logic [31:0]    mem_rdata
);
  // Address map (offsets):
  // 0x00 CONTROL:
  //      [0] START, [1] SOFT_RST, [2] MODE_TRAIN, [3] USE_OUT_PROJ, [4] CAUSAL
  // 0x04 STATUS: [0] BUSY, [1] DONE, [2] ERR
  // 0x08 SEQ_LEN
  // 0x0C D_MODEL
  // 0x10 D_HEAD
  // 0x14 SCORE_SHIFT
  // 0x18 NORM_BIAS
  // 0x1C INT_EN: [0] done, [1] err
  // 0x20 INT_STATUS
  // 0x24 TOKEN_BASE_LO
  // 0x28 TOKEN_BASE_HI
  // 0x2C WQ_BASE
  // 0x30 WK_BASE
  // 0x34 WV_BASE
  // 0x38 WO_BASE
  // 0x3C OUT_BASE
  // 0x40 HW_VERSION
  // 0x44 PERF_CYCLES
  // 0x48 PERF_MACS
  // 0x4C PERF_STALLS
  // 0x54 MEM_ADDR
  // 0x58 MEM_WDATA
  // 0x5C MEM_RDATA
  // 0x60 MEM_CTRL: [2:0] mem_sel

  logic [31:0] REG_CONTROL, REG_STATUS, REG_INT_EN, REG_INT_ST;
  logic [31:0] REG_SEQ_LEN, REG_D_MODEL, REG_D_HEAD;
  logic [31:0] REG_SCORE_SHIFT, REG_NORM_BIAS;
  logic [31:0] REG_TOKEN_BASE_LO, REG_TOKEN_BASE_HI;
  logic [31:0] REG_WQ_BASE, REG_WK_BASE, REG_WV_BASE, REG_WO_BASE, REG_OUT_BASE;
  logic [31:0] REG_MEM_ADDR, REG_MEM_WDATA, REG_MEM_CTRL;

  localparam logic [31:0] HW_VERSION = 32'h0001_1000;

  assign ctrl_start        = REG_CONTROL[0];
  assign ctrl_soft_rst     = REG_CONTROL[1];
  assign ctrl_mode_train   = REG_CONTROL[2];
  assign ctrl_use_out_proj = REG_CONTROL[3];
  assign ctrl_causal       = REG_CONTROL[4];

  assign seq_len       = REG_SEQ_LEN[15:0];
  assign d_model       = REG_D_MODEL[15:0];
  assign d_head        = REG_D_HEAD[15:0];
  assign score_shift   = REG_SCORE_SHIFT[7:0];
  assign norm_bias     = REG_NORM_BIAS[15:0];
  assign token_base_lo = REG_TOKEN_BASE_LO;
  assign token_base_hi = REG_TOKEN_BASE_HI;
  assign wq_base       = REG_WQ_BASE;
  assign wk_base       = REG_WK_BASE;
  assign wv_base       = REG_WV_BASE;
  assign wo_base       = REG_WO_BASE;
  assign out_base      = REG_OUT_BASE;

  assign mem_addr  = REG_MEM_ADDR;
  assign mem_wdata = REG_MEM_WDATA;
  assign mem_sel   = REG_MEM_CTRL[2:0];

  wire done_irq = REG_INT_EN[0] & stat_done;
  wire err_irq  = REG_INT_EN[1] & stat_err;

  assign irq = done_irq | err_irq;

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
      REG_CONTROL <= 32'b0;
      REG_STATUS  <= 32'b0;
      REG_INT_EN  <= 32'b0;
      REG_INT_ST  <= 32'b0;
      REG_SEQ_LEN <= 32'd4;
      REG_D_MODEL <= 32'd4;
      REG_D_HEAD  <= 32'd4;
      REG_SCORE_SHIFT <= 32'd4;
      REG_NORM_BIAS <= 32'd1;
      REG_TOKEN_BASE_LO <= 32'd0;
      REG_TOKEN_BASE_HI <= 32'd0;
      REG_WQ_BASE <= 32'd0;
      REG_WK_BASE <= 32'd0;
      REG_WV_BASE <= 32'd0;
      REG_WO_BASE <= 32'd0;
      REG_OUT_BASE <= 32'd0;
      REG_MEM_ADDR <= 32'd0;
      REG_MEM_WDATA <= 32'd0;
      REG_MEM_CTRL <= 32'd0;
      mem_wen <= 1'b0;
    end else begin
      mem_wen <= 1'b0;
      REG_STATUS <= {29'b0, stat_err, stat_done, stat_busy};
      REG_INT_ST <= {30'b0, err_irq, done_irq};

      if (S_AWVALID && S_WVALID && !S_BVALID) begin
        S_BVALID <= 1'b1;
        case (S_AWADDR[ADDR_W-1:2])
          6'h00: REG_CONTROL <= apply_wstrb(REG_CONTROL, S_WDATA, S_WSTRB);
          6'h02: REG_SEQ_LEN <= apply_wstrb(REG_SEQ_LEN, S_WDATA, S_WSTRB);
          6'h03: REG_D_MODEL <= apply_wstrb(REG_D_MODEL, S_WDATA, S_WSTRB);
          6'h04: REG_D_HEAD  <= apply_wstrb(REG_D_HEAD,  S_WDATA, S_WSTRB);
          6'h05: REG_SCORE_SHIFT <= apply_wstrb(REG_SCORE_SHIFT, S_WDATA, S_WSTRB);
          6'h06: REG_NORM_BIAS <= apply_wstrb(REG_NORM_BIAS, S_WDATA, S_WSTRB);
          6'h07: REG_INT_EN <= apply_wstrb(REG_INT_EN, S_WDATA, S_WSTRB);
          6'h09: REG_TOKEN_BASE_LO <= apply_wstrb(REG_TOKEN_BASE_LO, S_WDATA, S_WSTRB);
          6'h0A: REG_TOKEN_BASE_HI <= apply_wstrb(REG_TOKEN_BASE_HI, S_WDATA, S_WSTRB);
          6'h0B: REG_WQ_BASE <= apply_wstrb(REG_WQ_BASE, S_WDATA, S_WSTRB);
          6'h0C: REG_WK_BASE <= apply_wstrb(REG_WK_BASE, S_WDATA, S_WSTRB);
          6'h0D: REG_WV_BASE <= apply_wstrb(REG_WV_BASE, S_WDATA, S_WSTRB);
          6'h0E: REG_WO_BASE <= apply_wstrb(REG_WO_BASE, S_WDATA, S_WSTRB);
          6'h0F: REG_OUT_BASE <= apply_wstrb(REG_OUT_BASE, S_WDATA, S_WSTRB);
          6'h15: REG_MEM_ADDR <= apply_wstrb(REG_MEM_ADDR, S_WDATA, S_WSTRB);
          6'h16: begin
            REG_MEM_WDATA <= apply_wstrb(REG_MEM_WDATA, S_WDATA, S_WSTRB);
            mem_wen <= 1'b1;
          end
          6'h18: REG_MEM_CTRL <= apply_wstrb(REG_MEM_CTRL, S_WDATA, S_WSTRB);
          default: ;
        endcase
      end else if (S_BVALID && S_BREADY) begin
        S_BVALID <= 1'b0;
      end

      if (S_ARVALID && !S_RVALID) begin
        S_RVALID <= 1'b1;
        case (S_ARADDR[ADDR_W-1:2])
          6'h00: S_RDATA <= REG_CONTROL;
          6'h01: S_RDATA <= REG_STATUS;
          6'h02: S_RDATA <= REG_SEQ_LEN;
          6'h03: S_RDATA <= REG_D_MODEL;
          6'h04: S_RDATA <= REG_D_HEAD;
          6'h05: S_RDATA <= REG_SCORE_SHIFT;
          6'h06: S_RDATA <= REG_NORM_BIAS;
          6'h07: S_RDATA <= REG_INT_EN;
          6'h08: S_RDATA <= REG_INT_ST;
          6'h09: S_RDATA <= REG_TOKEN_BASE_LO;
          6'h0A: S_RDATA <= REG_TOKEN_BASE_HI;
          6'h0B: S_RDATA <= REG_WQ_BASE;
          6'h0C: S_RDATA <= REG_WK_BASE;
          6'h0D: S_RDATA <= REG_WV_BASE;
          6'h0E: S_RDATA <= REG_WO_BASE;
          6'h0F: S_RDATA <= REG_OUT_BASE;
          6'h10: S_RDATA <= HW_VERSION;
          6'h11: S_RDATA <= stat_cycles;
          6'h12: S_RDATA <= stat_macs;
          6'h13: S_RDATA <= stat_stalls;
          6'h15: S_RDATA <= REG_MEM_ADDR;
          6'h16: S_RDATA <= REG_MEM_WDATA;
          6'h17: S_RDATA <= mem_rdata;
          6'h18: S_RDATA <= REG_MEM_CTRL;
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
endmodule
