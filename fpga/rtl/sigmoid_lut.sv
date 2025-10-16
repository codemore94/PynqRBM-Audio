module sigmoid_lut #(
parameter IN_W = 16, // e.g., Q6.10 input
parameter OUT_W = 16, // Q0.16 output
parameter ADDR_W = 10 // 1024 entries
)(
input logic clk,
input logic signed [IN_W-1:0] x,
output logic [OUT_W-1:0] y
);
// Map x in [-6,6] to [0, 1023]
localparam signed X_MIN = -6 <<< 10; // if Q6.10
localparam signed X_MAX = 6 <<< 10;
logic [ADDR_W-1:0] addr;
logic [OUT_W-1:0] rom [0:(1<<ADDR_W)-1];
initial $readmemh("../mem/sigmoid_q6p10_q0p16.mem", rom);


logic signed [IN_W-1:0] x_clamped;
always_comb begin
x_clamped = (x < X_MIN) ? X_MIN : (x > X_MAX ? X_MAX : x);
addr = (x_clamped - X_MIN) >>> (10 - (ADDR_W-10)); // scale to 1024
end
always_ff @(posedge clk) y <= rom[addr];
endmodule
