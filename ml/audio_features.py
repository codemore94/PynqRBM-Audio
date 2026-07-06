"""
Audio front-end: waveform -> fixed-size log-mel feature vector.

Pure numpy/scipy (no librosa). Designed to produce a SMALL, fixed-length
vector suitable for an FPGA-scale RBM visible layer:

    N = n_mels * n_time_bins        (e.g. 16 * 4 = 64)

The time axis is pooled into a fixed number of bins so every clip yields the
same N regardless of length. Output is min-max normalised to [0,1] per the
whole training set (see fit_normalizer), matching Bernoulli RBM visible units.
"""
import numpy as np


def _hz_to_mel(f):
    return 2595.0 * np.log10(1.0 + f / 700.0)


def _mel_to_hz(m):
    return 700.0 * (10.0 ** (m / 2595.0) - 1.0)


def mel_filterbank(sr, n_fft, n_mels, fmin=40.0, fmax=None):
    """Triangular mel filterbank: shape (n_mels, n_fft//2 + 1)."""
    fmax = fmax or sr / 2.0
    n_bins = n_fft // 2 + 1
    mel_pts = np.linspace(_hz_to_mel(fmin), _hz_to_mel(fmax), n_mels + 2)
    hz_pts = _mel_to_hz(mel_pts)
    bin_pts = np.floor((n_fft + 1) * hz_pts / sr).astype(int)
    bin_pts = np.clip(bin_pts, 0, n_bins - 1)
    fb = np.zeros((n_mels, n_bins), dtype=np.float32)
    for m in range(1, n_mels + 1):
        l, c, r = bin_pts[m - 1], bin_pts[m], bin_pts[m + 1]
        for k in range(l, c):
            if c > l:
                fb[m - 1, k] = (k - l) / (c - l)
        for k in range(c, r):
            if r > c:
                fb[m - 1, k] = (r - k) / (r - c)
    return fb


def logmel_frames(wave, sr, n_fft=256, hop=128, n_mels=16, preemph=0.97):
    """Return log-mel spectrogram, shape (n_frames, n_mels)."""
    x = np.append(wave[0], wave[1:] - preemph * wave[:-1])
    if len(x) < n_fft:
        x = np.pad(x, (0, n_fft - len(x)))
    n_frames = 1 + (len(x) - n_fft) // hop
    win = np.hanning(n_fft).astype(np.float32)
    frames = np.stack([x[i * hop:i * hop + n_fft] * win for i in range(n_frames)])
    spec = np.abs(np.fft.rfft(frames, n=n_fft, axis=1)) ** 2
    fb = mel_filterbank(sr, n_fft, n_mels)
    mel = spec @ fb.T
    return np.log(mel + 1e-6).astype(np.float32)


def _pool_time(logmel, n_time_bins):
    """Average frames into n_time_bins fixed bins -> (n_time_bins, n_mels)."""
    n_frames = logmel.shape[0]
    edges = np.linspace(0, n_frames, n_time_bins + 1).astype(int)
    out = np.empty((n_time_bins, logmel.shape[1]), dtype=np.float32)
    for b in range(n_time_bins):
        lo, hi = edges[b], max(edges[b + 1], edges[b] + 1)
        out[b] = logmel[lo:hi].mean(axis=0)
    return out


def feature_vector(wave, sr, n_mels=16, n_time_bins=4, n_fft=256, hop=128):
    """waveform -> flat feature vector of length n_mels * n_time_bins."""
    lm = logmel_frames(wave, sr, n_fft=n_fft, hop=hop, n_mels=n_mels)
    pooled = _pool_time(lm, n_time_bins)          # (n_time_bins, n_mels)
    return pooled.reshape(-1)                       # length N


def batch_features(waves, sr, **kw):
    return np.stack([feature_vector(w, sr, **kw) for w in waves])


def fit_normalizer(X):
    """Per-feature min/max over the training set."""
    return X.min(axis=0), X.max(axis=0)


def apply_normalizer(X, lo, hi):
    """Scale to [0,1] using training min/max; clip out-of-range test values."""
    return np.clip((X - lo) / (hi - lo + 1e-9), 0.0, 1.0).astype(np.float32)
