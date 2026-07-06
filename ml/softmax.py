"""Multinomial logistic-regression (softmax) head, pure numpy."""
import numpy as np


def _softmax(z):
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


class Softmax:
    def __init__(self, n_features, n_classes, lr=0.1, epochs=300,
                 l2=1e-3, seed=0):
        rng = np.random.default_rng(seed)
        self.W = 0.01 * rng.standard_normal((n_features, n_classes)).astype(np.float32)
        self.b = np.zeros(n_classes, dtype=np.float32)
        self.lr, self.epochs, self.l2 = lr, epochs, l2

    def fit(self, X, y):
        n, k = X.shape[0], self.b.shape[0]
        Y = np.eye(k, dtype=np.float32)[y]
        for _ in range(self.epochs):
            P = _softmax(X @ self.W + self.b)
            gW = X.T @ (P - Y) / n + self.l2 * self.W
            gb = (P - Y).mean(axis=0)
            self.W -= self.lr * gW
            self.b -= self.lr * gb
        return self

    def predict(self, X):
        return np.argmax(X @ self.W + self.b, axis=1)

    def score(self, X, y):
        return float(np.mean(self.predict(X) == y))
