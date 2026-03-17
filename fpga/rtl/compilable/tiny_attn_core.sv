// Tiny single-head self-attention core with memory-windowed storage.
module tiny_attn_core #(
  parameter integer MAX_SEQ_LEN = 8,
  parameter integer MAX_D_MODEL = 8
)(
  input  logic           clk,
  input  logic           resetn,
  input  logic           ctrl_start,
  input  logic           ctrl_soft_rst,
  input  logic           ctrl_mode_train,
  input  logic           ctrl_use_out_proj,
  input  logic           ctrl_causal,
  input  logic [15:0]    seq_len,
  input  logic [15:0]    d_model,
  input  logic [15:0]    d_head,
  input  logic [7:0]     score_shift,
  input  logic [15:0]    norm_bias,
  output logic           stat_busy,
  output logic           stat_done,
  output logic           stat_err,
  output logic [31:0]    stat_cycles,
  output logic [31:0]    stat_macs,
  output logic [31:0]    stat_stalls,
  input  logic [31:0]    mem_addr,
  input  logic [31:0]    mem_wdata,
  input  logic           mem_wen,
  input  logic [2:0]     mem_sel,
  output logic [31:0]    mem_rdata
);
  localparam logic [15:0] MAX_SEQ_U16 = MAX_SEQ_LEN;
  localparam logic [15:0] MAX_D_U16   = MAX_D_MODEL;

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_Q_ACC,
    ST_K_ACC,
    ST_SCORE_ACC,
    ST_V_ACC,
    ST_OUT_ACC,
    ST_DIRECT_STORE,
    ST_NEXT_QUERY,
    ST_DONE
  } st_t;

  logic signed [7:0] token_mem [0:MAX_SEQ_LEN-1][0:MAX_D_MODEL-1];
  logic signed [7:0] wq_mem    [0:MAX_D_MODEL-1][0:MAX_D_MODEL-1];
  logic signed [7:0] wk_mem    [0:MAX_D_MODEL-1][0:MAX_D_MODEL-1];
  logic signed [7:0] wv_mem    [0:MAX_D_MODEL-1][0:MAX_D_MODEL-1];
  logic signed [7:0] wo_mem    [0:MAX_D_MODEL-1][0:MAX_D_MODEL-1];
  logic signed [15:0] out_mem  [0:MAX_SEQ_LEN-1][0:MAX_D_MODEL-1];
  logic [15:0] attn_mat        [0:MAX_SEQ_LEN-1][0:MAX_SEQ_LEN-1];
  logic [15:0] attn_weight     [0:MAX_SEQ_LEN-1];
  logic signed [15:0] q_vec    [0:MAX_D_MODEL-1];
  logic signed [15:0] k_vec    [0:MAX_D_MODEL-1];
  logic signed [15:0] ctx_vec  [0:MAX_D_MODEL-1];

  st_t st;

  logic [15:0] q_idx, k_idx, in_idx, out_idx;
  logic [15:0] active_seq_len, active_d_model, active_d_head;
  logic [31:0] denom_acc;
  logic [31:0] denom_safe;
  logic signed [63:0] proj_acc;
  logic signed [63:0] sum_acc;
  logic start_d;

  logic signed [63:0] proj_term;
  logic signed [63:0] score_term;
  logic signed [63:0] ctx_term;
  logic signed [63:0] out_term;

  logic [15:0] mem_row;
  logic [15:0] mem_col;

  integer i, j;

  assign mem_row = mem_addr[31:16];
  assign mem_col = mem_addr[15:0];
  assign denom_safe = (denom_acc == 0) ? 32'd1 : denom_acc;

  always @* begin
    proj_term = 64'sd0;
    score_term = 64'sd0;
    ctx_term = 64'sd0;
    out_term = 64'sd0;

    if (q_idx < MAX_SEQ_U16 && in_idx < MAX_D_U16 && out_idx < MAX_D_U16) begin
      case (st)
        ST_Q_ACC: proj_term = $signed(token_mem[q_idx][in_idx]) * $signed(wq_mem[in_idx][out_idx]);
        ST_K_ACC: proj_term = $signed(token_mem[k_idx][in_idx]) * $signed(wk_mem[in_idx][out_idx]);
        ST_V_ACC: proj_term = $signed(token_mem[k_idx][in_idx]) * $signed(wv_mem[in_idx][out_idx]);
        default: proj_term = 64'sd0;
      endcase
    end

    if (out_idx < MAX_D_U16) begin
      score_term = $signed(q_vec[out_idx]) * $signed(k_vec[out_idx]);
    end

    if (k_idx < MAX_SEQ_U16) begin
      ctx_term = $signed({1'b0, attn_weight[k_idx]}) * $signed(sat16(proj_acc + proj_term));
    end

    if (in_idx < MAX_D_U16 && out_idx < MAX_D_U16) begin
      out_term = $signed(ctx_vec[in_idx]) * $signed(wo_mem[in_idx][out_idx]);
    end
  end

  function automatic logic signed [15:0] sat16(
    input logic signed [63:0] x
  );
    begin
      if (x > 64'sd32767)
        sat16 = 16'sh7fff;
      else if (x < -64'sd32768)
        sat16 = -16'sd32768;
      else
        sat16 = x[15:0];
    end
  endfunction

  function automatic logic [15:0] clamp_u16(
    input logic signed [63:0] x
  );
    begin
      if (x < 0)
        clamp_u16 = 16'd0;
      else if (x > 64'sd65535)
        clamp_u16 = 16'hffff;
      else
        clamp_u16 = x[15:0];
    end
  endfunction

  function automatic logic [15:0] score_to_weight(
    input logic signed [63:0] score,
    input logic [7:0] shift_amt,
    input logic [15:0] bias
  );
    logic signed [63:0] scaled;
    begin
      scaled = score >>> shift_amt;
      if (scaled < 0)
        scaled = 0;
      score_to_weight = clamp_u16(scaled + $signed({1'b0, bias}));
    end
  endfunction

  always @* begin
    mem_rdata = 32'b0;
    case (mem_sel)
      3'd0: if (mem_row < MAX_SEQ_U16 && mem_col < MAX_D_U16)
        mem_rdata = {{24{token_mem[mem_row][mem_col][7]}}, token_mem[mem_row][mem_col]};
      3'd1: if (mem_row < MAX_D_U16 && mem_col < MAX_D_U16)
        mem_rdata = {{24{wq_mem[mem_row][mem_col][7]}}, wq_mem[mem_row][mem_col]};
      3'd2: if (mem_row < MAX_D_U16 && mem_col < MAX_D_U16)
        mem_rdata = {{24{wk_mem[mem_row][mem_col][7]}}, wk_mem[mem_row][mem_col]};
      3'd3: if (mem_row < MAX_D_U16 && mem_col < MAX_D_U16)
        mem_rdata = {{24{wv_mem[mem_row][mem_col][7]}}, wv_mem[mem_row][mem_col]};
      3'd4: if (mem_row < MAX_D_U16 && mem_col < MAX_D_U16)
        mem_rdata = {{24{wo_mem[mem_row][mem_col][7]}}, wo_mem[mem_row][mem_col]};
      3'd5: if (mem_row < MAX_SEQ_U16 && mem_col < MAX_D_U16)
        mem_rdata = {{16{out_mem[mem_row][mem_col][15]}}, out_mem[mem_row][mem_col]};
      3'd6: if (mem_row < MAX_SEQ_U16 && mem_col < MAX_SEQ_U16)
        mem_rdata = {16'b0, attn_mat[mem_row][mem_col]};
      default: mem_rdata = 32'b0;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!resetn || ctrl_soft_rst) begin
      stat_busy <= 1'b0;
      stat_done <= 1'b0;
      stat_err <= 1'b0;
      stat_cycles <= 32'b0;
      stat_macs <= 32'b0;
      stat_stalls <= 32'b0;
      st <= ST_IDLE;
      q_idx <= '0;
      k_idx <= '0;
      in_idx <= '0;
      out_idx <= '0;
      active_seq_len <= 16'd1;
      active_d_model <= 16'd1;
      active_d_head <= 16'd1;
      denom_acc <= 32'd0;
      proj_acc <= 64'sd0;
      sum_acc <= 64'sd0;
      start_d <= 1'b0;
      for (i = 0; i < MAX_SEQ_LEN; i = i + 1) begin
        attn_weight[i] <= 16'b0;
        for (j = 0; j < MAX_D_MODEL; j = j + 1) begin
          token_mem[i][j] <= '0;
          out_mem[i][j] <= '0;
        end
        for (j = 0; j < MAX_SEQ_LEN; j = j + 1) begin
          attn_mat[i][j] <= '0;
        end
      end
      for (i = 0; i < MAX_D_MODEL; i = i + 1) begin
        q_vec[i] <= '0;
        k_vec[i] <= '0;
        ctx_vec[i] <= '0;
        for (j = 0; j < MAX_D_MODEL; j = j + 1) begin
          wq_mem[i][j] <= '0;
          wk_mem[i][j] <= '0;
          wv_mem[i][j] <= '0;
          wo_mem[i][j] <= '0;
        end
      end
    end else begin
      start_d <= ctrl_start;

      if (mem_wen) begin
        case (mem_sel)
          3'd0: if (mem_row < MAX_SEQ_U16 && mem_col < MAX_D_U16) token_mem[mem_row][mem_col] <= mem_wdata[7:0];
          3'd1: if (mem_row < MAX_D_U16 && mem_col < MAX_D_U16) wq_mem[mem_row][mem_col] <= mem_wdata[7:0];
          3'd2: if (mem_row < MAX_D_U16 && mem_col < MAX_D_U16) wk_mem[mem_row][mem_col] <= mem_wdata[7:0];
          3'd3: if (mem_row < MAX_D_U16 && mem_col < MAX_D_U16) wv_mem[mem_row][mem_col] <= mem_wdata[7:0];
          3'd4: if (mem_row < MAX_D_U16 && mem_col < MAX_D_U16) wo_mem[mem_row][mem_col] <= mem_wdata[7:0];
          default: ;
        endcase
      end

      if (stat_busy)
        stat_cycles <= stat_cycles + 1'b1;

      case (st)
        ST_IDLE: begin
          stat_busy <= 1'b0;
          if (ctrl_start && !start_d) begin
            stat_done <= 1'b0;
            stat_err <= 1'b0;
            stat_cycles <= 32'b0;
            stat_macs <= 32'b0;
            stat_stalls <= 32'b0;
            q_idx <= 16'd0;
            k_idx <= 16'd0;
            in_idx <= 16'd0;
            out_idx <= 16'd0;
            denom_acc <= 32'd0;
            proj_acc <= 64'sd0;
            sum_acc <= 64'sd0;
            active_seq_len <= (seq_len == 0) ? 16'd1 :
                              ((seq_len > MAX_SEQ_U16) ? MAX_SEQ_U16 : seq_len);
            active_d_model <= (d_model == 0) ? 16'd1 :
                              ((d_model > MAX_D_U16) ? MAX_D_U16 : d_model);
            active_d_head <= (d_head == 0) ? 16'd1 :
                             ((d_head > MAX_D_U16) ? MAX_D_U16 : d_head);
            stat_busy <= 1'b1;
            if (ctrl_mode_train) begin
              stat_err <= 1'b1;
              st <= ST_DONE;
            end else begin
              st <= ST_Q_ACC;
            end
          end
        end

        ST_Q_ACC: begin
          proj_acc <= proj_acc + proj_term;
          stat_macs <= stat_macs + 1'b1;
          if (in_idx + 1 >= active_d_model) begin
            q_vec[out_idx] <= sat16(proj_acc + proj_term);
            proj_acc <= 64'sd0;
            in_idx <= 16'd0;
            if (out_idx + 1 >= active_d_head) begin
              out_idx <= 16'd0;
              k_idx <= 16'd0;
              denom_acc <= 32'd0;
              st <= ST_K_ACC;
            end else begin
              out_idx <= out_idx + 1'b1;
            end
          end else begin
            in_idx <= in_idx + 1'b1;
          end
        end

        ST_K_ACC: begin
          if (ctrl_causal && (k_idx > q_idx)) begin
            attn_weight[k_idx] <= 16'd0;
            attn_mat[q_idx][k_idx] <= 16'd0;
            in_idx <= 16'd0;
            out_idx <= 16'd0;
            proj_acc <= 64'sd0;
            if (k_idx + 1 >= active_seq_len) begin
              k_idx <= 16'd0;
              out_idx <= 16'd0;
              in_idx <= 16'd0;
              proj_acc <= 64'sd0;
              sum_acc <= 64'sd0;
              st <= ST_V_ACC;
            end else begin
              k_idx <= k_idx + 1'b1;
            end
          end else begin
            proj_acc <= proj_acc + proj_term;
            stat_macs <= stat_macs + 1'b1;
            if (in_idx + 1 >= active_d_model) begin
              k_vec[out_idx] <= sat16(proj_acc + proj_term);
              proj_acc <= 64'sd0;
              in_idx <= 16'd0;
              if (out_idx + 1 >= active_d_head) begin
                out_idx <= 16'd0;
                sum_acc <= 64'sd0;
                st <= ST_SCORE_ACC;
              end else begin
                out_idx <= out_idx + 1'b1;
              end
            end else begin
              in_idx <= in_idx + 1'b1;
            end
          end
        end

        ST_SCORE_ACC: begin
          sum_acc <= sum_acc + score_term;
          stat_macs <= stat_macs + 1'b1;
          if (out_idx + 1 >= active_d_head) begin
            attn_weight[k_idx] <= score_to_weight(sum_acc + score_term, score_shift, norm_bias);
            attn_mat[q_idx][k_idx] <= score_to_weight(sum_acc + score_term, score_shift, norm_bias);
            denom_acc <= denom_acc + score_to_weight(sum_acc + score_term, score_shift, norm_bias);
            out_idx <= 16'd0;
            sum_acc <= 64'sd0;
            if (k_idx + 1 >= active_seq_len) begin
              k_idx <= 16'd0;
              in_idx <= 16'd0;
              proj_acc <= 64'sd0;
              st <= ST_V_ACC;
            end else begin
              k_idx <= k_idx + 1'b1;
              in_idx <= 16'd0;
              proj_acc <= 64'sd0;
              st <= ST_K_ACC;
            end
          end else begin
            out_idx <= out_idx + 1'b1;
          end
        end

        ST_V_ACC: begin
          proj_acc <= proj_acc + proj_term;
          stat_macs <= stat_macs + 1'b1;
          if (in_idx + 1 >= active_d_model) begin
            sum_acc <= sum_acc + ctx_term;
            stat_macs <= stat_macs + 1'b1;
            proj_acc <= 64'sd0;
            in_idx <= 16'd0;
            if (k_idx + 1 >= active_seq_len) begin
              ctx_vec[out_idx] <= sat16((sum_acc + ctx_term) / $signed({1'b0, denom_safe}));
              sum_acc <= 64'sd0;
              k_idx <= 16'd0;
              if (out_idx + 1 >= active_d_head) begin
                out_idx <= 16'd0;
                in_idx <= 16'd0;
                proj_acc <= 64'sd0;
                if (ctrl_use_out_proj)
                  st <= ST_OUT_ACC;
                else
                  st <= ST_DIRECT_STORE;
              end else begin
                out_idx <= out_idx + 1'b1;
              end
            end else begin
              k_idx <= k_idx + 1'b1;
            end
          end else begin
            in_idx <= in_idx + 1'b1;
          end
        end

        ST_OUT_ACC: begin
          proj_acc <= proj_acc + out_term;
          stat_macs <= stat_macs + 1'b1;
          if (in_idx + 1 >= active_d_head) begin
            out_mem[q_idx][out_idx] <= sat16((proj_acc + out_term) >>> 4);
            proj_acc <= 64'sd0;
            in_idx <= 16'd0;
            if (out_idx + 1 >= active_d_model) begin
              out_idx <= 16'd0;
              st <= ST_NEXT_QUERY;
            end else begin
              out_idx <= out_idx + 1'b1;
            end
          end else begin
            in_idx <= in_idx + 1'b1;
          end
        end

        ST_DIRECT_STORE: begin
          if (out_idx < active_d_head)
            out_mem[q_idx][out_idx] <= ctx_vec[out_idx];
          else
            out_mem[q_idx][out_idx] <= 16'sd0;

          if (out_idx + 1 >= active_d_model) begin
            out_idx <= 16'd0;
            st <= ST_NEXT_QUERY;
          end else begin
            out_idx <= out_idx + 1'b1;
          end
        end

        ST_NEXT_QUERY: begin
          if (q_idx + 1 >= active_seq_len) begin
            st <= ST_DONE;
          end else begin
            q_idx <= q_idx + 1'b1;
            k_idx <= 16'd0;
            in_idx <= 16'd0;
            out_idx <= 16'd0;
            proj_acc <= 64'sd0;
            sum_acc <= 64'sd0;
            denom_acc <= 32'd0;
            st <= ST_Q_ACC;
          end
        end

        ST_DONE: begin
          stat_busy <= 1'b0;
          stat_done <= 1'b1;
          st <= ST_IDLE;
        end

        default: st <= ST_IDLE;
      endcase
    end
  end
endmodule
