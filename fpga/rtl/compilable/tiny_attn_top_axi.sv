// Tiny self-attention top-level with AXI-Lite CSR and memory windows.
module tiny_attn_top_axi #(
  parameter integer MAX_SEQ_LEN = 8,
  parameter integer MAX_D_MODEL = 8
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
  output logic           irq
);
  logic ctrl_start;
  logic ctrl_soft_rst;
  logic ctrl_mode_train;
  logic ctrl_mode_full_bp;
  logic ctrl_use_out_proj;
  logic ctrl_causal;
  logic [15:0] seq_len;
  logic [15:0] d_model;
  logic [15:0] d_head;
  logic [7:0]  score_shift;
  logic [15:0] norm_bias;
  logic [31:0] token_base_lo, token_base_hi;
  logic [31:0] wq_base, wk_base, wv_base, wo_base, out_base;
  logic stat_busy, stat_done, stat_err;
  logic [31:0] stat_cycles, stat_macs, stat_stalls;
  logic [31:0] mem_addr, mem_wdata, mem_rdata;
  logic mem_wen;
  logic [2:0] mem_sel;

  tiny_attn_ctrl_axi u_ctrl (
    .ACLK(ACLK),
    .ARESETn(ARESETn),
    .S_AWADDR(S_AWADDR), .S_AWVALID(S_AWVALID), .S_AWREADY(S_AWREADY),
    .S_WDATA(S_WDATA), .S_WSTRB(S_WSTRB), .S_WVALID(S_WVALID), .S_WREADY(S_WREADY),
    .S_BRESP(S_BRESP), .S_BVALID(S_BVALID), .S_BREADY(S_BREADY),
    .S_ARADDR(S_ARADDR), .S_ARVALID(S_ARVALID), .S_ARREADY(S_ARREADY),
    .S_RDATA(S_RDATA), .S_RRESP(S_RRESP), .S_RVALID(S_RVALID), .S_RREADY(S_RREADY),
    .ctrl_start(ctrl_start),
    .ctrl_soft_rst(ctrl_soft_rst),
    .ctrl_mode_train(ctrl_mode_train),
    .ctrl_mode_full_bp(ctrl_mode_full_bp),
    .ctrl_use_out_proj(ctrl_use_out_proj),
    .ctrl_causal(ctrl_causal),
    .seq_len(seq_len),
    .d_model(d_model),
    .d_head(d_head),
    .score_shift(score_shift),
    .norm_bias(norm_bias),
    .token_base_lo(token_base_lo),
    .token_base_hi(token_base_hi),
    .wq_base(wq_base),
    .wk_base(wk_base),
    .wv_base(wv_base),
    .wo_base(wo_base),
    .out_base(out_base),
    .stat_busy(stat_busy),
    .stat_done(stat_done),
    .stat_err(stat_err),
    .stat_cycles(stat_cycles),
    .stat_macs(stat_macs),
    .stat_stalls(stat_stalls),
    .irq(irq),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wen(mem_wen),
    .mem_sel(mem_sel),
    .mem_rdata(mem_rdata)
  );

  wire unused_bases = ^{token_base_lo, token_base_hi, wq_base, wk_base, wv_base, wo_base, out_base, 1'b0};

  tiny_attn_core #(
    .MAX_SEQ_LEN(MAX_SEQ_LEN),
    .MAX_D_MODEL(MAX_D_MODEL)
  ) u_core (
    .clk(ACLK),
    .resetn(ARESETn),
    .ctrl_start(ctrl_start),
    .ctrl_soft_rst(ctrl_soft_rst),
    .ctrl_mode_train(ctrl_mode_train),
    .ctrl_mode_full_bp(ctrl_mode_full_bp),
    .ctrl_use_out_proj(ctrl_use_out_proj),
    .ctrl_causal(ctrl_causal),
    .seq_len(seq_len),
    .d_model(d_model),
    .d_head(d_head),
    .score_shift(score_shift),
    .norm_bias(norm_bias),
    .stat_busy(stat_busy),
    .stat_done(stat_done),
    .stat_err(stat_err),
    .stat_cycles(stat_cycles),
    .stat_macs(stat_macs),
    .stat_stalls(stat_stalls),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wen(mem_wen),
    .mem_sel(mem_sel),
    .mem_rdata(mem_rdata)
  );
endmodule
