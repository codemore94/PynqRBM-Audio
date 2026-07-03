`timescale 1ns/1ps

module tb_rv_tiny_attn_rbm_soc_full;
  logic clk;
  logic resetn;
  logic uart_tx;
  logic uart_rx;
  logic rbm_irq;
  logic rbm_awvalid, rbm_awready, rbm_wvalid, rbm_wready, rbm_arvalid, rbm_arready;
  logic [31:0] rbm_awaddr, rbm_wdata, rbm_araddr;
  logic attn_awvalid, attn_awready, attn_wvalid, attn_wready, attn_arvalid, attn_arready;
  logic [31:0] attn_awaddr, attn_wdata, attn_araddr;
  logic tiny_done, rbm_done;
  logic [31:0] fw_stage, fw_rc;

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

`ifdef SYNTHESIS
  localparam FW_HEX_PATH = "../sw/rv_soc_full_fw.hex";
`else
  localparam FW_HEX_PATH = "sw/rv_soc_full_fw.hex";
`endif

  rv_rbm_soc #(
    .MEM_WORDS(4096),
    .UART_DIV(20),
    .RBM_I_DIM(8),
    .RBM_H_DIM(8),
    .ATTN_MAX_SEQ_LEN(4),
    .ATTN_MAX_D_MODEL(4),
    .FW_HEX(FW_HEX_PATH)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .uart_tx(uart_tx),
    .uart_rx(uart_rx),
    .rbm_irq(rbm_irq),
    .trace_rbm_awvalid(rbm_awvalid),
    .trace_rbm_awready(rbm_awready),
    .trace_rbm_awaddr(rbm_awaddr),
    .trace_rbm_wvalid(rbm_wvalid),
    .trace_rbm_wready(rbm_wready),
    .trace_rbm_wdata(rbm_wdata),
    .trace_rbm_arvalid(rbm_arvalid),
    .trace_rbm_arready(rbm_arready),
    .trace_rbm_araddr(rbm_araddr),
    .trace_attn_awvalid(attn_awvalid),
    .trace_attn_awready(attn_awready),
    .trace_attn_awaddr(attn_awaddr),
    .trace_attn_wvalid(attn_wvalid),
    .trace_attn_wready(attn_wready),
    .trace_attn_wdata(attn_wdata),
    .trace_attn_arvalid(attn_arvalid),
    .trace_attn_arready(attn_arready),
    .trace_attn_araddr(attn_araddr),
    .trace_tiny_done(tiny_done),
    .trace_rbm_done(rbm_done),
    .trace_fw_stage(fw_stage),
    .trace_fw_rc(fw_rc)
  );

`ifdef SYNTHESIS
  assign clk = 1'b0;
  assign resetn = 1'b0;
  assign uart_rx = 1'b1;
`else
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    resetn = 1'b0;
    uart_rx = 1'b1;
  end

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
      if (attn_arvalid && attn_arready && attn_araddr == 32'h0000_0040)
        saw_tiny_hw_version_read <= 1'b1;

      if (rbm_arvalid && rbm_arready && rbm_araddr == 32'h0000_0058)
        saw_rbm_hw_version_read <= 1'b1;

      if (attn_awvalid && attn_awready &&
          attn_wvalid && attn_wready &&
          attn_awaddr == 32'h0000_0000 &&
          attn_wdata[0]) begin
        tiny_start_count <= tiny_start_count + 1;
        $display("TB INFO tiny start count=%0d control=0x%08x time=%0t",
          tiny_start_count + 1, attn_wdata, $time);
        if (attn_wdata[2])
          saw_tiny_train <= 1'b1;
      end

      if (attn_awvalid && attn_awready &&
          attn_wvalid && attn_wready &&
          attn_awaddr == 32'h0000_0060 &&
          attn_wdata[2:0] == 3'd7) begin
        saw_tiny_adapt_write <= 1'b1;
        $display("TB INFO tiny adapt window selected time=%0t", $time);
      end

      if (tiny_done && !prev_tiny_done) begin
        saw_tiny_done <= 1'b1;
        $display("TB INFO tiny done time=%0t", $time);
      end
      prev_tiny_done <= tiny_done;

      if (rbm_awvalid && rbm_awready &&
          rbm_wvalid && rbm_wready &&
          rbm_awaddr == 32'h0000_0000 &&
          rbm_wdata[0]) begin
        saw_rbm_start <= 1'b1;
        $display("TB INFO rbm start control=0x%08x time=%0t", rbm_wdata, $time);
      end

      if (rbm_irq) begin
        saw_rbm_irq <= 1'b1;
        $display("TB INFO rbm irq time=%0t", $time);
      end

      if (rbm_done && !prev_rbm_done) begin
        rbm_done_count <= rbm_done_count + 1;
        $display("TB INFO rbm done count=%0d time=%0t", rbm_done_count + 1, $time);
      end
      prev_rbm_done <= rbm_done;
    end
  end

  initial begin
    repeat (10) @(posedge clk);
    resetn = 1'b1;

    repeat (2500000) begin
      @(posedge clk);
      if (fw_stage != prev_fw_stage || fw_rc != prev_fw_rc) begin
        $display("TB INFO fw stage=%0d rc=%0d time=%0t",
          fw_stage, fw_rc, $time);
        prev_fw_stage = fw_stage;
        prev_fw_rc = fw_rc;
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
      fw_stage, fw_rc);
    $fatal(1);
  end
`endif
endmodule
