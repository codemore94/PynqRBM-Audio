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
  // … clamp x to range and shift …
  // ROM init from .mem file
  logic [OUT_W-1:0] rom [0:(1<<ADDR_W)-1];
  initial $readmemh("sigmoid_q6p10_q0p16.mem", rom);
  always_ff @(posedge clk) y <= rom[addr];
endmodule
