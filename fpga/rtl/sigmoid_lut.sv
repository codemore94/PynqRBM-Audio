## `fpga/rtl/sigmoid_lut.sv`

```systemverilog
module sigmoid_lut #(
  parameter IN_W = 16,   // e.g., Q6.10 input
  parameter OUT_W = 16,  // Q0.16 output
  parameter ADDR_W = 10  // 1024 entries
)(
  input  logic                   clk,
  input  logic signed [IN_W-1:0] x,
  output logic        [OUT_W-1:0] y
);
  // Map x in [-6,6] to [0, 1023]
  localparam signed X_MIN = -6 <<< 10; // if Q6.10
  localparam signed X_MAX =  6 <<< 10;
  logic [ADDR_W-1:0] addr;
  logic [OUT_W-1:0] rom [0:(1<<ADDR_W)-1];
  initial $readmemh("../mem/sigmoid_q6p10_q0p16.mem", rom);

  logic signed [IN_W-1:0] x_clamped;
  always_comb begin
    x_clamped = (x < X_MIN) ? X_MIN : (x > X_MAX ? X_MAX : x);
    addr = (x_clamped - X_MIN) >>> (10 - (ADDR_W-10)); // scale to 1024
  end
  always_ff @(posedge clk) y <= rom[addr];
endmodule
```

---

## `fpga/rtl/lfsr16.sv`

```systemverilog
module lfsr16(
  input  logic clk, rst,
  input  logic [15:0] seed,
  output logic [15:0] rnd
);
  logic [15:0] s;
  always_ff @(posedge clk) begin
    if (rst) s <= seed;
    else     s <= {s[14:0], s[15]^s[13]^s[12]^s[10]};
  end
  assign rnd = s;
endmodule
```

---

## `fpga/rtl/outerprod_accum.sv`

```systemverilog
module outerprod_accum #(
  parameter I_TILE = 64,
  parameter H_TILE = 64
)(
  input  logic                   clk, rst,
  input  logic                   clr_pos,
  input  logic                   clr_neg,
  input  logic                   neg_phase, // 0=pos 1=neg
  input  logic                   sample_valid,
  input  logic signed [7:0]      v_i   [I_TILE],  // Q1.7
  input  logic        [15:0]     h_p   [H_TILE],  // Q0.16
  input  logic                   last_sample,
  output logic                   done
);
  // Linearized accum array: I_TILE*H_TILE of 32-bit signed (Q7.23)
  localparam N = I_TILE*H_TILE;
  logic signed [31:0] acc_pos [0:N-1];
  logic signed [31:0] acc_neg [0:N-1];

  // Clear
  integer idx;
  typedef enum logic [1:0] {IDLE, ACCUM, FIN} st_t;
  st_t st;

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= IDLE; done <= 1'b0;
      for (idx=0; idx<N; idx++) begin
        acc_pos[idx] <= '0; acc_neg[idx] <= '0;
      end
    end else begin
      done <= 1'b0;
      if (clr_pos) for (idx=0; idx<N; idx++) acc_pos[idx] <= '0;
      if (clr_neg) for (idx=0; idx<N; idx++) acc_neg[idx] <= '0;
      case (st)
        IDLE: if (sample_valid) st <= ACCUM;
        ACCUM: begin
          // time-multiplexed nested loop: unrolled lightly here
          for (int i=0;i<I_TILE;i++) begin
            for (int h=0; h<H_TILE; h++) begin
              automatic int a = i*H_TILE + h;
              // v_i(Q1.7)*h_p(Q0.16) => Q1.23
              logic signed [23:0] prod = $signed({{8{v_i[i][7]}},v_i[i]}) * $signed(h_p[h]);
              logic signed [31:0] ext  = {{8{prod[23]}},prod};
              if (!neg_phase) acc_pos[a] <= acc_pos[a] + ext; else acc_neg[a] <= acc_neg[a] + ext;
            end
          end
          if (last_sample) begin st <= FIN; end
        end
        FIN: begin done <= 1'b1; st <= IDLE; end
      endcase
    end
  end
endmodule
```

---

## `fpga/rtl/sgd_update_tile.sv`

