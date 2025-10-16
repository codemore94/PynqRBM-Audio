import numpy as np
# Q6.10 input in range [-6,6], 1024 entries -> Q0.16 output
xs = np.linspace(-6.0, 6.0, 1024)
y = 1.0/(1.0+np.exp(-xs))
q = np.clip(np.round(y*(1<<16)), 0, (1<<16)-1).astype(np.uint32)
with open('../fpga/mem/sigmoid_q6p10_q0p16.mem','w') as f:
    for v in q:
        f.write(f"{v:04x}\n")
print('Wrote sigmoid LUT')
