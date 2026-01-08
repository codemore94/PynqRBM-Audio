`timescale 1ns/1ps

module rbm_hidden_units #(
  parameter int I_DIM = 256,
  parameter int H_DIM = 64,

  // Map 32-bit accumulator -> sigmoid LUT input.
  // Default matches your earlier rbm_core_min example: x = acc[21:6]
  parameter int LUT_SLICE_LSB = 6
)(
  input  logic clk, rst, start,
  output logic busy, done,

  input  logic signed [7:0]   v_mem [0:I_DIM-1],
  input  logic signed [15:0]  w_mem [0:H_DIM-1][0:I_DIM-1],
  input  logic signed [31:0]  b_vec [0:H_DIM-1],
  output logic [15:0]         p_vec [0:H_DIM-1]
);

  // --------------------------
  // State machine
  // --------------------------
  typedef enum logic [2:0] {
    S_IDLE      = 3'd0,
    S_INIT_NEUR = 3'd1,
    S_ACC       = 3'd2,
    S_LUT_WAIT  = 3'd3,
    S_WRITE     = 3'd4,
    S_DONE_PLS  = 3'd5
  } state_t;

  state_t st;

  // Indices
  logic [$clog2(I_DIM)-1:0] i_idx;
  logic [$clog2(H_DIM)-1:0] j_idx;

  // Accumulator
  logic signed [31:0] acc;

  // Product (declare outside always_ff to keep tools happy)
  logic signed [23:0] prod;
  logic signed [31:0] prod_ext;
  logic signed [31:0] acc_sum;

  // Sigmoid LUT I/O (assume synchronous LUT: y updates on clk)
  logic [15:0] lut_x;
  logic [15:0] lut_y;

  // Shared LUT instance
  sigmoid_lut u_sig (
    .clk(clk),
    .x  (lut_x),
    .y  (lut_y)
  );

  // Combinational helpers for MAC
  always_comb begin
    prod     = $signed(v_mem[i_idx]) * $signed(w_mem[j_idx][i_idx]); // 8x16 -> 24
    prod_ext = {{8{prod[23]}}, prod};                                 // sign-extend to 32
    acc_sum  = acc + prod_ext;
  end

  // Outputs
  always_comb begin
    busy = (st != S_IDLE) && (st != S_DONE_PLS);
  end

  // Main sequential logic
  integer k;
  always_ff @(posedge clk) begin
    if (rst) begin
      st   <= S_IDLE;
      i_idx <= '0;
      j_idx <= '0;
      acc  <= '0;
      lut_x <= '0;
      done <= 1'b0;

      // Optional: clear outputs on reset (good for sim sanity)
      for (k = 0; k < H_DIM; k++) begin
        p_vec[k] <= '0;
      end
    end else begin
      done <= 1'b0; // default: pulse only in S_DONE_PLS

      case (st)
        // --------------------------
        S_IDLE: begin
          if (start) begin
            j_idx <= '0;
            st    <= S_INIT_NEUR;
          end
        end

        // --------------------------
        // Initialize accumulator for neuron j
        S_INIT_NEUR: begin
          i_idx <= '0;
          acc   <= b_vec[j_idx];
          st    <= S_ACC;
        end

        // --------------------------
        // Accumulate dot product for current neuron j
        S_ACC: begin
          // accumulate current i
          acc <= acc_sum;

          // If last i, also launch LUT input based on *acc_sum* (includes last product)
          if (i_idx == I_DIM-1) begin
            // Slice acc_sum to 16-bit for LUT input
            // Default: [21:6] when LUT_SLICE_LSB=6
            lut_x <= acc_sum[LUT_SLICE_LSB + 15 -: 16];
            st    <= S_LUT_WAIT;
          end else begin
            i_idx <= i_idx + 1;
          end
        end

        // --------------------------
        // Wait 1 cycle for synchronous LUT output
        S_LUT_WAIT: begin
          st <= S_WRITE;
        end

        // --------------------------
        // Write probability output for neuron j
        S_WRITE: begin
          p_vec[j_idx] <= lut_y;

          if (j_idx == H_DIM-1) begin
            st <= S_DONE_PLS;
          end else begin
            j_idx <= j_idx + 1;
            st    <= S_INIT_NEUR;
          end
        end

        // --------------------------
        // Pulse done for one cycle then return idle
        S_DONE_PLS: begin
          done <= 1'b1;
          st   <= S_IDLE;
        end

        default: st <= S_IDLE;
      endcase
    end
  end

endmodule
