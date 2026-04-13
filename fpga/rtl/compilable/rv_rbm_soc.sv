`ifndef PICORV32_REGS
`define PICORV32_REGS rv_rbm_soc_regs
`endif

module rv_rbm_soc #(
  parameter integer MEM_WORDS = 4096,
  parameter [31:0]  STACKADDR = 4*MEM_WORDS,
  parameter [31:0]  PROGADDR_RESET = 32'h0000_0000,
  parameter [31:0]  PROGADDR_IRQ = 32'h0000_0010,
  parameter integer UART_DIV = 100,
  parameter integer RBM_I_DIM = 64,
  parameter integer RBM_H_DIM = 64,
  parameter integer ATTN_MAX_SEQ_LEN = 8,
  parameter integer ATTN_MAX_D_MODEL = 8,
  parameter FW_HEX = "sw/rv_soc_fw.hex"
) (
  input  logic clk,
  input  logic resetn,
  output logic uart_tx,
  input  logic uart_rx,
  output logic rbm_irq
);
  localparam [31:0] RAM_END       = (4*MEM_WORDS);
  localparam [31:0] UART_BASE     = 32'h1000_0000;
  localparam [31:0] TIMER_BASE    = 32'h1000_1000;
  localparam [31:0] RBM_BASE      = 32'h4000_0000;
  localparam [31:0] RBM_END       = 32'h4000_0100;
  localparam [31:0] ATTN_BASE     = 32'h4000_1000;
  localparam [31:0] ATTN_END      = 32'h4000_1100;

  logic        mem_valid;
  logic        mem_instr;
  logic        mem_ready;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [3:0]  mem_wstrb;
  logic [31:0] mem_rdata;

  logic [31:0] irq;
  logic timer_irq_pending;
  logic timer_irq_en;
  logic attn_irq;

  always_comb begin
    irq = 32'b0;
    irq[0] = timer_irq_en && timer_irq_pending;
    irq[1] = rbm_irq;
    irq[2] = attn_irq;
  end

  picorv32 #(
    .STACKADDR(STACKADDR),
    .PROGADDR_RESET(PROGADDR_RESET),
    .PROGADDR_IRQ(PROGADDR_IRQ),
    .ENABLE_IRQ(1),
    .ENABLE_IRQ_QREGS(1),
    .ENABLE_COUNTERS(1),
    .COMPRESSED_ISA(1),
    .ENABLE_MUL(1),
    .ENABLE_DIV(1)
  ) u_cpu (
    .clk(clk),
    .resetn(resetn),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .irq(irq)
  );

  logic ram_sel, uart_div_sel, uart_dat_sel, timer_sel, rbm_sel, attn_sel;
  always_comb begin
    ram_sel      = mem_valid && (mem_addr < RAM_END);
    uart_div_sel = mem_valid && (mem_addr == UART_BASE + 32'h0);
    uart_dat_sel = mem_valid && (mem_addr == UART_BASE + 32'h4);
    timer_sel    = mem_valid && (mem_addr >= TIMER_BASE) && (mem_addr < TIMER_BASE + 32'h14);
    rbm_sel      = mem_valid && (mem_addr >= RBM_BASE) && (mem_addr < RBM_END);
    attn_sel     = mem_valid && (mem_addr >= ATTN_BASE) && (mem_addr < ATTN_END);
  end

  logic [31:0] ram [0:MEM_WORDS-1];
  logic [31:0] ram_rdata;
  logic        ram_ready;
  always_ff @(posedge clk) begin
    ram_ready <= 1'b0;
    if (!resetn) begin
      ram_ready <= 1'b0;
    end else if (ram_sel) begin
      ram_rdata <= ram[mem_addr[31:2]];
      if (mem_wstrb[0]) ram[mem_addr[31:2]][7:0]   <= mem_wdata[7:0];
      if (mem_wstrb[1]) ram[mem_addr[31:2]][15:8]  <= mem_wdata[15:8];
      if (mem_wstrb[2]) ram[mem_addr[31:2]][23:16] <= mem_wdata[23:16];
      if (mem_wstrb[3]) ram[mem_addr[31:2]][31:24] <= mem_wdata[31:24];
      ram_ready <= 1'b1;
    end
  end

// synthesis translate_off
  initial begin
    if ($test$plusargs("NO_FW")) begin
      // Keep zero-initialized memory in simulation when requested.
    end else begin
      $readmemh(FW_HEX, ram);
    end
  end
// synthesis translate_on
  initial begin
    $readmemh(FW_HEX, ram);
  end

  logic [31:0] uart_div_do, uart_dat_do;
  logic uart_dat_wait;
  simpleuart #(.DEFAULT_DIV(UART_DIV)) u_uart (
    .clk(clk),
    .resetn(resetn),
    .ser_tx(uart_tx),
    .ser_rx(uart_rx),
    .reg_div_we(uart_div_sel ? mem_wstrb : 4'b0),
    .reg_div_di(mem_wdata),
    .reg_div_do(uart_div_do),
    .reg_dat_we(uart_dat_sel ? |mem_wstrb : 1'b0),
    .reg_dat_re(uart_dat_sel && (mem_wstrb == 4'b0)),
    .reg_dat_di(mem_wdata),
    .reg_dat_do(uart_dat_do),
    .reg_dat_wait(uart_dat_wait)
  );

  logic [63:0] timer_mtime, timer_mtimecmp;
  logic [31:0] timer_rdata;
  logic timer_ready;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      timer_mtime <= 64'b0;
      timer_mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
      timer_irq_en <= 1'b0;
      timer_irq_pending <= 1'b0;
      timer_ready <= 1'b0;
    end else begin
      timer_ready <= 1'b0;
      timer_mtime <= timer_mtime + 1'b1;
      if (timer_mtime >= timer_mtimecmp) timer_irq_pending <= 1'b1;

      if (timer_sel) begin
        timer_ready <= 1'b1;
        if (|mem_wstrb) begin
          case (mem_addr[5:2])
            4'h2: timer_mtimecmp[31:0] <= mem_wdata;
            4'h3: timer_mtimecmp[63:32] <= mem_wdata;
            4'h4: begin
              timer_irq_en <= mem_wdata[0];
              if (mem_wdata[1]) timer_irq_pending <= 1'b0;
            end
            default: ;
          endcase
        end
      end
    end
  end

  always_comb begin
    timer_rdata = 32'b0;
    case (mem_addr[5:2])
      4'h0: timer_rdata = timer_mtime[31:0];
      4'h1: timer_rdata = timer_mtime[63:32];
      4'h2: timer_rdata = timer_mtimecmp[31:0];
      4'h3: timer_rdata = timer_mtimecmp[63:32];
      4'h4: timer_rdata = {30'b0, timer_irq_pending, timer_irq_en};
      default: timer_rdata = 32'b0;
    endcase
  end

  logic [31:0] rbm_awaddr, rbm_wdata, rbm_araddr, rbm_rdata;
  logic [3:0]  rbm_wstrb;
  logic rbm_awvalid, rbm_awready, rbm_wvalid, rbm_wready;
  logic [1:0] rbm_bresp, rbm_rresp;
  logic rbm_bvalid, rbm_bready, rbm_arvalid, rbm_arready, rbm_rvalid, rbm_rready;

  logic rbm_req_done, rbm_req_ready;
  logic [31:0] rbm_req_rdata;
  logic [31:0] attn_awaddr, attn_wdata, attn_araddr, attn_rdata;
  logic [3:0]  attn_wstrb;
  logic attn_awvalid, attn_awready, attn_wvalid, attn_wready;
  logic [1:0] attn_bresp, attn_rresp;
  logic attn_bvalid, attn_bready, attn_arvalid, attn_arready, attn_rvalid, attn_rready;
  logic attn_req_done, attn_req_ready;
  logic [31:0] attn_req_rdata;

  rbm_axil_bridge u_rbm_bridge (
    .clk(clk),
    .resetn(resetn),
    .req_valid(rbm_sel),
    .req_ready(rbm_req_ready),
    .req_write(|mem_wstrb),
    .req_addr(mem_addr - RBM_BASE),
    .req_wdata(mem_wdata),
    .req_wstrb(mem_wstrb),
    .req_rdata(rbm_req_rdata),
    .req_done(rbm_req_done),
    .m_awaddr(rbm_awaddr),
    .m_awvalid(rbm_awvalid),
    .m_awready(rbm_awready),
    .m_wdata(rbm_wdata),
    .m_wstrb(rbm_wstrb),
    .m_wvalid(rbm_wvalid),
    .m_wready(rbm_wready),
    .m_bresp(rbm_bresp),
    .m_bvalid(rbm_bvalid),
    .m_bready(rbm_bready),
    .m_araddr(rbm_araddr),
    .m_arvalid(rbm_arvalid),
    .m_arready(rbm_arready),
    .m_rdata(rbm_rdata),
    .m_rresp(rbm_rresp),
    .m_rvalid(rbm_rvalid),
    .m_rready(rbm_rready)
  );

  rbm_cd1_top_axi #(
    .I_DIM(RBM_I_DIM),
    .H_DIM(RBM_H_DIM)
  ) u_rbm (
    .ACLK(clk),
    .ARESETn(resetn),
    .S_AWADDR(rbm_awaddr),
    .S_AWVALID(rbm_awvalid),
    .S_AWREADY(rbm_awready),
    .S_WDATA(rbm_wdata),
    .S_WSTRB(rbm_wstrb),
    .S_WVALID(rbm_wvalid),
    .S_WREADY(rbm_wready),
    .S_BRESP(rbm_bresp),
    .S_BVALID(rbm_bvalid),
    .S_BREADY(rbm_bready),
    .S_ARADDR(rbm_araddr),
    .S_ARVALID(rbm_arvalid),
    .S_ARREADY(rbm_arready),
    .S_RDATA(rbm_rdata),
    .S_RRESP(rbm_rresp),
    .S_RVALID(rbm_rvalid),
    .S_RREADY(rbm_rready),
    .irq(rbm_irq)
  );

  rbm_axil_bridge u_attn_bridge (
    .clk(clk),
    .resetn(resetn),
    .req_valid(attn_sel),
    .req_ready(attn_req_ready),
    .req_write(|mem_wstrb),
    .req_addr(mem_addr - ATTN_BASE),
    .req_wdata(mem_wdata),
    .req_wstrb(mem_wstrb),
    .req_rdata(attn_req_rdata),
    .req_done(attn_req_done),
    .m_awaddr(attn_awaddr),
    .m_awvalid(attn_awvalid),
    .m_awready(attn_awready),
    .m_wdata(attn_wdata),
    .m_wstrb(attn_wstrb),
    .m_wvalid(attn_wvalid),
    .m_wready(attn_wready),
    .m_bresp(attn_bresp),
    .m_bvalid(attn_bvalid),
    .m_bready(attn_bready),
    .m_araddr(attn_araddr),
    .m_arvalid(attn_arvalid),
    .m_arready(attn_arready),
    .m_rdata(attn_rdata),
    .m_rresp(attn_rresp),
    .m_rvalid(attn_rvalid),
    .m_rready(attn_rready)
  );

  tiny_attn_top_axi #(
    .MAX_SEQ_LEN(ATTN_MAX_SEQ_LEN),
    .MAX_D_MODEL(ATTN_MAX_D_MODEL)
  ) u_attn (
    .ACLK(clk),
    .ARESETn(resetn),
    .S_AWADDR(attn_awaddr),
    .S_AWVALID(attn_awvalid),
    .S_AWREADY(attn_awready),
    .S_WDATA(attn_wdata),
    .S_WSTRB(attn_wstrb),
    .S_WVALID(attn_wvalid),
    .S_WREADY(attn_wready),
    .S_BRESP(attn_bresp),
    .S_BVALID(attn_bvalid),
    .S_BREADY(attn_bready),
    .S_ARADDR(attn_araddr),
    .S_ARVALID(attn_arvalid),
    .S_ARREADY(attn_arready),
    .S_RDATA(attn_rdata),
    .S_RRESP(attn_rresp),
    .S_RVALID(attn_rvalid),
    .S_RREADY(attn_rready),
    .irq(attn_irq)
  );

  logic uart_ready;
  assign uart_ready = uart_div_sel || (uart_dat_sel && !uart_dat_wait);

  always_comb begin
    mem_ready = 1'b0;
    mem_rdata = 32'b0;
    if (ram_sel) begin
      mem_ready = ram_ready;
      mem_rdata = ram_rdata;
    end else if (uart_div_sel) begin
      mem_ready = 1'b1;
      mem_rdata = uart_div_do;
    end else if (uart_dat_sel) begin
      mem_ready = !uart_dat_wait;
      mem_rdata = uart_dat_do;
    end else if (timer_sel) begin
      mem_ready = timer_ready;
      mem_rdata = timer_rdata;
    end else if (rbm_sel) begin
      mem_ready = rbm_req_done;
      mem_rdata = rbm_req_rdata;
    end else if (attn_sel) begin
      mem_ready = attn_req_done;
      mem_rdata = attn_req_rdata;
    end else if (mem_valid) begin
      mem_ready = 1'b1;
      mem_rdata = 32'b0;
    end
  end

  wire unused_ok = ^{mem_instr, rbm_req_ready, attn_req_ready, uart_ready, 1'b0};
endmodule
