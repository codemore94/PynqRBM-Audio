`timescale 1ns/1ps

module tb_tiny_attn_top_axi;
  localparam MAX_SEQ_LEN = 4;
  localparam MAX_D_MODEL = 4;

  logic clk = 1'b0;
  logic rstn = 1'b0;

  logic [31:0] S_AWADDR;
  logic        S_AWVALID;
  logic        S_AWREADY;
  logic [31:0] S_WDATA;
  logic [3:0]  S_WSTRB;
  logic        S_WVALID;
  logic        S_WREADY;
  logic [1:0]  S_BRESP;
  logic        S_BVALID;
  logic        S_BREADY;
  logic [31:0] S_ARADDR;
  logic        S_ARVALID;
  logic        S_ARREADY;
  logic [31:0] S_RDATA;
  logic [1:0]  S_RRESP;
  logic        S_RVALID;
  logic        S_RREADY;
  logic        irq;

  tiny_attn_top_axi #(
    .MAX_SEQ_LEN(MAX_SEQ_LEN),
    .MAX_D_MODEL(MAX_D_MODEL)
  ) dut (
    .ACLK(clk),
    .ARESETn(rstn),
    .S_AWADDR(S_AWADDR), .S_AWVALID(S_AWVALID), .S_AWREADY(S_AWREADY),
    .S_WDATA(S_WDATA), .S_WSTRB(S_WSTRB), .S_WVALID(S_WVALID), .S_WREADY(S_WREADY),
    .S_BRESP(S_BRESP), .S_BVALID(S_BVALID), .S_BREADY(S_BREADY),
    .S_ARADDR(S_ARADDR), .S_ARVALID(S_ARVALID), .S_ARREADY(S_ARREADY),
    .S_RDATA(S_RDATA), .S_RRESP(S_RRESP), .S_RVALID(S_RVALID), .S_RREADY(S_RREADY),
    .irq(irq)
  );

  always #5 clk = ~clk;

  task automatic axi_write(input [31:0] addr, input [31:0] data);
    begin
      @(posedge clk);
      S_AWADDR  <= addr;
      S_AWVALID <= 1'b1;
      S_WDATA   <= data;
      S_WSTRB   <= 4'hf;
      S_WVALID  <= 1'b1;
      S_BREADY  <= 1'b1;
      wait (S_AWREADY && S_WREADY);
      @(posedge clk);
      S_AWVALID <= 1'b0;
      S_WVALID  <= 1'b0;
      wait (S_BVALID);
      @(posedge clk);
      S_BREADY <= 1'b0;
    end
  endtask

  task automatic axi_read(input [31:0] addr, output [31:0] data);
    begin
      @(posedge clk);
      S_ARADDR  <= addr;
      S_ARVALID <= 1'b1;
      S_RREADY  <= 1'b1;
      wait (S_ARREADY);
      @(posedge clk);
      S_ARVALID <= 1'b0;
      wait (S_RVALID);
      data = S_RDATA;
      @(posedge clk);
      S_RREADY <= 1'b0;
    end
  endtask

  localparam REG_CONTROL     = 32'h00;
  localparam REG_STATUS      = 32'h04;
  localparam REG_SEQ_LEN     = 32'h08;
  localparam REG_D_MODEL     = 32'h0C;
  localparam REG_D_HEAD      = 32'h10;
  localparam REG_SCORE_SHIFT = 32'h14;
  localparam REG_NORM_BIAS   = 32'h18;
  localparam REG_HW_VERSION  = 32'h40;
  localparam REG_PERF_CYCLES = 32'h44;
  localparam REG_PERF_MACS   = 32'h48;
  localparam REG_MEM_ADDR    = 32'h54;
  localparam REG_MEM_WDATA   = 32'h58;
  localparam REG_MEM_RDATA   = 32'h5C;
  localparam REG_MEM_CTRL    = 32'h60;
  localparam [15:0] ADAPT_ROW_GAIN = 16'hfffe;
  localparam [15:0] ADAPT_ROW_BIAS = 16'hffff;

  function automatic [31:0] addr2d(input [15:0] row, input [15:0] col);
    begin
      addr2d = {row, col};
    end
  endfunction

  task automatic mem_write(input [2:0] sel, input [31:0] addr, input [31:0] data);
    begin
      axi_write(REG_MEM_CTRL, {29'b0, sel});
      axi_write(REG_MEM_ADDR, addr);
      axi_write(REG_MEM_WDATA, data);
    end
  endtask

  task automatic mem_read(input [2:0] sel, input [31:0] addr, output [31:0] data);
    begin
      axi_write(REG_MEM_CTRL, {29'b0, sel});
      axi_write(REG_MEM_ADDR, addr);
      axi_read(REG_MEM_RDATA, data);
    end
  endtask

  integer r;
  reg [31:0] rdata;
  reg [31:0] perf_cycles;
  reg [31:0] perf_macs;
  reg [31:0] out00_before;
  reg [31:0] out01_before;
  reg [31:0] out10_before;
  reg [31:0] out11_before;
  reg [31:0] gain0_after;
  reg [31:0] bias0_after;
  reg [31:0] fullbp_out00_before;
  reg [31:0] fullbp_out00_after;
  reg [31:0] wq00_after;
  reg [31:0] wk00_after;
  reg [31:0] wv00_after;
  reg [31:0] wo00_after;

  initial begin
    S_AWADDR = 0; S_AWVALID = 0; S_WDATA = 0; S_WSTRB = 0; S_WVALID = 0; S_BREADY = 0;
    S_ARADDR = 0; S_ARVALID = 0; S_RREADY = 0;

    repeat (5) @(posedge clk);
    rstn = 1'b1;
    repeat (5) @(posedge clk);

    axi_read(REG_HW_VERSION, rdata);
    if (rdata !== 32'h0001_1000)
      $fatal(1, "HW_VERSION mismatch: got 0x%08x", rdata);

    axi_write(REG_SEQ_LEN, 32'd2);
    axi_write(REG_D_MODEL, 32'd2);
    axi_write(REG_D_HEAD, 32'd2);
    axi_write(REG_SCORE_SHIFT, 32'd0);
    axi_write(REG_NORM_BIAS, 32'd1);

    // Tokens: [3,1], [1,3]
    mem_write(3'd0, addr2d(16'd0, 16'd0), 32'd3);
    mem_write(3'd0, addr2d(16'd0, 16'd1), 32'd1);
    mem_write(3'd0, addr2d(16'd1, 16'd0), 32'd1);
    mem_write(3'd0, addr2d(16'd1, 16'd1), 32'd3);

    // Identity WQ, WK, WV
    for (r = 0; r < 2; r = r + 1) begin
      mem_write(3'd1, addr2d(r[15:0], 16'd0), (r == 0) ? 32'd1 : 32'd0);
      mem_write(3'd1, addr2d(r[15:0], 16'd1), (r == 1) ? 32'd1 : 32'd0);
      mem_write(3'd2, addr2d(r[15:0], 16'd0), (r == 0) ? 32'd1 : 32'd0);
      mem_write(3'd2, addr2d(r[15:0], 16'd1), (r == 1) ? 32'd1 : 32'd0);
      mem_write(3'd3, addr2d(r[15:0], 16'd0), (r == 0) ? 32'd1 : 32'd0);
      mem_write(3'd3, addr2d(r[15:0], 16'd1), (r == 1) ? 32'd1 : 32'd0);
    end

    // Start, no output projection.
    axi_write(REG_CONTROL, 32'h0000_0001);
    axi_write(REG_CONTROL, 32'h0000_0000);

    begin : poll_done
      integer t;
      for (t = 0; t < 2000; t = t + 1) begin
        axi_read(REG_STATUS, rdata);
        if (rdata[1]) begin
          t = 2000;
        end
        @(posedge clk);
      end
      if (!rdata[1])
        $fatal(1, "Timeout waiting for DONE");
      if (rdata[2])
        $fatal(1, "Unexpected ERR status");
    end

    mem_read(3'd5, addr2d(16'd0, 16'd0), rdata);
    out00_before = rdata;
    if ($signed(rdata[15:0]) !== 16'sd2)
      $fatal(1, "out[0][0] mismatch: got %0d exp 2", $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd0, 16'd1), rdata);
    out01_before = rdata;
    if ($signed(rdata[15:0]) !== 16'sd1)
      $fatal(1, "out[0][1] mismatch: got %0d exp 1", $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd1, 16'd0), rdata);
    out10_before = rdata;
    if ($signed(rdata[15:0]) !== 16'sd1)
      $fatal(1, "out[1][0] mismatch: got %0d exp 1", $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd1, 16'd1), rdata);
    out11_before = rdata;
    if ($signed(rdata[15:0]) !== 16'sd2)
      $fatal(1, "out[1][1] mismatch: got %0d exp 2", $signed(rdata[15:0]));

    mem_read(3'd6, addr2d(16'd0, 16'd0), rdata);
    if (rdata[15:0] !== 16'd11)
      $fatal(1, "attn[0][0] mismatch: got %0d exp 11", rdata[15:0]);

    mem_read(3'd6, addr2d(16'd0, 16'd1), rdata);
    if (rdata[15:0] !== 16'd7)
      $fatal(1, "attn[0][1] mismatch: got %0d exp 7", rdata[15:0]);

    axi_read(REG_PERF_CYCLES, perf_cycles);
    axi_read(REG_PERF_MACS, perf_macs);
    if (perf_cycles == 0 || perf_macs == 0)
      $fatal(1, "Performance counters did not increment");

    // Train only the post-attention adapter toward larger targets.
    mem_write(3'd7, addr2d(16'd0, 16'd0), 32'd6);
    mem_write(3'd7, addr2d(16'd0, 16'd1), 32'd3);
    mem_write(3'd7, addr2d(16'd1, 16'd0), 32'd3);
    mem_write(3'd7, addr2d(16'd1, 16'd1), 32'd6);

    axi_write(REG_CONTROL, 32'h0000_0005);
    axi_write(REG_CONTROL, 32'h0000_0004);
    begin : poll_train_done
      integer t2;
      for (t2 = 0; t2 < 2000; t2 = t2 + 1) begin
        axi_read(REG_STATUS, rdata);
        if (rdata[1]) begin
          t2 = 2000;
        end
        @(posedge clk);
      end
      if (!rdata[1])
        $fatal(1, "Timeout waiting for train DONE");
      if (rdata[2])
        $fatal(1, "Unexpected train ERR status");
    end

    mem_read(3'd7, addr2d(ADAPT_ROW_GAIN, 16'd0), gain0_after);
    mem_read(3'd7, addr2d(ADAPT_ROW_BIAS, 16'd0), bias0_after);
    if ($signed(gain0_after[15:0]) <= 16'sd256)
      $fatal(1, "adapter gain[0] did not increase: got %0d", $signed(gain0_after[15:0]));
    if ($signed(bias0_after[15:0]) <= 16'sd0)
      $fatal(1, "adapter bias[0] did not increase: got %0d", $signed(bias0_after[15:0]));

    axi_write(REG_CONTROL, 32'h0000_0001);
    axi_write(REG_CONTROL, 32'h0000_0000);
    begin : poll_reinfer_done
      integer t3;
      for (t3 = 0; t3 < 2000; t3 = t3 + 1) begin
        axi_read(REG_STATUS, rdata);
        if (rdata[1]) begin
          t3 = 2000;
        end
        @(posedge clk);
      end
      if (!rdata[1])
        $fatal(1, "Timeout waiting for post-train DONE");
      if (rdata[2])
        $fatal(1, "Unexpected post-train ERR status");
    end

    mem_read(3'd5, addr2d(16'd0, 16'd0), rdata);
    if ($signed(rdata[15:0]) <= $signed(out00_before[15:0]))
      $fatal(1, "out[0][0] did not move toward target: before %0d after %0d",
        $signed(out00_before[15:0]), $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd0, 16'd1), rdata);
    if ($signed(rdata[15:0]) <= $signed(out01_before[15:0]))
      $fatal(1, "out[0][1] did not move toward target: before %0d after %0d",
        $signed(out01_before[15:0]), $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd1, 16'd0), rdata);
    if ($signed(rdata[15:0]) <= $signed(out10_before[15:0]))
      $fatal(1, "out[1][0] did not move toward target: before %0d after %0d",
        $signed(out10_before[15:0]), $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd1, 16'd1), rdata);
    if ($signed(rdata[15:0]) <= $signed(out11_before[15:0]))
      $fatal(1, "out[1][1] did not move toward target: before %0d after %0d",
        $signed(out11_before[15:0]), $signed(rdata[15:0]));

    // Full backprop mode: update WQ/WK/WV/WO, not just the adapter.
    axi_write(REG_CONTROL, 32'h0000_0002);
    axi_write(REG_CONTROL, 32'h0000_0000);
    axi_write(REG_SEQ_LEN, 32'd2);
    axi_write(REG_D_MODEL, 32'd2);
    axi_write(REG_D_HEAD, 32'd2);
    axi_write(REG_SCORE_SHIFT, 32'd0);
    axi_write(REG_NORM_BIAS, 32'd1);

    mem_write(3'd0, addr2d(16'd0, 16'd0), 32'd3);
    mem_write(3'd0, addr2d(16'd0, 16'd1), 32'd1);
    mem_write(3'd0, addr2d(16'd1, 16'd0), 32'd1);
    mem_write(3'd0, addr2d(16'd1, 16'd1), 32'd3);

    for (r = 0; r < 2; r = r + 1) begin
      mem_write(3'd1, addr2d(r[15:0], 16'd0), (r == 0) ? 32'd1 : 32'd0);
      mem_write(3'd1, addr2d(r[15:0], 16'd1), (r == 1) ? 32'd1 : 32'd0);
      mem_write(3'd2, addr2d(r[15:0], 16'd0), (r == 0) ? 32'd1 : 32'd0);
      mem_write(3'd2, addr2d(r[15:0], 16'd1), (r == 1) ? 32'd1 : 32'd0);
      mem_write(3'd3, addr2d(r[15:0], 16'd0), (r == 0) ? 32'd1 : 32'd0);
      mem_write(3'd3, addr2d(r[15:0], 16'd1), (r == 1) ? 32'd1 : 32'd0);
      mem_write(3'd4, addr2d(r[15:0], 16'd0), (r == 0) ? 32'd1 : 32'd0);
      mem_write(3'd4, addr2d(r[15:0], 16'd1), (r == 1) ? 32'd1 : 32'd0);
    end

    mem_write(3'd7, addr2d(16'd0, 16'd0), 32'd6);
    mem_write(3'd7, addr2d(16'd0, 16'd1), 32'd3);
    mem_write(3'd7, addr2d(16'd1, 16'd0), 32'd3);
    mem_write(3'd7, addr2d(16'd1, 16'd1), 32'd6);

    axi_write(REG_CONTROL, 32'h0000_0009);
    axi_write(REG_CONTROL, 32'h0000_0008);
    begin : poll_fullbp_base
      integer t4;
      for (t4 = 0; t4 < 2000; t4 = t4 + 1) begin
        axi_read(REG_STATUS, rdata);
        if (rdata[1]) begin
          t4 = 2000;
        end
        @(posedge clk);
      end
      if (!rdata[1])
        $fatal(1, "Timeout waiting for fullbp baseline DONE");
      if (rdata[2])
        $fatal(1, "Unexpected fullbp baseline ERR status");
    end

    mem_read(3'd5, addr2d(16'd0, 16'd0), fullbp_out00_before);

    repeat (16) begin
      axi_write(REG_CONTROL, 32'h0000_002d);
      axi_write(REG_CONTROL, 32'h0000_002c);
      begin : poll_fullbp_train
        integer t5;
        for (t5 = 0; t5 < 6000; t5 = t5 + 1) begin
          axi_read(REG_STATUS, rdata);
          if (rdata[1]) begin
            t5 = 6000;
          end
          @(posedge clk);
        end
        if (!rdata[1])
          $fatal(1, "Timeout waiting for full backprop DONE");
        if (rdata[2])
          $fatal(1, "Unexpected full backprop ERR status");
      end
    end

    mem_read(3'd1, addr2d(16'd0, 16'd0), wq00_after);
    mem_read(3'd2, addr2d(16'd0, 16'd0), wk00_after);
    mem_read(3'd3, addr2d(16'd0, 16'd0), wv00_after);
    mem_read(3'd4, addr2d(16'd0, 16'd0), wo00_after);
    if ((wq00_after[7:0] == 8'd1) && (wk00_after[7:0] == 8'd1) &&
        (wv00_after[7:0] == 8'd1) && (wo00_after[7:0] == 8'd1))
      $fatal(1, "full backprop did not update any major weight matrix");

    axi_write(REG_CONTROL, 32'h0000_0009);
    axi_write(REG_CONTROL, 32'h0000_0008);
    begin : poll_fullbp_reinfer
      integer t6;
      for (t6 = 0; t6 < 4000; t6 = t6 + 1) begin
        axi_read(REG_STATUS, rdata);
        if (rdata[1]) begin
          t6 = 4000;
        end
        @(posedge clk);
      end
      if (!rdata[1])
        $fatal(1, "Timeout waiting for fullbp reinfer DONE");
      if (rdata[2])
        $fatal(1, "Unexpected fullbp reinfer ERR status");
    end

    mem_read(3'd5, addr2d(16'd0, 16'd0), fullbp_out00_after);
    if ($signed(fullbp_out00_after[15:0]) <= $signed(fullbp_out00_before[15:0]))
      $fatal(1, "full backprop did not improve out[0][0]: before %0d after %0d",
        $signed(fullbp_out00_before[15:0]), $signed(fullbp_out00_after[15:0]));

    $display("TINY ATTN PASS cycles=%0d macs=%0d irq=%0d gain0=%0d bias0=%0d",
      perf_cycles, perf_macs, irq, $signed(gain0_after[15:0]), $signed(bias0_after[15:0]));
    repeat (10) @(posedge clk);
    $finish;
  end
endmodule
