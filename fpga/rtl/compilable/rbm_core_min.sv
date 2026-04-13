// Minimal forward GEMV + sigmoid for bring-up (one hidden at a time)
module rbm_core_min #(
  parameter int I_DIM = 256
)(
  input  logic                 clk,
  input  logic                 rst,
  input  logic                 start,
  output logic                 busy,
  // Frame buffer port (Q1.7)
  input  logic signed [7:0]    v_mem [0:I_DIM-1],
  // Weight port for selected hidden j (Q1.15)
  input  logic signed [15:0]   w_col [0:I_DIM-1],
  input  logic signed [31:0]   b_j,
  output logic [15:0]          p_j
);
  localparam int I_IDX_W = (I_DIM > 1) ? $clog2(I_DIM) : 1;

  typedef enum logic [1:0] {IDLE, ACC, ACT} st_t;
  st_t st;
  logic [I_IDX_W-1:0] i;
  logic signed [31:0] acc;
  logic signed [23:0] prod;
  logic [15:0] sig_y;

  assign busy = (st != IDLE);
  assign prod = $signed(v_mem[i]) * $signed(w_col[i]);
  sigmoid_lut u_sig(.clk(clk), .x(acc[21:6]), .y(sig_y));

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= IDLE;
      i <= '0;
      acc <= '0;
      p_j <= '0;
    end else begin
      case (st)
        IDLE: begin
          if (start) begin
            i <= '0;
            acc <= b_j;
            st <= ACC;
          end
        end
        ACC: begin
          acc <= acc + {{8{prod[23]}}, prod};
          if (i == I_DIM-1) begin
            st <= ACT;
          end else begin
            i <= i + 1'b1;
          end
        end
        ACT: begin
          p_j <= sig_y;
          st <= IDLE;
        end
        default: st <= IDLE;
      endcase
    end
  end
endmodule
