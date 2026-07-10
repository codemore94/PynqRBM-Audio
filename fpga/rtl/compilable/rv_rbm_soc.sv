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
  output logic rbm_irq,
  output logic trace_rbm_awvalid,
  output logic trace_rbm_awready,
  output logic [31:0] trace_rbm_awaddr,
  output logic trace_rbm_wvalid,
  output logic trace_rbm_wready,
  output logic [31:0] trace_rbm_wdata,
  output logic trace_rbm_arvalid,
  output logic trace_rbm_arready,
  output logic [31:0] trace_rbm_araddr,
  output logic trace_attn_awvalid,
  output logic trace_attn_awready,
  output logic [31:0] trace_attn_awaddr,
  output logic trace_attn_wvalid,
  output logic trace_attn_wready,
  output logic [31:0] trace_attn_wdata,
  output logic trace_attn_arvalid,
  output logic trace_attn_arready,
  output logic [31:0] trace_attn_araddr,
  output logic trace_tiny_done,
  output logic trace_rbm_done,
  output logic [31:0] trace_fw_stage,
  output logic [31:0] trace_fw_rc
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

  localparam integer RAM_ADDR_W = (MEM_WORDS <= 1) ? 1 : $clog2(MEM_WORDS);
  logic [RAM_ADDR_W-1:0] ram_addr;
  logic [31:0] ram_q;
  logic [31:0] ram_rdata;
  logic        ram_ready;
  logic        ram_sel_d;

  assign ram_addr = mem_addr[RAM_ADDR_W+1:2];

  function automatic [31:0] merge_wstrb(
    input [31:0] old_value,
    input [31:0] new_value,
    input [3:0]  byte_en
  );
    begin
      merge_wstrb = old_value;
      if (byte_en[0]) merge_wstrb[7:0]   = new_value[7:0];
      if (byte_en[1]) merge_wstrb[15:8]  = new_value[15:8];
      if (byte_en[2]) merge_wstrb[23:16] = new_value[23:16];
      if (byte_en[3]) merge_wstrb[31:24] = new_value[31:24];
    end
  endfunction

  rv_word_ram #(
    .DEPTH(MEM_WORDS),
    .ADDR_W(RAM_ADDR_W),
    .INIT_FILE(FW_HEX)
  ) u_ram (
    .clk(clk),
    .addr(ram_addr),
    .we(ram_sel && |mem_wstrb),
    .be(mem_wstrb),
    .wdata(mem_wdata),
    .rdata(ram_q)
  );

  always_ff @(posedge clk) begin
    if (!resetn) begin
      ram_ready <= 1'b0;
      ram_sel_d <= 1'b0;
      ram_rdata <= 32'b0;
      trace_fw_stage <= 32'b0;
      trace_fw_rc <= 32'b0;
    end else begin
      // One-shot handshake: ready pulses exactly one cycle per request.
      // A plain delayed copy of ram_sel keeps ready high for two cycles
      // after the handshake, and picorv32's minimum request turnaround is
      // short enough to catch that stale ready and complete with the
      // previous transaction's data (corrupting instruction fetches).
      if (ram_ready) begin
        ram_ready <= 1'b0;
        ram_sel_d <= 1'b0;
      end else begin
        ram_sel_d <= ram_sel && !ram_sel_d;
        ram_ready <= ram_sel_d;
      end
      ram_rdata <= ram_q;
      if (ram_sel && |mem_wstrb && mem_addr == 32'h0000_3f00)
        trace_fw_stage <= merge_wstrb(trace_fw_stage, mem_wdata, mem_wstrb);
      if (ram_sel && |mem_wstrb && mem_addr == 32'h0000_3f04)
        trace_fw_rc <= merge_wstrb(trace_fw_rc, mem_wdata, mem_wstrb);
    end
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
  logic rbm_done_trace, tiny_done_trace;

  assign trace_rbm_awvalid = rbm_awvalid;
  assign trace_rbm_awready = rbm_awready;
  assign trace_rbm_awaddr = rbm_awaddr;
  assign trace_rbm_wvalid = rbm_wvalid;
  assign trace_rbm_wready = rbm_wready;
  assign trace_rbm_wdata = rbm_wdata;
  assign trace_rbm_arvalid = rbm_arvalid;
  assign trace_rbm_arready = rbm_arready;
  assign trace_rbm_araddr = rbm_araddr;
  assign trace_attn_awvalid = attn_awvalid;
  assign trace_attn_awready = attn_awready;
  assign trace_attn_awaddr = attn_awaddr;
  assign trace_attn_wvalid = attn_wvalid;
  assign trace_attn_wready = attn_wready;
  assign trace_attn_wdata = attn_wdata;
  assign trace_attn_arvalid = attn_arvalid;
  assign trace_attn_arready = attn_arready;
  assign trace_attn_araddr = attn_araddr;
  assign trace_tiny_done = tiny_done_trace;
  assign trace_rbm_done = rbm_done_trace;

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
    .irq(rbm_irq),
    .trace_stat_done(rbm_done_trace)
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
    .irq(attn_irq),
    .trace_stat_done(tiny_done_trace)
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

module rv_word_ram #(
  parameter integer DEPTH = 4096,
  parameter integer ADDR_W = 12,
  parameter INIT_FILE = ""
)(
  input  logic clk,
  input  logic [ADDR_W-1:0] addr,
  input  logic we,
  input  logic [3:0] be,
  input  logic [31:0] wdata,
  output logic [31:0] rdata
);
`ifdef QUARTUS_SYNTH
  wire [31:0] ram_q;
  assign rdata = ram_q;

  altsyncram #(
    .operation_mode("SINGLE_PORT"),
    .width_a(32),
    .widthad_a(ADDR_W),
    .numwords_a(DEPTH),
    .byte_size(8),
    .width_byteena_a(4),
    .outdata_reg_a("UNREGISTERED"),
    .address_aclr_a("NONE"),
    .outdata_aclr_a("NONE"),
    .indata_aclr_a("NONE"),
    .wrcontrol_aclr_a("NONE"),
    .byteena_aclr_a("NONE"),
    .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
    .ram_block_type("M10K"),
    .init_file(INIT_FILE),
    .intended_device_family("Cyclone V"),
    .lpm_type("altsyncram")
  ) u_mem (
    .wren_a(we),
    .wren_b(1'b0),
    .rden_a(1'b1),
    .rden_b(1'b0),
    .data_a(wdata),
    .data_b(1'b0),
    .address_a(addr),
    .address_b(1'b0),
    .clock0(clk),
    .clock1(1'b1),
    .clocken0(1'b1),
    .clocken1(1'b1),
    .clocken2(1'b1),
    .clocken3(1'b1),
    .aclr0(1'b0),
    .aclr1(1'b0),
    .byteena_a(be),
    .byteena_b(1'b1),
    .addressstall_a(1'b0),
    .addressstall_b(1'b0),
    .q_a(ram_q),
    .q_b(),
    .eccstatus()
  );
`else
  logic [31:0] mem [0:DEPTH-1];

  initial begin
`ifdef SYNTHESIS
    $readmemh(INIT_FILE, mem);
`else
    if (!$test$plusargs("NO_FW"))
      $readmemh(INIT_FILE, mem);
`endif
  end

  always_ff @(posedge clk) begin
    rdata <= mem[addr];
    if (we) begin
      if (be[0]) mem[addr][7:0]   <= wdata[7:0];
      if (be[1]) mem[addr][15:8]  <= wdata[15:8];
      if (be[2]) mem[addr][23:16] <= wdata[23:16];
      if (be[3]) mem[addr][31:24] <= wdata[31:24];
    end
  end
`endif
endmodule
