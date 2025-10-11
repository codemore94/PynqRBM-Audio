

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
