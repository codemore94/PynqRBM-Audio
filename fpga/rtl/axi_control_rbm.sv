module rbm_ctrl_axi_lite #(
  parameter AW = 6 // 64B space (expand as needed)
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

  // Control outputs
  output logic           start,
  output logic           soft_reset,
  output logic           use_sampling,
  output logic [15:0]    frame_len,
  output logic [15:0]    i_dim,
  output logic [15:0]    h_dim,
  output logic [7:0]     k_dim,
  output logic [4:0]     scale_shift,
  output logic [15:0]    rng_seed,
  output logic           ie_done,
  // Status inputs
  input  logic           busy,
  input  logic           done,
  input  logic           error,
  output logic           irq
);
// … standard AXI-Lite reg file implementation; raise irq when done & ie_done …
if(done && ie_done)begin
   irq <= 1'b1;
end
endmodule
