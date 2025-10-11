// Minimal forward GEMV + sigmoid for bring-up (one hidden at a time)
module rbm_core_min #(
parameter I_DIM = 256
)(
input logic clk, rst,
input logic start,
output logic busy,
// Frame buffer port
input logic signed [7:0] v_mem [I_DIM], // Q1.7
// Weight port for selected hidden j (provided by wrapper)
input logic signed [15:0] w_col [I_DIM], // Q1.15
input logic signed [31:0] b_j, // bias aligned
output logic [15:0] p_j // Q0.16
);
logic [15:0] i;
logic signed [31:0] acc;
typedef enum logic [1:0] {IDLE, ACC, ACT} st_t; st_t st;
assign busy = (st!=IDLE);
logic [15:0] sig_y;
sigmoid_lut u_sig(.clk(clk), .x(acc[21:6]), .y(sig_y)); // crude mapping


always_ff @(posedge clk) begin
if (rst) begin st<=IDLE; i<=0; acc<=0; end
else begin
case(st)
IDLE: if (start) begin i<=0; acc<=b_j; st<=ACC; end
ACC: begin
// acc += v[i]*w[i]
logic signed [23:0] prod = $signed({{8{v_mem[i][7]}},v_mem[i]}) * $signed(w_col[i]);
acc <= acc + {{8{prod[23]}},prod};
i <= i + 1;
if (i==I_DIM-1) st<=ACT;
end
ACT: begin
p_j <= sig_y; st<=IDLE;
end
endcase
end
end
endmodule
