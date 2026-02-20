module sigmoid_lut #(
  parameter IN_W = 16, // e.g., Q6.10
  parameter OUT_W = 16,
  parameter ADDR_W = 10 // 1024 entries
)(
  input  logic               clk,
  input  logic [IN_W-1:0]    x,
  output logic [OUT_W-1:0]   y
);
  // address by clamping and dropping LSBs (piecewise-constant)
  logic [ADDR_W-1:0] addr;
  // Map signed input to unsigned address space by biasing and dropping LSBs.
  // This is a generic mapping; ensure your LUT matches this convention.
  logic signed [IN_W-1:0] x_s;
  logic [IN_W-1:0] x_u;
  always_comb begin
    x_s = x;
    x_u = x_s + (1 << (IN_W-1));
    addr = x_u[IN_W-1 -: ADDR_W];
  end
  // ROM init from .mem file
  logic [OUT_W-1:0] rom [0:(1<<ADDR_W)-1];
  initial $readmemh("sigmoid_q6p10_q0p16.mem", rom);
  always_ff @(posedge clk) y <= rom[addr];
endmodule