```systemverilog
module sgd_update_tile #(
  parameter I_TILE = 64,
  parameter H_TILE = 64
)(
  input  logic           clk, rst,
  input  logic [15:0]    lr,   // Q0.16
  input  logic [15:0]    mom,  // Q0.16
  input  logic [15:0]    wd,   // Q0.16
  input  logic           start,
  output logic           busy,
  output logic           done,
  // BRAM-style read ports for accumulators (provided by a wrapper)
  input  logic signed [31:0] acc_pos_d, acc_neg_d,
  output logic [15:0]    acc_addr,     // 0..I_TILE*H_TILE-1
  // Weight read-modify-write stream
  input  logic signed [15:0] w_d,      // Q1.15 current
  output logic [15:0]    w_addr,
  output logic signed [15:0] w_q,      // Q1.15 updated
  output logic           w_we
);
  localparam N = I_TILE*H_TILE;
  logic [15:0] idx;
  typedef enum logic [1:0] {IDLE, RUN, FIN} st_t; st_t st;
  assign busy = (st==RUN);

  // Simple momentum buffer can be externalized; here we ignore for brevity

  always_ff @(posedge clk) begin
    if (rst) begin st <= IDLE; done <= 1'b0; idx<=0; w_we<=1'b0; end
    else begin
      done <= 1'b0; w_we<=1'b0;
      unique case(st)
        IDLE: if (start) begin idx<=0; st<=RUN; end
        RUN: begin
          // d = acc_pos - acc_neg  (Q7.23)
          logic signed [31:0] d = acc_pos_d - acc_neg_d;
          // upd = lr * d  (Q0.16 * Q7.23 -> Q7.39 -> >>16 -> Q7.23)
          logic signed [39:0] mul = $signed({{8{d[31]}},d}) * $signed({1'b0,lr});
          logic signed [31:0] upd = mul[39:8]; // >>16
          // weight decay: w = (1 - wd)*w  ~ w - wd*w
          logic signed [31:0] wd_mul = $signed({{16{w_d[15]}},w_d}) * $signed(wd); // Q1.31
          logic signed [31:0] wd_term= wd_mul >>> 16; // Q1.15 align
          logic signed [31:0] w_ext  = {{16{w_d[15]}}, w_d};
          logic signed [31:0] w_new  = w_ext + (upd >>> 8) - wd_term; // rescale to ~Q1.15
          // saturate to 16-bit
          logic signed [15:0] sat;
          if (w_new >  32767) sat = 16'sd32767;
          else if (w_new < -32768) sat = -16'sd32768;
          else sat = w_new[15:0];

          w_q   <= sat;
          w_addr<= idx;
          w_we  <= 1'b1;

          acc_addr <= idx;
          idx <= idx + 1;
          if (idx == N-1) st<=FIN;
        end
        FIN: begin done<=1'b1; st<=IDLE; end
      endcase
    end
  end
endmodule
```

---

## `fpga/rtl/rbm_core_min.sv`

```systemverilog
// Minimal forward GEMV + sigmoid for bring-up (one hidden at a time)
module rbm_core_min #(
  parameter I_DIM = 256
)(
  input  logic               clk, rst,
  input  logic               start,
  output logic               busy,
  // Frame buffer port
  input  logic signed [7:0]  v_mem   [I_DIM],   // Q1.7
  // Weight port for selected hidden j (provided by wrapper)
  input  logic signed [15:0] w_col  [I_DIM],   // Q1.15
  input  logic signed [31:0] b_j,             // bias aligned
  output logic       [15:0]  p_j              // Q0.16
);
  logic [15:0] i;
  logic signed [31:0] acc;
  typedef enum logic [1:0] {IDLE, ACC, ACT} st_t; st_t st;
  assign busy = (st!=IDLE);
  logic [15:0] sig_y;
  sigmoid_lut u_sig(.clk(clk), .x(acc[21:6]), .y(sig_y)); // crude mapping

  always_ff @(posedge clk) begin
    if (rst) begin st<=IDLE; i<=0; acc<=0; end
    else begin
      case(st)
        IDLE: if (start) begin i<=0; acc<=b_j; st<=ACC; end
        ACC: begin
          // acc += v[i]*w[i]
          logic signed [23:0] prod = $signed({{8{v_mem[i][7]}},v_mem[i]}) * $signed(w_col[i]);
          acc <= acc + {{8{prod[23]}},prod};
          i <= i + 1;
          if (i==I_DIM-1) st<=ACT;
        end
        ACT: begin
          p_j <= sig_y; st<=IDLE;
        end
      endcase
    end
  end
endmodule
```

---

