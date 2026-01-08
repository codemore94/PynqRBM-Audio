`timescale 1ns/1ps

module tb_rbm_hidden_units;

  // === Tune these to your build ===
  localparam int I_DIM = 256;
  localparam int H_DIM = 64;

  logic clk = 0;
  logic rst = 1;
  logic start = 0;

  logic busy;
  logic done;

  // DUT-facing memories
  logic signed [7:0]   v_mem [0:I_DIM-1];
  logic signed [15:0]  w_mem [0:H_DIM-1][0:I_DIM-1];
  logic signed [31:0]  b_vec [0:H_DIM-1];
  logic [15:0]         p_vec [0:H_DIM-1];

  // File-load helpers (flattened arrays are easiest for $readmemh)
  logic [15:0] w_flat   [0:(H_DIM*I_DIM)-1];
  logic [31:0] b_flat   [0:H_DIM-1];
  logic [15:0] exp_p    [0:H_DIM-1];

  // Vector directory (override from command line with +VEC_DIR=...)
  string VEC_DIR = "sim/vectors/case_000";

  // Clock
  always #5 clk = ~clk; // 100 MHz

  // === DUT ===
  rbm_hidden_units #(.I_DIM(I_DIM), .H_DIM(H_DIM)) dut (
    .clk   (clk),
    .rst   (rst),
    .start (start),
    .busy  (busy),
    .done  (done),
    .v_mem (v_mem),
    .w_mem (w_mem),
    .b_vec (b_vec),
    .p_vec (p_vec)
  );

  // Load vectors from files
  task automatic load_vectors();
    int j, i;
    string path;

    begin
      if ($value$plusargs("VEC_DIR=%s", VEC_DIR)) begin
        $display("TB: Using VEC_DIR=%s", VEC_DIR);
      end else begin
        $display("TB: Using default VEC_DIR=%s", VEC_DIR);
      end

      // v_mem.mem: I_DIM lines of 2-hex-digit bytes (00..ff)
      path = {VEC_DIR, "/v_mem.mem"};
      $display("TB: Loading %s", path);
      $readmemh(path, v_mem);

      // w_mem.mem: (H_DIM*I_DIM) lines of 4-hex-digit words (0000..ffff),
      // flattened in order: w_flat[j*I_DIM + i] = W[j][i]
      path = {VEC_DIR, "/w_mem.mem"};
      $display("TB: Loading %s", path);
      $readmemh(path, w_flat);

      // bias_vec.mem: H_DIM lines of 8-hex-digit words (00000000..ffffffff)
      path = {VEC_DIR, "/bias_vec.mem"};
      $display("TB: Loading %s", path);
      $readmemh(path, b_flat);

      // expected_p.mem: H_DIM lines of 4-hex-digit words
      path = {VEC_DIR, "/expected_p.mem"};
      $display("TB: Loading %s", path);
      $readmemh(path, exp_p);

      // Unpack flattened weights into 2D array for DUT
      for (j = 0; j < H_DIM; j++) begin
        b_vec[j] = $signed(b_flat[j]);
        for (i = 0; i < I_DIM; i++) begin
          w_mem[j][i] = $signed(w_flat[j*I_DIM + i]);
        end
      end
    end
  endtask

  // Run one test case
  task automatic run_one();
    int j;
    int errors;

    begin
      errors = 0;

      // Reset
      rst = 1;
      start = 0;
      repeat (10) @(posedge clk);
      rst = 0;
      repeat (5) @(posedge clk);

      // Start pulse
      start = 1;
      @(posedge clk);
      start = 0;

      // Wait for completion
      // If your DUT doesn't have 'done', you can do:
      // wait(busy==1); wait(busy==0);
      wait (done == 1);
      @(posedge clk); // allow outputs to settle if done is a pulse

      // Check results
      for (j = 0; j < H_DIM; j++) begin
        if (p_vec[j] !== exp_p[j]) begin
          errors++;
          if (errors <= 10) begin
            $display("MISMATCH j=%0d got=%h exp=%h", j, p_vec[j], exp_p[j]);
          end
        end
      end

      if (errors == 0) begin
        $display("PASS: All %0d hidden outputs match expected.", H_DIM);
      end else begin
        $display("FAIL: %0d mismatches out of %0d outputs.", errors, H_DIM);
        $fatal(1);
      end
    end
  endtask

  initial begin
    load_vectors();
    run_one();
    $finish;
  end

endmodule
