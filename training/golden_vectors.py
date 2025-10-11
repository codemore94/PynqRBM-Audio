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
