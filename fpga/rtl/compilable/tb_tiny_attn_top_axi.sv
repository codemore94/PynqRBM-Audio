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
    if ($signed(rdata[15:0]) !== 16'sd2)
      $fatal(1, "out[0][0] mismatch: got %0d exp 2", $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd0, 16'd1), rdata);
    if ($signed(rdata[15:0]) !== 16'sd1)
      $fatal(1, "out[0][1] mismatch: got %0d exp 1", $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd1, 16'd0), rdata);
    if ($signed(rdata[15:0]) !== 16'sd1)
      $fatal(1, "out[1][0] mismatch: got %0d exp 1", $signed(rdata[15:0]));

    mem_read(3'd5, addr2d(16'd1, 16'd1), rdata);
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

    $display("TINY ATTN PASS cycles=%0d macs=%0d irq=%0d", perf_cycles, perf_macs, irq);
    repeat (10) @(posedge clk);
    $finish;
  end
endmodule
