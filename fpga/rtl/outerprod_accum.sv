module outerprod_accum #(
parameter I_TILE = 64,
parameter H_TILE = 64
)(
input logic clk, rst,
input logic clr_pos,
input logic clr_neg,
input logic neg_phase, // 0=pos 1=neg
input logic sample_valid,
input logic signed [7:0] v_i [I_TILE], // Q1.7
input logic [15:0] h_p [H_TILE], // Q0.16
input logic last_sample,
output logic done
);
// Linearized accum array: I_TILE*H_TILE of 32-bit signed (Q7.23)
localparam N = I_TILE*H_TILE;
logic signed [31:0] acc_pos [0:N-1];
logic signed [31:0] acc_neg [0:N-1];


// Clear
integer idx;
typedef enum logic [1:0] {IDLE, ACCUM, FIN} st_t;
st_t st;


always_ff @(posedge clk) begin
if (rst) begin
st <= IDLE; done <= 1'b0;
for (idx=0; idx<N; idx++) begin
acc_pos[idx] <= '0; acc_neg[idx] <= '0;
end
end else begin
done <= 1'b0;
if (clr_pos) for (idx=0; idx<N; idx++) acc_pos[idx] <= '0;
if (clr_neg) for (idx=0; idx<N; idx++) acc_neg[idx] <= '0;
case (st)
IDLE: if (sample_valid) st <= ACCUM;
ACCUM: begin
// time-multiplexed nested loop: unrolled lightly here
for (int i=0;i<I_TILE;i++) begin
for (int h=0; h<H_TILE; h++) begin
automatic int a = i*H_TILE + h;
// v_i(Q1.7)*h_p(Q0.16) => Q1.23
logic signed [23:0] prod = $signed({{8{v_i[i][7]}},v_i[i]}) * $signed(h_p[h]);
logic signed [31:0] ext = {{8{prod[23]}},prod};
if (!neg_phase) acc_pos[a] <= acc_pos[a] + ext; else acc_neg[a] <= acc_neg[a] + ext;
end
end
if (last_sample) begin st <= FIN; end
end
FIN: begin done <= 1'b1; st <= IDLE; end
endcase
end
end
endmodule
