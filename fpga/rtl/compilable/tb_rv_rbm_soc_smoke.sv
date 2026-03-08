`timescale 1ns/1ps

module tb_rv_rbm_soc_smoke;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic uart_tx;
  logic uart_rx = 1'b1;
  logic rbm_irq;
  logic saw_hw_version_read = 1'b0;
  logic saw_control_start_write = 1'b0;
  logic saw_done = 1'b0;

  rv_rbm_soc #(
    .MEM_WORDS(4096),
    .UART_DIV(20)
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
      saw_hw_version_read <= 1'b0;
      saw_control_start_write <= 1'b0;
      saw_done <= 1'b0;
    end else begin
      // HW_VERSION read at RBM offset 0x58.
      if (dut.rbm_arvalid && dut.rbm_arready && dut.rbm_araddr == 32'h0000_0058) begin
        saw_hw_version_read <= 1'b1;
      end

      // CONTROL write with START bit set at RBM offset 0x00.
      if (dut.rbm_awvalid && dut.rbm_awready &&
          dut.rbm_wvalid && dut.rbm_wready &&
          dut.rbm_awaddr == 32'h0000_0000 &&
          dut.rbm_wdata[0]) begin
        saw_control_start_write <= 1'b1;
      end

      if (dut.u_rbm.done_latch) begin
        saw_done <= 1'b1;
      end
    end
  end

  initial begin
    repeat (10) @(posedge clk);
    resetn = 1'b1;
    repeat (200000) begin
      @(posedge clk);
      if (saw_hw_version_read && saw_control_start_write && saw_done) begin
        $display("SOC FW PASS: hwver_read=%0d start_write=%0d done=%0d",
          saw_hw_version_read, saw_control_start_write, saw_done);
        $finish;
      end
    end
    $display("SOC FW FAIL: hwver_read=%0d start_write=%0d done=%0d rbm_irq=%0d",
      saw_hw_version_read, saw_control_start_write, saw_done, rbm_irq);
    $fatal(1);
    $finish;
  end
endmodule
