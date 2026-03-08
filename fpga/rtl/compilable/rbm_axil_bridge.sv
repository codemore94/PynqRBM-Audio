module rbm_axil_bridge (
  input  logic        clk,
  input  logic        resetn,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic        req_write,
  input  logic [31:0] req_addr,
  input  logic [31:0] req_wdata,
  input  logic [3:0]  req_wstrb,
  output logic [31:0] req_rdata,
  output logic        req_done,

  output logic [31:0] m_awaddr,
  output logic        m_awvalid,
  input  logic        m_awready,
  output logic [31:0] m_wdata,
  output logic [3:0]  m_wstrb,
  output logic        m_wvalid,
  input  logic        m_wready,
  input  logic [1:0]  m_bresp,
  input  logic        m_bvalid,
  output logic        m_bready,
  output logic [31:0] m_araddr,
  output logic        m_arvalid,
  input  logic        m_arready,
  input  logic [31:0] m_rdata,
  input  logic [1:0]  m_rresp,
  input  logic        m_rvalid,
  output logic        m_rready
);
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_W_ADDR_DATA,
    ST_W_RESP,
    ST_R_ADDR,
    ST_R_DATA
  } st_t;

  st_t st;

  always_ff @(posedge clk) begin
    if (!resetn) begin
      st <= ST_IDLE;
      req_rdata <= 32'b0;
      req_done <= 1'b0;
      m_awaddr <= 32'b0;
      m_awvalid <= 1'b0;
      m_wdata <= 32'b0;
      m_wstrb <= 4'b0;
      m_wvalid <= 1'b0;
      m_bready <= 1'b0;
      m_araddr <= 32'b0;
      m_arvalid <= 1'b0;
      m_rready <= 1'b0;
    end else begin
      req_done <= 1'b0;

      case (st)
        ST_IDLE: begin
          if (req_valid) begin
            if (req_write) begin
              m_awaddr <= req_addr;
              m_wdata <= req_wdata;
              m_wstrb <= req_wstrb;
              m_awvalid <= 1'b1;
              m_wvalid <= 1'b1;
              st <= ST_W_ADDR_DATA;
            end else begin
              m_araddr <= req_addr;
              m_arvalid <= 1'b1;
              st <= ST_R_ADDR;
            end
          end
        end

        ST_W_ADDR_DATA: begin
          if (m_awvalid && m_awready) m_awvalid <= 1'b0;
          if (m_wvalid && m_wready) m_wvalid <= 1'b0;
          if ((m_awvalid ? m_awready : 1'b1) && (m_wvalid ? m_wready : 1'b1)) begin
            m_bready <= 1'b1;
            st <= ST_W_RESP;
          end
        end

        ST_W_RESP: begin
          if (m_bvalid && m_bready) begin
            m_bready <= 1'b0;
            req_done <= 1'b1;
            st <= ST_IDLE;
          end
        end

        ST_R_ADDR: begin
          if (m_arvalid && m_arready) begin
            m_arvalid <= 1'b0;
            m_rready <= 1'b1;
            st <= ST_R_DATA;
          end
        end

        ST_R_DATA: begin
          if (m_rvalid && m_rready) begin
            req_rdata <= m_rdata;
            m_rready <= 1'b0;
            req_done <= 1'b1;
            st <= ST_IDLE;
          end
        end

        default: st <= ST_IDLE;
      endcase
    end
  end

  assign req_ready = (st == ST_IDLE);
  wire unused_ok = ^{m_bresp, m_rresp, 1'b0};
endmodule
