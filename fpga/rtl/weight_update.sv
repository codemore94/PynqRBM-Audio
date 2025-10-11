module sgd_update_tile #(
  parameter I_TILE = 64,
  parameter H_TILE = 64
)(
  input  logic           clk, rst,
  input  logic  [15:0]   lr,          // Q0.16
  input  logic  [15:0]   mom,         // Q0.16
  input  logic  [15:0]   wd,          // Q0.16
  // Accumulator BRAM read ports
  input  logic  [31:0]   acc_pos_rd,
  input  logic  [31:0]   acc_neg_rd,
  // Previous update (for momentum) storage BRAM read/write
  input  logic  [15:0]   w_prev_upd_rd, // Q1.15
  output logic [15:0]    w_prev_upd_wr,
  output logic           w_prev_we,
  // Weight BRAM/DMA write
  input  logic  [15:0]   w_rd,        // current W (optional)
  output logic [15:0]    w_wr,        // updated W (Q1.15)
  output logic           w_we,
  output logic           done
);
  // For each (i,h):
  // d = acc_pos - acc_neg (Q7.23)
  // upd = mom*prev_upd + lr*d - wd*w
  //   scale shifts to align to Q1.15
  // w_new = sat(w + upd)
endmodule
