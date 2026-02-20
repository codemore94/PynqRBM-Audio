// CD-1 RBM training core with AXI-Lite control + memory window
module rbm_cd1_top_axi #(
  parameter I_DIM = 64,
  parameter H_DIM = 64
)(
  input  logic           ACLK,
  input  logic           ARESETn,
  // AXI4-Lite slave
  input  logic [31:0]    S_AWADDR,
  input  logic           S_AWVALID,
  output logic           S_AWREADY,
  input  logic [31:0]    S_WDATA,
  input  logic [3:0]     S_WSTRB,
  input  logic           S_WVALID,
  output logic           S_WREADY,
  output logic [1:0]     S_BRESP,
  output logic           S_BVALID,
  input  logic           S_BREADY,
  input  logic [31:0]    S_ARADDR,
  input  logic           S_ARVALID,
  output logic           S_ARREADY,
  output logic [31:0]    S_RDATA,
  output logic [1:0]     S_RRESP,
  output logic           S_RVALID,
  input  logic           S_RREADY,
  output logic           irq
);
  // Control wires
  logic           ctrl_start;
  logic           ctrl_soft_rst;
  logic           ctrl_mode_train;
  logic           ctrl_determ;
  logic           ctrl_dma_en;
  logic [15:0]    i_dim, h_dim, frame_len;
  logic [7:0]     k_dim;
  logic [4:0]     scale_shift;
  logic [15:0]    rng_seed;
  logic [15:0]    tile_i, tile_h;
  logic [15:0]    batch_size, epochs;
  logic [15:0]    lr, mom, wd;
  logic           accum_clr_pos, accum_clr_neg;
  logic [31:0]    w_base_lo, w_base_hi;
  logic [31:0]    b_vis_base, b_hid_base;
  logic [31:0]    data_base_lo, data_base_hi;
  logic           stat_busy, stat_done, stat_err;
  logic           stat_batch_done, stat_epoch_done;
  logic [31:0]    stat_flags;
  logic           ie_done, ie_batch, ie_epoch;

  // Memory window
  logic [31:0]    mem_addr;
  logic [31:0]    mem_wdata;
  logic           mem_wen;
  logic [2:0]     mem_sel;
  logic [31:0]    mem_rdata;

  // Local memories (on-chip model)
  logic signed [7:0]  v0 [0:I_DIM-1];
  logic signed [7:0]  v1 [0:I_DIM-1];
  logic signed [15:0] w  [0:I_DIM-1][0:H_DIM-1];
  logic signed [15:0] b_vis [0:I_DIM-1];
  logic signed [15:0] b_hid [0:H_DIM-1];
  logic [15:0]        h0_prob [0:H_DIM-1];
  logic [15:0]        h1_prob [0:H_DIM-1];
  logic signed [7:0]  h0_samp [0:H_DIM-1];

  // RNG
  logic [15:0] rnd;
  lfsr16 u_rng(
    .clk(ACLK),
    .rst(!ARESETn | ctrl_soft_rst),
    .seed(rng_seed),
    .rnd(rnd)
  );

  // Sigmoid LUT (single shared)
  logic [15:0] sig_in;
  logic [15:0] sig_out;
  sigmoid_lut u_sig(.clk(ACLK), .x(sig_in), .y(sig_out));

  // Control/CSR
  rbm_ctrl_axi_lite u_ctrl(
    .ACLK(ACLK),
    .ARESETn(ARESETn),
    .S_AWADDR(S_AWADDR), .S_AWVALID(S_AWVALID), .S_AWREADY(S_AWREADY),
    .S_WDATA(S_WDATA), .S_WSTRB(S_WSTRB), .S_WVALID(S_WVALID), .S_WREADY(S_WREADY),
    .S_BRESP(S_BRESP), .S_BVALID(S_BVALID), .S_BREADY(S_BREADY),
    .S_ARADDR(S_ARADDR), .S_ARVALID(S_ARVALID), .S_ARREADY(S_ARREADY),
    .S_RDATA(S_RDATA), .S_RRESP(S_RRESP), .S_RVALID(S_RVALID), .S_RREADY(S_RREADY),
    .ctrl_start(ctrl_start), .ctrl_soft_rst(ctrl_soft_rst), .ctrl_mode_train(ctrl_mode_train),
    .ctrl_determ(ctrl_determ), .ctrl_dma_en(ctrl_dma_en),
    .i_dim(i_dim), .h_dim(h_dim), .frame_len(frame_len),
    .k_dim(k_dim), .scale_shift(scale_shift), .rng_seed(rng_seed),
    .tile_i(tile_i), .tile_h(tile_h), .batch_size(batch_size), .epochs(epochs),
    .lr(lr), .mom(mom), .wd(wd),
    .accum_clr_pos(accum_clr_pos), .accum_clr_neg(accum_clr_neg),
    .w_base_lo(w_base_lo), .w_base_hi(w_base_hi),
    .b_vis_base(b_vis_base), .b_hid_base(b_hid_base),
    .data_base_lo(data_base_lo), .data_base_hi(data_base_hi),
    .stat_busy(stat_busy), .stat_done(stat_done), .stat_err(stat_err),
    .stat_batch_done(stat_batch_done), .stat_epoch_done(stat_epoch_done),
    .stat_flags(stat_flags),
    .irq(irq), .ie_done(ie_done), .ie_batch(ie_batch), .ie_epoch(ie_epoch),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wen(mem_wen),
    .mem_sel(mem_sel), .mem_rdata(mem_rdata)
  );

  assign ie_done  = 1'b1;
  assign ie_batch = 1'b1;
  assign ie_epoch = 1'b1;

  // Memory window readback
  logic [15:0] mem_i;
  logic [15:0] mem_h;
  assign mem_i = mem_addr[15:0];
  assign mem_h = mem_addr[31:16];

  always_comb begin
    mem_rdata = 32'b0;
    case (mem_sel)
      3'd0: if (mem_i < I_DIM) mem_rdata = {{24{v0[mem_i][7]}}, v0[mem_i]};
      3'd1: if (mem_i < I_DIM && mem_h < H_DIM) mem_rdata = {{16{w[mem_i][mem_h][15]}}, w[mem_i][mem_h]};
      3'd2: if (mem_i < I_DIM) mem_rdata = {{16{b_vis[mem_i][15]}}, b_vis[mem_i]};
      3'd3: if (mem_h < H_DIM) mem_rdata = {{16{b_hid[mem_h][15]}}, b_hid[mem_h]};
      3'd4: if (mem_h < H_DIM) mem_rdata = {16'b0, h0_prob[mem_h]};
      3'd5: if (mem_h < H_DIM) mem_rdata = {16'b0, h1_prob[mem_h]};
      default: mem_rdata = 32'b0;
    endcase
  end

  // Memory window writes
  integer i, j;
  always_ff @(posedge ACLK) begin
    if (!ARESETn) begin
      for (i = 0; i < I_DIM; i = i + 1) begin
        v0[i] <= '0;
        v1[i] <= '0;
        b_vis[i] <= '0;
        for (j = 0; j < H_DIM; j = j + 1) begin
          w[i][j] <= '0;
        end
      end
      for (j = 0; j < H_DIM; j = j + 1) begin
        b_hid[j] <= '0;
        h0_prob[j] <= '0;
        h1_prob[j] <= '0;
        h0_samp[j] <= '0;
      end
    end else begin
      if (mem_wen) begin
        case (mem_sel)
          3'd0: if (mem_i < I_DIM) v0[mem_i] <= mem_wdata[7:0];
          3'd1: if (mem_i < I_DIM && mem_h < H_DIM) w[mem_i][mem_h] <= mem_wdata[15:0];
          3'd2: if (mem_i < I_DIM) b_vis[mem_i] <= mem_wdata[15:0];
          3'd3: if (mem_h < H_DIM) b_hid[mem_h] <= mem_wdata[15:0];
          default: ;
        endcase
      end
    end
  end

  // Training FSM
  typedef enum logic [3:0] {
    ST_IDLE,
    ST_POS_ACC,
    ST_POS_SIG,
    ST_POS_STORE,
    ST_NEG_ACC,
    ST_NEG_SIG,
    ST_NEG_STORE,
    ST_NEGH_ACC,
    ST_NEGH_SIG,
    ST_NEGH_STORE,
    ST_UPD_W,
    ST_UPD_BVIS,
    ST_UPD_BHID,
    ST_NEXT,
    ST_DONE
  } st_t;

  st_t st;
  logic [15:0] i_idx, h_idx;
  logic signed [31:0] acc;
  logic [15:0] epoch_cnt, batch_cnt;
  logic done_latch;
  logic batch_pulse, epoch_pulse;

  // Update path combinational helpers
  logic signed [23:0] pos_term;
  logic signed [23:0] neg_term;
  logic signed [24:0] delta_term;
  logic signed [41:0] scaled_term;
  logic signed [31:0] dw_term;
  logic signed [7:0]  diff_vis;
  logic signed [23:0] scaled_vis;
  logic signed [16:0] diff_hid;
  logic signed [33:0] scaled_hid;

  always_comb begin
    pos_term = $signed({{8{v0[i_idx][7]}}, v0[i_idx]}) * $signed(h0_prob[h_idx]);
    neg_term = $signed({{8{v1[i_idx][7]}}, v1[i_idx]}) * $signed(h1_prob[h_idx]);
    delta_term = pos_term - neg_term;
    scaled_term = $signed(delta_term) * $signed({1'b0, lr});
    dw_term = scaled_term >>> 16;

    diff_vis = v0[i_idx] - v1[i_idx];
    scaled_vis = $signed(diff_vis) * $signed({1'b0, lr});

    diff_hid = $signed({1'b0, h0_prob[h_idx]}) - $signed({1'b0, h1_prob[h_idx]});
    scaled_hid = $signed(diff_hid) * $signed({1'b0, lr});
  end

  assign stat_busy = (st != ST_IDLE);
  assign stat_done = done_latch;
  assign stat_err  = 1'b0;
  assign stat_batch_done = batch_pulse;
  assign stat_epoch_done = epoch_pulse;
  assign stat_flags = {16'b0, epoch_cnt};

  // Sampling helper
  function automatic logic sample_bit(input logic [15:0] p, input logic determ, input logic [15:0] r);
    begin
      if (determ) sample_bit = (p >= 16'h8000);
      else sample_bit = (r < p);
    end
  endfunction

  // Main FSM
  always_ff @(posedge ACLK) begin
    if (!ARESETn) begin
      st <= ST_IDLE;
      i_idx <= 0;
      h_idx <= 0;
      acc <= 0;
      sig_in <= 0;
      epoch_cnt <= 0;
      batch_cnt <= 0;
      done_latch <= 1'b0;
      batch_pulse <= 1'b0;
      epoch_pulse <= 1'b0;
    end else begin
      batch_pulse <= 1'b0;
      epoch_pulse <= 1'b0;

      if (ctrl_soft_rst) begin
        st <= ST_IDLE;
        i_idx <= 0;
        h_idx <= 0;
        acc <= 0;
        sig_in <= 0;
        epoch_cnt <= 0;
        batch_cnt <= 0;
        done_latch <= 1'b0;
      end else begin
        case (st)
          ST_IDLE: begin
            if (ctrl_start) begin
              done_latch <= 1'b0;
              epoch_cnt <= 0;
              batch_cnt <= 0;
              i_idx <= 0;
              h_idx <= 0;
              st <= ST_POS_ACC;
            end
          end

          // Positive phase: compute h0_prob
          ST_POS_ACC: begin
            if (i_idx == 0) begin
              acc <= {{16{b_hid[h_idx][15]}}, b_hid[h_idx]} +
                     ($signed({{8{v0[i_idx][7]}}, v0[i_idx]}) * $signed(w[i_idx][h_idx]));
            end else begin
              acc <= acc + ($signed({{8{v0[i_idx][7]}}, v0[i_idx]}) * $signed(w[i_idx][h_idx]));
            end

            if (i_idx == I_DIM-1) begin
              i_idx <= 0;
              st <= ST_POS_SIG;
            end else begin
              i_idx <= i_idx + 1'b1;
            end
          end
          ST_POS_SIG: begin
            sig_in <= acc[21:6];
            st <= ST_POS_STORE;
          end
          ST_POS_STORE: begin
            h0_prob[h_idx] <= sig_out;
            h0_samp[h_idx] <= sample_bit(sig_out, ctrl_determ, rnd) ? 8'h80 : 8'h00;
            if (h_idx == H_DIM-1) begin
              h_idx <= 0;
              st <= ST_NEG_ACC;
            end else begin
              h_idx <= h_idx + 1'b1;
              st <= ST_POS_ACC;
            end
          end

          // Negative phase: reconstruct v1
          ST_NEG_ACC: begin
            if (h_idx == 0) begin
              acc <= {{16{b_vis[i_idx][15]}}, b_vis[i_idx]} +
                     ($signed({{8{h0_samp[h_idx][7]}}, h0_samp[h_idx]}) * $signed(w[i_idx][h_idx]));
            end else begin
              acc <= acc + ($signed({{8{h0_samp[h_idx][7]}}, h0_samp[h_idx]}) * $signed(w[i_idx][h_idx]));
            end

            if (h_idx == H_DIM-1) begin
              h_idx <= 0;
              st <= ST_NEG_SIG;
            end else begin
              h_idx <= h_idx + 1'b1;
            end
          end
          ST_NEG_SIG: begin
            sig_in <= acc[21:6];
            st <= ST_NEG_STORE;
          end
          ST_NEG_STORE: begin
            v1[i_idx] <= sample_bit(sig_out, ctrl_determ, rnd) ? 8'h80 : 8'h00;
            if (i_idx == I_DIM-1) begin
              i_idx <= 0;
              st <= ST_NEGH_ACC;
            end else begin
              i_idx <= i_idx + 1'b1;
              st <= ST_NEG_ACC;
            end
          end

          // Negative hidden probabilities h1
          ST_NEGH_ACC: begin
            if (i_idx == 0) begin
              acc <= {{16{b_hid[h_idx][15]}}, b_hid[h_idx]} +
                     ($signed({{8{v1[i_idx][7]}}, v1[i_idx]}) * $signed(w[i_idx][h_idx]));
            end else begin
              acc <= acc + ($signed({{8{v1[i_idx][7]}}, v1[i_idx]}) * $signed(w[i_idx][h_idx]));
            end

            if (i_idx == I_DIM-1) begin
              i_idx <= 0;
              st <= ST_NEGH_SIG;
            end else begin
              i_idx <= i_idx + 1'b1;
            end
          end
          ST_NEGH_SIG: begin
            sig_in <= acc[21:6];
            st <= ST_NEGH_STORE;
          end
          ST_NEGH_STORE: begin
            h1_prob[h_idx] <= sig_out;
            if (h_idx == H_DIM-1) begin
              h_idx <= 0;
              st <= ST_UPD_W;
            end else begin
              h_idx <= h_idx + 1'b1;
              st <= ST_NEGH_ACC;
            end
          end

          // Weight update
          ST_UPD_W: begin
            w[i_idx][h_idx] <= w[i_idx][h_idx] + (dw_term >>> 8);

            if (h_idx == H_DIM-1) begin
              h_idx <= 0;
              if (i_idx == I_DIM-1) begin
                i_idx <= 0;
                st <= ST_UPD_BVIS;
              end else begin
                i_idx <= i_idx + 1'b1;
              end
            end else begin
              h_idx <= h_idx + 1'b1;
            end
          end

          // Visible bias update
          ST_UPD_BVIS: begin
            b_vis[i_idx] <= b_vis[i_idx] + (scaled_vis >>> 8);

            if (i_idx == I_DIM-1) begin
              i_idx <= 0;
              st <= ST_UPD_BHID;
            end else begin
              i_idx <= i_idx + 1'b1;
            end
          end

          // Hidden bias update
          ST_UPD_BHID: begin
            b_hid[h_idx] <= b_hid[h_idx] + (scaled_hid >>> 17);

            if (h_idx == H_DIM-1) begin
              h_idx <= 0;
              st <= ST_NEXT;
            end else begin
              h_idx <= h_idx + 1'b1;
            end
          end

          ST_NEXT: begin
            if (batch_cnt == batch_size - 1) begin
              batch_cnt <= 0;
              batch_pulse <= 1'b1;
              if (epoch_cnt == epochs - 1) begin
                epoch_cnt <= 0;
                epoch_pulse <= 1'b1;
                st <= ST_DONE;
              end else begin
                epoch_cnt <= epoch_cnt + 1'b1;
                st <= ST_POS_ACC;
              end
            end else begin
              batch_cnt <= batch_cnt + 1'b1;
              st <= ST_POS_ACC;
            end
          end

          ST_DONE: begin
            done_latch <= 1'b1;
            if (!ctrl_start) st <= ST_IDLE;
          end

          default: st <= ST_IDLE;
        endcase
      end
    end
  end

endmodule
