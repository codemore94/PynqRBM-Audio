"""
Discriminative / Classification RBM (Larochelle & Bengio, 2008), pure numpy.

Unlike a plain RBM (which is trained unsupervised for reconstruction and does
not optimise class separability), the ClassRBM folds the label into the model
and trains p(y|x) directly. p(y|x) is TRACTABLE (sum over hidden units in
closed form), so training is exact gradient descent -- no CD sampling needed.

Inference is a matrix-vector product (W @ x) + per-class label weights + a
softplus reduction: the same MAC + nonlinearity datapath the FPGA RBM block
already has, so it maps to the existing accelerator concept.

    a[j,y] = c[j] + U[j,y] + (W x)[j]
    o[y]   = d[y] + sum_j softplus(a[j,y])
    p(y|x) = softmax_y(o)
"""
import numpy as np


def _softplus(x):
    return np.logaddexp(0.0, x)


def _sigmoid(x):
    return 1.0 / (1.0 + np.exp(-np.clip(x, -30, 30)))


def _softmax(z):
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


class ClassRBM:
    def __init__(self, n_visible, n_hidden, n_classes, lr=0.05, epochs=200,
                 batch=32, l2=1e-4, momentum=0.7, seed=0):
        rng = np.random.default_rng(seed)
        self.W = 0.05 * rng.standard_normal((n_hidden, n_visible)).astype(np.float32)
        self.U = 0.05 * rng.standard_normal((n_hidden, n_classes)).astype(np.float32)
        self.c = np.zeros(n_hidden, dtype=np.float32)
        self.d = np.zeros(n_classes, dtype=np.float32)
        self.lr, self.epochs, self.batch = lr, epochs, batch
        self.l2, self.momentum = l2, momentum
        self.nc = n_classes
        self.rng = rng

    def _logits(self, X):
        WX = X @ self.W.T                       # (n,H)
        a = self.c[None, :, None] + self.U[None, :, :] + WX[:, :, None]  # (n,H,C)
        o = self.d[None, :] + _softplus(a).sum(axis=1)                   # (n,C)
        return o, a

    def fit(self, X, y, verbose=False):
        n = X.shape[0]
        Y = np.eye(self.nc, dtype=np.float32)[y]
        vW = np.zeros_like(self.W); vU = np.zeros_like(self.U)
        vc = np.zeros_like(self.c); vd = np.zeros_like(self.d)
        for ep in range(self.epochs):
            idx = self.rng.permutation(n)
            for s in range(0, n, self.batch):
                b = idx[s:s + self.batch]
                xb, yb = X[b], Y[b]
                o, a = self._logits(xb)
                p = _softmax(o)
                g = (p - yb)                      # (m,C)  dL/do
                sig = _sigmoid(a)                 # (m,H,C)
                dLda = g[:, None, :] * sig        # (m,H,C)
                m = xb.shape[0]
                gd = g.mean(0)
                gU = dLda.mean(0) + self.l2 * self.U
                gc = dLda.sum(axis=2).mean(0)
                r = dLda.sum(axis=2)              # (m,H)
                gW = (r.T @ xb) / m + self.l2 * self.W
                vW = self.momentum * vW - self.lr * gW
                vU = self.momentum * vU - self.lr * gU
                vc = self.momentum * vc - self.lr * gc
                vd = self.momentum * vd - self.lr * gd
                self.W += vW; self.U += vU; self.c += vc; self.d += vd
            if verbose and (ep + 1) % 25 == 0:
                print(f"[classrbm] epoch {ep+1}/{self.epochs} train_acc={self.score(X,y):.3f}")
        return self

    def predict(self, X):
        o, _ = self._logits(X)
        return np.argmax(o, axis=1)

    def score(self, X, y):
        return float(np.mean(self.predict(X) == y))
