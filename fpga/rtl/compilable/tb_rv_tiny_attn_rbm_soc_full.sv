`timescale 1ns/1ps

module tb_rv_tiny_attn_rbm_soc_full;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic uart_tx;
  logic uart_rx = 1'b1;
  logic rbm_irq;

  logic saw_tiny_hw_version_read = 1'b0;
  logic saw_rbm_hw_version_read = 1'b0;
  integer tiny_start_count = 0;
  logic saw_tiny_done = 1'b0;
  logic saw_tiny_train = 1'b0;
  logic saw_tiny_adapt_write = 1'b0;
  logic saw_rbm_start = 1'b0;
  logic saw_rbm_irq = 1'b0;
  logic prev_rbm_done = 1'b0;
  logic prev_tiny_done = 1'b0;
  reg [31:0] prev_fw_stage = 32'b0;
  reg [31:0] prev_fw_rc = 32'b0;
  integer rbm_done_count = 0;

  rv_rbm_soc #(
    .MEM_WORDS(4096),
    .UART_DIV(20),
    .RBM_I_DIM(8),
    .RBM_H_DIM(8),
    .ATTN_MAX_SEQ_LEN(4),
    .ATTN_MAX_D_MODEL(4),
    .FW_HEX("sw/rv_soc_full_fw.hex")
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .uart_tx(uart_tx),
    .uart_rx(uart_rx),
    .rbm_irq(rbm_irq)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      saw_tiny_hw_version_read <= 1'b0;
      saw_rbm_hw_version_read <= 1'b0;
      tiny_start_count <= 0;
      saw_tiny_done <= 1'b0;
      saw_tiny_train <= 1'b0;
      saw_tiny_adapt_write <= 1'b0;
      saw_rbm_start <= 1'b0;
      saw_rbm_irq <= 1'b0;
      prev_rbm_done <= 1'b0;
      prev_tiny_done <= 1'b0;
      rbm_done_count <= 0;
    end else begin
      if (dut.attn_arvalid && dut.attn_arready && dut.attn_araddr == 32'h0000_0040)
        saw_tiny_hw_version_read <= 1'b1;

      if (dut.rbm_arvalid && dut.rbm_arready && dut.rbm_araddr == 32'h0000_0058)
        saw_rbm_hw_version_read <= 1'b1;

      if (dut.attn_awvalid && dut.attn_awready &&
          dut.attn_wvalid && dut.attn_wready &&
          dut.attn_awaddr == 32'h0000_0000 &&
          dut.attn_wdata[0]) begin
        tiny_start_count <= tiny_start_count + 1;
        $display("TB INFO tiny start count=%0d control=0x%08x time=%0t",
          tiny_start_count + 1, dut.attn_wdata, $time);
        if (dut.attn_wdata[2])
          saw_tiny_train <= 1'b1;
      end

      if (dut.attn_awvalid && dut.attn_awready &&
          dut.attn_wvalid && dut.attn_wready &&
          dut.attn_awaddr == 32'h0000_0060 &&
          dut.attn_wdata[2:0] == 3'd7) begin
        saw_tiny_adapt_write <= 1'b1;
        $display("TB INFO tiny adapt window selected time=%0t", $time);
      end

      if (dut.u_attn.u_core.stat_done && !prev_tiny_done) begin
        saw_tiny_done <= 1'b1;
        $display("TB INFO tiny done time=%0t", $time);
      end
      prev_tiny_done <= dut.u_attn.u_core.stat_done;

      if (dut.rbm_awvalid && dut.rbm_awready &&
          dut.rbm_wvalid && dut.rbm_wready &&
          dut.rbm_awaddr == 32'h0000_0000 &&
          dut.rbm_wdata[0]) begin
        saw_rbm_start <= 1'b1;
        $display("TB INFO rbm start control=0x%08x time=%0t", dut.rbm_wdata, $time);
      end

      if (rbm_irq) begin
        saw_rbm_irq <= 1'b1;
        $display("TB INFO rbm irq time=%0t", $time);
      end

      if (dut.u_rbm.done_latch && !prev_rbm_done) begin
        rbm_done_count <= rbm_done_count + 1;
        $display("TB INFO rbm done count=%0d time=%0t", rbm_done_count + 1, $time);
      end
      prev_rbm_done <= dut.u_rbm.done_latch;
    end
  end

  initial begin
    repeat (10) @(posedge clk);
    resetn = 1'b1;

    repeat (2500000) begin
      @(posedge clk);
      if (dut.ram[16'h3f00 >> 2] != prev_fw_stage || dut.ram[16'h3f04 >> 2] != prev_fw_rc) begin
        $display("TB INFO fw stage=%0d rc=%0d time=%0t",
          dut.ram[16'h3f00 >> 2], dut.ram[16'h3f04 >> 2], $time);
        prev_fw_stage = dut.ram[16'h3f00 >> 2];
        prev_fw_rc = dut.ram[16'h3f04 >> 2];
      end
      if (saw_tiny_hw_version_read && saw_rbm_hw_version_read &&
          tiny_start_count >= 3 && saw_tiny_done &&
          saw_tiny_train && saw_tiny_adapt_write &&
          saw_rbm_start && saw_rbm_irq &&
          rbm_done_count == 1) begin
        $display("FULL SOC PASS: tiny_hw=%0d rbm_hw=%0d tiny_starts=%0d tiny_done=%0d tiny_train=%0d tiny_adapt=%0d rbm_start=%0d rbm_irq=%0d rbm_done=%0d",
          saw_tiny_hw_version_read, saw_rbm_hw_version_read, tiny_start_count, saw_tiny_done,
          saw_tiny_train, saw_tiny_adapt_write, saw_rbm_start, saw_rbm_irq, rbm_done_count);
        $finish;
      end
    end

    $display("FULL SOC FAIL: tiny_hw=%0d rbm_hw=%0d tiny_starts=%0d tiny_done=%0d tiny_train=%0d tiny_adapt=%0d rbm_start=%0d rbm_irq=%0d rbm_done=%0d",
      saw_tiny_hw_version_read, saw_rbm_hw_version_read, tiny_start_count, saw_tiny_done,
      saw_tiny_train, saw_tiny_adapt_write, saw_rbm_start, saw_rbm_irq, rbm_done_count);
    $display("FULL SOC FW STATE: stage=%0d rc=%0d",
      dut.ram[16'h3f00 >> 2], dut.ram[16'h3f04 >> 2]);
    $fatal(1);
  end
endmodule
