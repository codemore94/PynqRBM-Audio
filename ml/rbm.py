"""
Bernoulli RBM trained with Contrastive Divergence (CD-1), pure numpy.

This mirrors the *concept* of the hardware rbm_cd1 block: visible units in
[0,1], sigmoid hidden activations, one Gibbs step for the negative phase.
After training, `transform` returns the deterministic hidden probabilities,
which are fed to the softmax head as learned features.
"""
import numpy as np


def _sigmoid(x):
    return 1.0 / (1.0 + np.exp(-np.clip(x, -30, 30)))


class RBM:
    def __init__(self, n_visible, n_hidden, lr=0.05, epochs=30,
                 batch=32, momentum=0.5, weight_decay=1e-4, seed=0):
        self.nv, self.nh = n_visible, n_hidden
        self.lr, self.epochs, self.batch = lr, epochs, batch
        self.momentum, self.wd = momentum, weight_decay
        self.rng = np.random.default_rng(seed)
        self.W = 0.01 * self.rng.standard_normal((n_visible, n_hidden)).astype(np.float32)
        self.b_v = np.zeros(n_visible, dtype=np.float32)
        self.b_h = np.zeros(n_hidden, dtype=np.float32)

    def _sample(self, p):
        return (self.rng.random(p.shape) < p).astype(np.float32)

    def fit(self, X, verbose=False):
        dW = np.zeros_like(self.W)
        dbv = np.zeros_like(self.b_v)
        dbh = np.zeros_like(self.b_h)
        n = X.shape[0]
        for ep in range(self.epochs):
            idx = self.rng.permutation(n)
            recon_err = 0.0
            for s in range(0, n, self.batch):
                v0 = X[idx[s:s + self.batch]]
                # positive phase
                ph0 = _sigmoid(v0 @ self.W + self.b_h)
                h0 = self._sample(ph0)
                # negative phase (one Gibbs step)
                pv1 = _sigmoid(h0 @ self.W.T + self.b_v)
                ph1 = _sigmoid(pv1 @ self.W + self.b_h)
                m = v0.shape[0]
                gW = (v0.T @ ph0 - pv1.T @ ph1) / m - self.wd * self.W
                gbv = (v0 - pv1).mean(axis=0)
                gbh = (ph0 - ph1).mean(axis=0)
                dW = self.momentum * dW + self.lr * gW
                dbv = self.momentum * dbv + self.lr * gbv
                dbh = self.momentum * dbh + self.lr * gbh
                self.W += dW
                self.b_v += dbv
                self.b_h += dbh
                recon_err += np.mean((v0 - pv1) ** 2) * m
            if verbose:
                print(f"[rbm] epoch {ep+1:2d}/{self.epochs}  recon_mse={recon_err/n:.4f}")
        return self

    def transform(self, X):
        """Deterministic hidden probabilities -> learned feature vectors."""
        return _sigmoid(X @ self.W + self.b_h)