## `fpga/scripts/build_project.tcl`

```tcl
create_project bolt_ear ./bolt_ear -part xc7z020clg400-1
set_property board_part digilentinc.com:pynq-z1:part0:1.0 [current_project]
read_verilog -sv [glob ../rtl/*.sv]
read_xdc ../bd/constraints.xdc
# Optional: source block design later; start with plain RTL top if you have one
update_compile_order -fileset sources_1
synth_design -top rbm_core_min -part xc7z020clg400-1
opt_design
place_design
route_design
write_bitstream -force bolt_ear.bit
write_hw_platform -fixed -include_bit -force bolt_ear.xsa
```

---

## `fpga/bd/create_bd.tcl`

```tcl
create_bd_design "bd_pl"
# Use clk_wiz to make 100 MHz
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list CONFIG.PRIM_IN_FREQ {100.0} CONFIG.CLK_OUT1_REQUESTED_OUT_FREQ {100.0}] [get_bd_cells clk_wiz_0]
# AXI interconnect + UART + Timer + BRAM will be added when you package the core as AXI IP
validate_bd_design
save_bd_design
```

---

## `training/make_sigmoid_lut.py`

```python
import numpy as np
# Q6.10 input in range [-6,6], 1024 entries -> Q0.16 output
xs = np.linspace(-6.0, 6.0, 1024)
y  = 1.0/(1.0+np.exp(-xs))
q  = np.clip(np.round(y*(1<<16)), 0, (1<<16)-1).astype(np.uint32)
with open('../fpga/mem/sigmoid_q6p10_q0p16.mem','w') as f:
    for v in q:
        f.write(f"{v:04x}\n")
print('Wrote sigmoid LUT')
```

---

## `training/golden_vectors.py`

```python
import numpy as np
np.random.seed(1)
I = 256
H = 64
v = np.random.randint(-128,128,size=I).astype(np.int8)
W = np.random.randint(-32768,32767,size=(I,H)).astype(np.int16)
b = np.random.randint(-2**15,2**15-1,size=H).astype(np.int32)
# Fixed-point ref (rough):
acc = b.copy()
for j in range(H):
    s = int(b[j])
    for i in range(I):
        s += int(v[i]) * int(W[i,j])
    acc[j]=s
np.savez('vectors.npz', v=v, W=W, b=b, acc=acc)
print('Saved vectors.npz')
```

---

## `sw_rv/bsp/linker.ld`

```ld
MEMORY { BRAM (rxw) : ORIGIN = 0x00000000, LENGTH = 128K }
SECTIONS {
  .text : { *(.text*) *(.rodata*) } > BRAM
  .data : { *(.data*) } > BRAM
  .bss  : { *(.bss*)  } > BRAM
  _heap_start = .; _heap_end = ORIGIN(BRAM)+LENGTH(BRAM);
}
```

---

## `sw_rv/app/main.c`

```c
#include <stdint.h>
#include <stdio.h>
// Stubbed MMIO helpers
#define REG32(a) (*(volatile uint32_t*)(a))
#define ACCEL 0x40002000u
#define R(off) REG32(ACCEL + (off))

int main(){
  // Configure minimal dims
  R(0x08)=256; R(0x0C)=64; R(0x14)=256; R(0x18)=10; // scaleshift=10
  // Start inference once (if wrapped)
  R(0x00)=1; // START
  for(volatile int i=0;i<1000000;i++);
  return 0;
}
```

---

## `sw_rv/Makefile`

```make
CROSS=riscv32-unknown-elf
CFLAGS=-Os -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -Wall
LDS=bsp/linker.ld
SRCS=app/main.c

all: app.elf app.bin
app.elf: $(SRCS)
	$(CROSS)-gcc $(CFLAGS) -T $(LDS) -o $@ $^
app.bin: app.elf
	$(CROSS)-objcopy -O binary $< $@
clean:
	rm -f app.elf app.bin
```

---

## `fpga/bd/constraints.xdc`

```xdc
# Placeholder; use board clock pins if you instantiate a top with external clock
```

---

### Next steps

1. Run `python training/make_sigmoid_lut.py` to create the LUT file.
2. Synthesize `rbm_core_min.sv` alone first with `build_project.tcl`.
3. Replace top in the TCL to your packaged IP/SoC top when ready.
4. Incrementally integrate `outerprod_accum` and `sgd_update_tile` behind an AXI-Lite shell.

```
```
