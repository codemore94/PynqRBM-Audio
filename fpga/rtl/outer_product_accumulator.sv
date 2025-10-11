module outerprod_accum #(
  parameter I_TILE = 64,
  parameter H_TILE = 64
)(
  input  logic                   clk, rst,
  input  logic                   clr_pos, clr_neg,
  // streams of v and h probs for ONE sample, iterated across batch
  input  logic                   v_valid,
  input  logic  signed [7:0]     v_i   [I_TILE],   // Q1.7
  input  logic                   h_valid,
  input  logic  [15:0]           h_p   [H_TILE],   // Q0.16
  input  logic                   sample_last,      // last sample of batch
  // select which bank to write
  input  logic                   neg_phase,        // 0=pos,1=neg
  // BRAM interface (internal or expose for debug)
  output logic                   done
);
  // Accum BRAM: [I_TILE][H_TILE] of 32-bit signed (Q7.23)
  // Implement as 2D banking or linearized address = i*H_TILE + h
  // For each sample: for all i,h -> acc += v_i * h_p
  // Use nested loops time-multiplexed; PAR lanes if you like.
endmodule
