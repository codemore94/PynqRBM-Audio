`timescale 1ns/1ps
module tb_rbm_cd1_top_axi;
  localparam I_DIM = 4;
  localparam H_DIM = 4;

  logic clk = 0;
  logic rstn = 0;

  // AXI-Lite signals
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

  rbm_cd1_top_axi #(
    .I_DIM(I_DIM),
    .H_DIM(H_DIM)
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

  // Clock
  always #5 clk = ~clk;

  // AXI tasks
  task automatic axi_write(input [31:0] addr, input [31:0] data);
    begin
      @(posedge clk);
      S_AWADDR  <= addr;
      S_AWVALID <= 1'b1;
      S_WDATA   <= data;
      S_WSTRB   <= 4'hF;
      S_WVALID  <= 1'b1;
      S_BREADY  <= 1'b1;
      wait (S_AWREADY && S_WREADY);
      @(posedge clk);
      S_AWVALID <= 1'b0;
      S_WVALID  <= 1'b0;
      wait (S_BVALID);
      @(posedge clk);
      S_BREADY  <= 1'b0;
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

  // Register offsets
  localparam REG_CONTROL     = 32'h00;
  localparam REG_STATUS      = 32'h04;
  localparam REG_I_DIM       = 32'h08;
  localparam REG_H_DIM       = 32'h0C;
  localparam REG_K_DIM       = 32'h10;
  localparam REG_FRAME_LEN   = 32'h14;
  localparam REG_SCALE_SHIFT = 32'h18;
  localparam REG_RNG_SEED    = 32'h1C;
  localparam REG_BATCH       = 32'h2C;
  localparam REG_EPOCHS      = 32'h30;
  localparam REG_LR_MOM      = 32'h34;
  localparam REG_WD          = 32'h38;
  localparam REG_MEM_ADDR    = 32'h6C;
  localparam REG_MEM_WDATA   = 32'h70;
  localparam REG_MEM_RDATA   = 32'h74;
  localparam REG_MEM_CTRL    = 32'h78;

  // Helper to write memory window
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

  integer i, h;
  reg [31:0] rdata;

  initial begin
    // init AXI defaults
    S_AWADDR = 0; S_AWVALID = 0; S_WDATA = 0; S_WSTRB = 0; S_WVALID = 0; S_BREADY = 0;
    S_ARADDR = 0; S_ARVALID = 0; S_RREADY = 0;

    // reset
    rstn = 0;
    repeat(5) @(posedge clk);
    rstn = 1;
    repeat(5) @(posedge clk);

    // program params
    axi_write(REG_I_DIM, I_DIM);
    axi_write(REG_H_DIM, H_DIM);
    axi_write(REG_K_DIM, 1);
    axi_write(REG_FRAME_LEN, 1);
    axi_write(REG_SCALE_SHIFT, 0);
    axi_write(REG_RNG_SEED, 32'hACE1);
    axi_write(REG_BATCH, 1);
    axi_write(REG_EPOCHS, 1);
    axi_write(REG_LR_MOM, 32'h00000100); // lr=0x0100
    axi_write(REG_WD, 0);

    // load v0
    for (i = 0; i < I_DIM; i = i + 1) begin
      mem_write(3'd0, i, (i[0] ? 8'h80 : 8'h00));
    end

    // load weights and biases
    for (i = 0; i < I_DIM; i = i + 1) begin
      mem_write(3'd2, i, 16'h0000); // b_vis
      for (h = 0; h < H_DIM; h = h + 1) begin
        mem_write(3'd1, {h[15:0], i[15:0]}, 16'h0100); // w[i][h]
      end
    end
    for (h = 0; h < H_DIM; h = h + 1) begin
      mem_write(3'd3, h, 16'h0000); // b_hid
    end

    // start training
    axi_write(REG_CONTROL, 32'h0000_0001);

    // poll status.done (bit1)
    begin : poll_done
      integer t;
      for (t = 0; t < 2000; t = t + 1) begin
        axi_read(REG_STATUS, rdata);
        if (rdata[1]) begin
          $display("DONE status=0x%08x", rdata);
          t = 2000;
        end
        @(posedge clk);
      end
      if (!rdata[1]) $display("TIMEOUT waiting for done");
    end

    // read back a weight
    mem_read(3'd1, {16'd0,16'd0}, rdata);
    $display("w[0][0]=0x%08x", rdata);

    repeat(20) @(posedge clk);
    $finish;
  end

endmodule
