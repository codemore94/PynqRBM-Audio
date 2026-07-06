# Phase 1 — audio-classification go/no-go (software reference)

Pure numpy/scipy pipeline (no TensorFlow/torch/librosa needed) that answers the
existential question **before** investing in hardware: *can an FPGA-scale RBM
classify audio?*

    wav ──> log-mel feature vector (N) ──> RBM ──> class label

## Run

```bash
cd ml
python3 run_experiment.py --classes 0 1 2 3 --source fsdd      # real spoken digits
python3 run_experiment.py --classes 0 1 2 3 4 5 6 7 8 9        # all 10 digits
python3 run_experiment.py --source synthetic                  # offline plumbing check
```

Dataset: **Free Spoken Digit Dataset** (8 kHz mono digits 0–9), auto-downloaded
once to `ml/data/recordings/`. Falls back to a synthetic tone dataset offline.

## Result (FSDD, random split, N=64 = 16 mel × 4 time-bins, hidden=64)

| task | chance | raw linear | unsupervised RBM | **Classification-RBM** |
|------|:------:|:----------:|:----------------:|:----------------------:|
| digits 0–3 | 0.25 | 0.78 | 0.46 | **0.97** |
| digits 0–1 | 0.50 | 0.97 | – | **0.99** |
| digits 0–9 | 0.10 | 0.52 | – | **0.92** |

## The key finding (drives the hardware design)

- The **log-mel front-end works** — features are linearly separable (0.78 on 4
  classes from a bare linear classifier).
- An **unsupervised / generative RBM (CD-1) *loses* information** — it optimises
  reconstruction, not separability, and lands *below* the linear baseline
  across a 24-point hyperparameter sweep (best 0.62). This is the flavour the
  current RTL (`rbm_cd1_top_axi.sv`) implements.
- A **discriminative Classification-RBM** (`classrbm.py`, Larochelle & Bengio
  2008) trains `p(y|x)` directly and **beats everything (0.92–0.99)**. It keeps
  the RBM MAC + softplus/sigmoid datapath, so it maps onto the existing
  accelerator concept — inference is `argmax_y [ d_y + Σ_j softplus(c_j + U_jy +
  (W x)_j) ]`.

**Verdict: GO — but the accelerator must implement a *discriminative* RBM
(add label weights `U`, train on `p(y|x)`), not the current generative CD-1.**

## Files

| file | role |
|------|------|
| `dataset.py` | FSDD download/cache + synthetic fallback |
| `audio_features.py` | wav → log-mel fixed-length vector, quantisation-ready |
| `rbm.py` | unsupervised Bernoulli RBM (CD-1) — the *current* design's model |
| `classrbm.py` | discriminative Classification-RBM — the *corrected* design |
| `softmax.py` | linear baseline / classifier head |
| `run_experiment.py` | ties it together, prints the GO/NO-GO verdict |

## Next (Phase 2)

Quantise `classrbm.py` to the HW fixed-point format (Q6.10 / Q0.16, matching
`sigmoid_q6p10_q0p16.mem`), re-measure accuracy, and emit weight `.mem` files +
golden input→label vectors as the RTL test oracle.
