
## `fpga/rtl/sgd_update_tile.sv`

```systemverilog
module sgd_update_tile #(
  parameter I_TILE = 64,
  parameter H_TILE = 64
)(
  input  logic           clk, rst,
  input  logic [15:0]    lr,   // Q0.16
  input  logic [15:0]    mom,  // Q0.16
  input  logic [15:0]    wd,   // Q0.16
  input  logic           start,
  output logic           busy,
  output logic           done,
  // BRAM-style read ports for accumulators (provided by a wrapper)
  input  logic signed [31:0] acc_pos_d, acc_neg_d,
  output logic [15:0]    acc_addr,     // 0..I_TILE*H_TILE-1
  // Weight read-modify-write stream
  input  logic signed [15:0] w_d,      // Q1.15 current
  output logic [15:0]    w_addr,
  output logic signed [15:0] w_q,      // Q1.15 updated
  output logic           w_we
);
  localparam N = I_TILE*H_TILE;
  logic [15:0] idx;
  typedef enum logic [1:0] {IDLE, RUN, FIN} st_t; st_t st;
  assign busy = (st==RUN);

  // Simple momentum buffer can be externalized; here we ignore for brevity

  always_ff @(posedge clk) begin
    if (rst) begin st <= IDLE; done <= 1'b0; idx<=0; w_we<=1'b0; end
    else begin
      done <= 1'b0; w_we<=1'b0;
      unique case(st)
        IDLE: if (start) begin idx<=0; st<=RUN; end
        RUN: begin
          // d = acc_pos - acc_neg  (Q7.23)
          logic signed [31:0] d = acc_pos_d - acc_neg_d;
          // upd = lr * d  (Q0.16 * Q7.23 -> Q7.39 -> >>16 -> Q7.23)
          logic signed [39:0] mul = $signed({{8{d[31]}},d}) * $signed({1'b0,lr});
          logic signed [31:0] upd = mul[39:8]; // >>16
          // weight decay: w = (1 - wd)*w  ~ w - wd*w
          logic signed [31:0] wd_mul = $signed({{16{w_d[15]}},w_d}) * $signed(wd); // Q1.31
          logic signed [31:0] wd_term= wd_mul >>> 16; // Q1.15 align
          logic signed [31:0] w_ext  = {{16{w_d[15]}}, w_d};
          logic signed [31:0] w_new  = w_ext + (upd >>> 8) - wd_term; // rescale to ~Q1.15
          // saturate to 16-bit
          logic signed [15:0] sat;
          if (w_new >  32767) sat = 16'sd32767;
          else if (w_new < -32768) sat = -16'sd32768;
          else sat = w_new[15:0];

          w_q   <= sat;
          w_addr<= idx;
          w_we  <= 1'b1;

          acc_addr <= idx;
          idx <= idx + 1;
          if (idx == N-1) st<=FIN;
        end
        FIN: begin done<=1'b1; st<=IDLE; end
      endcase
    end
  end
endmodule
```
