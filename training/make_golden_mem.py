import numpy as np
np.random.seed(7)
I = 256
# Visible vector v (Q1.7)
v = np.random.randint(-128,128,size=I).astype(np.int8)
# One hidden column weights (Q1.15)
w = np.random.randint(-32768,32767,size=I).astype(np.int16)
# Bias b (Q6.26 accumulator units)
b = np.int32(0)
# Accumulate in 32-bit: sum v[i]*w[i] + b
acc = np.int64(b)
for i in range(I):
acc += np.int64(v[i])*np.int64(w[i])
# Shift to Q6.10-ish before LUT (>>10)
acc_shift = np.int32(np.clip(acc>>10, -2**31, 2**31-1))
# Write mem files
with open('../fpga/sim/vectors/v_mem.mem','w') as f:
for x in v: f.write(f"{(np.uint8(x)&0xFF):02x}
")
with open('../fpga/sim/vectors/w_col.mem','w') as f:
for x in w: f.write(f"{(np.uint16(x)&0xFFFF):04x}
")
with open('../fpga/sim/vectors/bias.mem','w') as f:
f.write(f"{(np.uint32(b)&0xFFFFFFFF):08x}
")
with open('../fpga/sim/vectors/acc_shift.mem','w') as f:
f.write(f"{(np.uint32(acc_shift)&0xFFFFFFFF):08x}
")
print('Wrote v_mem.mem, w_col.mem, bias.mem, acc_shift.mem')
