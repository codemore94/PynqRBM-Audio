// AXI-Lite wrapped minimal RBM core (forward path only for bring-up)
// Reset
logic rst; assign rst = ~aresetn;


// Control/Status wires
logic ctrl_start, ctrl_soft_rst, ctrl_mode_train, ctrl_determ, ctrl_dma_en;
logic [15:0] i_dim, h_dim, frame_len, tile_i, tile_h, batch_size, epochs, lr, mom, wd;
logic [7:0] k_dim; logic [4:0] scale_shift; logic [15:0] rng_seed;
logic accum_clr_pos, accum_clr_neg;
logic [31:0] w_base_lo,w_base_hi,b_vis_base,b_hid_base,data_base_lo,data_base_hi;
logic stat_busy, stat_done, stat_err, stat_batch_done, stat_epoch_done; logic [31:0] stat_flags;


// Instantiate AXI-Lite register block
rbm_ctrl_axi_lite u_regs (
.ACLK(aclk), .ARESETn(aresetn),
.S_AWADDR(S_AXIL_AWADDR), .S_AWVALID(S_AXIL_AWVALID), .S_AWREADY(S_AXIL_AWREADY),
.S_WDATA(S_AXIL_WDATA), .S_WSTRB(S_AXIL_WSTRB), .S_WVALID(S_AXIL_WVALID), .S_WREADY(S_AXIL_WREADY),
.S_BRESP(S_AXIL_BRESP), .S_BVALID(S_AXIL_BVALID), .S_BREADY(S_AXIL_BREADY),
.S_ARADDR(S_AXIL_ARADDR), .S_ARVALID(S_AXIL_ARVALID), .S_ARREADY(S_AXIL_ARREADY),
.S_RDATA(S_AXIL_RDATA), .S_RRESP(S_AXIL_RRESP), .S_RVALID(S_AXIL_RVALID), .S_RREADY(S_AXIL_RREADY),
.ctrl_start(ctrl_start), .ctrl_soft_rst(ctrl_soft_rst), .ctrl_mode_train(ctrl_mode_train),
.ctrl_determ(ctrl_determ), .ctrl_dma_en(ctrl_dma_en), .i_dim(i_dim), .h_dim(h_dim), .frame_len(frame_len),
.k_dim(k_dim), .scale_shift(scale_shift), .rng_seed(rng_seed), .tile_i(tile_i), .tile_h(tile_h),
.batch_size(batch_size), .epochs(epochs), .lr(lr), .mom(mom), .wd(wd), .accum_clr_pos(accum_clr_pos), .accum_clr_neg(accum_clr_neg),
.w_base_lo(w_base_lo), .w_base_hi(w_base_hi), .b_vis_base(b_vis_base), .b_hid_base(b_hid_base),
.data_base_lo(data_base_lo), .data_base_hi(data_base_hi),
.stat_busy(stat_busy), .stat_done(stat_done), .stat_err(stat_err), .stat_batch_done(stat_batch_done), .stat_epoch_done(stat_epoch_done), .stat_flags(stat_flags),
.irq(irq), .ie_done(1'b1), .ie_batch(1'b1), .ie_epoch(1'b1)
);


// Simple BRAM arrays for bring-up (replace with real memories)
logic signed [7:0] v_mem [I_DIM];
logic signed [15:0] w_col [I_DIM];
logic signed [31:0] b_j;
logic [15:0] p_j;


// Forward core
logic core_busy; assign stat_busy = core_busy;
rbm_core_min #(.I_DIM(I_DIM)) u_core (
.clk(aclk), .rst(rst | ctrl_soft_rst), .start(ctrl_start), .busy(core_busy),
.v_mem(v_mem), .w_col(w_col), .b_j(b_j), .p_j(p_j)
);


// Status bits: pulse DONE when core leaves busy
typedef enum logic [1:0] {S_IDLE,S_RUN} sst_t; sst_t sst; logic prev_busy;
always_ff @(posedge aclk) begin
if (rst) begin sst<=S_IDLE; prev_busy<=1'b0; stat_done<=1'b0; stat_err<=1'b0; stat_batch_done<=1'b0; stat_epoch_done<=1'b0; stat_flags<=32'b0; end
else begin
prev_busy <= core_busy;
stat_done <= (prev_busy && !core_busy); // one-cycle pulse
stat_batch_done <= 1'b0; stat_epoch_done<=1'b0; // not used yet
end
end


// Dummy init for bring-up (optional): tie b_j=0, w_col=0, v_mem=0 via initial
initial begin
b_j = '0; for (int i=0;i<I_DIM;i++) begin v_mem[i]=0; w_col[i]=0; end
end
endmodule
