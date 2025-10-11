`timescale 1ns/1ps
module tb_rbm_core_min;
localparam I_DIM=256;
logic clk=0, rst=1, start; logic busy; logic [15:0] p_j;
// Memories to init
logic signed [7:0] v_mem [I_DIM];
logic signed [15:0] w_col [I_DIM];
logic signed [31:0] b_j;


// DUT
rbm_core_min #(.I_DIM(I_DIM)) dut(
.clk(clk), .rst(rst), .start(start), .busy(busy), .v_mem(v_mem), .w_col(w_col), .b_j(b_j), .p_j(p_j));


// Clock
always #5 clk=~clk; // 100 MHz


initial begin
$readmemh("vectors/v_mem.mem", v_mem);
$readmemh("vectors/w_col.mem", w_col);
$readmemh("vectors/bias.mem", b_j);
// LUT must exist at ../mem/sigmoid_q6p10_q0p16.mem relative to DUT
repeat(5) @(posedge clk);
rst=0; repeat(5) @(posedge clk);
start=1; @(posedge clk); start=0;
wait(!busy);
$display("p_j=0x%h", p_j);
// Not asserting a numerical check here since sigmoid LUT expected value not provided.
// You can extend by computing expected sigmoid in Python and storing expected_p.mem.
$finish;
end
endmodule
