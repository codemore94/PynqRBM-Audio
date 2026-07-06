"""
Dataset loader for the go/no-go audio-classification experiment.

Primary source: Free Spoken Digit Dataset (FSDD) -- spoken digits 0-9,
8 kHz mono 16-bit wav, several speakers. Small enough to fit an FPGA-scale
model. Downloaded once as a tarball and cached under ml/data/.

Fallback: a deterministic *synthetic* tone/formant dataset so the harness
still runs offline. Synthetic accuracy is NOT evidence the real task works --
it only exercises the code path.
"""
import io
import os
import sys
import tarfile
import urllib.request

import numpy as np
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "data")
REC_DIR = os.path.join(DATA_DIR, "recordings")
FSDD_TARBALL = (
    "https://github.com/Jakobovski/free-spoken-digit-dataset/"
    "archive/refs/heads/master.tar.gz"
)


def _download_fsdd():
    """Fetch and extract the FSDD recordings into REC_DIR (one-time)."""
    os.makedirs(REC_DIR, exist_ok=True)
    print(f"[dataset] downloading FSDD tarball ...", file=sys.stderr)
    raw = urllib.request.urlopen(FSDD_TARBALL, timeout=60).read()
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tf:
        for m in tf.getmembers():
            if m.isfile() and "/recordings/" in m.name and m.name.endswith(".wav"):
                base = os.path.basename(m.name)
                with open(os.path.join(REC_DIR, base), "wb") as out:
                    out.write(tf.extractfile(m).read())
    n = len([f for f in os.listdir(REC_DIR) if f.endswith(".wav")])
    print(f"[dataset] extracted {n} wav files -> {REC_DIR}", file=sys.stderr)


def load_fsdd(classes, target_len, per_class=None):
    """Return (waves, labels, sr). Each wave is float32 in [-1,1], length target_len.

    classes: list of digit ints, e.g. [0,1,2,3].
    per_class: cap files per class (None = all). Speaker-mixed random subset.
    """
    if not os.path.isdir(REC_DIR) or not any(
        f.endswith(".wav") for f in os.listdir(REC_DIR)
    ):
        _download_fsdd()

    files = sorted(f for f in os.listdir(REC_DIR) if f.endswith(".wav"))
    by_class = {c: [] for c in classes}
    for f in files:
        digit = int(f.split("_")[0])
        if digit in by_class:
            by_class[digit].append(f)

    rng = np.random.default_rng(0)
    waves, labels = [], []
    sr_seen = None
    for idx, c in enumerate(classes):
        fs = by_class[c]
        rng.shuffle(fs)
        if per_class:
            fs = fs[:per_class]
        if not fs:
            raise RuntimeError(f"no FSDD files for digit {c}")
        for f in fs:
            sr, data = wavfile.read(os.path.join(REC_DIR, f))
            sr_seen = sr_seen or sr
            x = data.astype(np.float32)
            if x.ndim > 1:
                x = x.mean(axis=1)
            x /= (np.max(np.abs(x)) + 1e-9)
            waves.append(_fit_len(x, target_len))
            labels.append(idx)
    return np.stack(waves), np.array(labels, dtype=np.int64), sr_seen


def make_synthetic(classes, target_len, sr=8000, per_class=120):
    """Deterministic multi-formant tones, one timbre per class, + noise.

    A stand-in so the pipeline runs offline. Distinguishable but easy --
    treat any accuracy here as a *plumbing* check only.
    """
    rng = np.random.default_rng(1)
    t = np.arange(target_len) / sr
    base = [(400, 900), (500, 1600), (700, 1100), (300, 2200),
            (650, 1900), (450, 1300), (800, 2500), (350, 700),
            (600, 1500), (750, 2000)]
    waves, labels = [], []
    for idx, c in enumerate(classes):
        f0, f1 = base[c % len(base)]
        for _ in range(per_class):
            jitter = rng.normal(1.0, 0.03)
            x = (np.sin(2 * np.pi * f0 * jitter * t)
                 + 0.6 * np.sin(2 * np.pi * f1 * jitter * t))
            x *= np.hanning(target_len) ** 0.5
            x += 0.15 * rng.standard_normal(target_len)
            x /= (np.max(np.abs(x)) + 1e-9)
            waves.append(x.astype(np.float32))
            labels.append(idx)
    return np.stack(waves), np.array(labels, dtype=np.int64), sr


def _fit_len(x, n):
    if len(x) >= n:
        return x[:n]
    return np.pad(x, (0, n - len(x)))


def load(classes, target_len, source="auto", per_class=None):
    """source: 'fsdd' | 'synthetic' | 'auto' (fsdd, fall back to synthetic)."""
    if source == "synthetic":
        return make_synthetic(classes, target_len)
    try:
        return load_fsdd(classes, target_len, per_class=per_class)
    except Exception as e:
        if source == "fsdd":
            raise
        print(f"[dataset] FSDD unavailable ({e}); using synthetic", file=sys.stderr)
        return make_synthetic(classes, target_len)
