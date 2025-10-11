module lfsr16(
input logic clk, rst,
input logic [15:0] seed,
output logic [15:0] rnd
);
logic [15:0] s;
always_ff @(posedge clk) begin
if (rst) s <= seed;
else s <= {s[14:0], s[15]^s[13]^s[12]^s[10]};
end
assign rnd = s;
endmodule
