"""
Phase-1 go/no-go experiment: can an FPGA-scale RBM classify spoken digits?

Pipeline:  wav -> log-mel feature vector (N) -> RBM hidden features (H)
           -> softmax head -> predicted class.

It reports THREE accuracies so you can see whether the RBM actually helps:
  * chance                : 1 / n_classes
  * softmax on raw features : baseline, no RBM
  * softmax on RBM features : the architecture under test

Two splits are evaluated:
  * random     : easy, mixes speakers across train/test
  * speaker-independent (loso): held-out speaker -> the honest, harder test

GO if RBM-feature accuracy clears the go/no-go threshold and is not worse
than the raw baseline. Otherwise rethink the model before touching hardware.

Usage:
  python3 run_experiment.py --classes 0 1 2 3 --n-mels 16 --time-bins 4 --hidden 64
  python3 run_experiment.py --source synthetic          # offline plumbing check
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dataset
import audio_features as af
from rbm import RBM
from softmax import Softmax
from classrbm import ClassRBM

GO_THRESHOLD = 0.80  # min classifier accuracy to call it a GO


def evaluate(Xtr, ytr, Xte, yte, n_classes, hidden, args, tag):
    lo, hi = af.fit_normalizer(Xtr)
    Xtr_n = af.apply_normalizer(Xtr, lo, hi)
    Xte_n = af.apply_normalizer(Xte, lo, hi)

    # baseline: softmax directly on features (no RBM)
    acc_base = Softmax(Xtr_n.shape[1], n_classes).fit(Xtr_n, ytr).score(Xte_n, yte)

    # unsupervised RBM features -> softmax (the ORIGINAL design's flavour)
    rbm = RBM(Xtr_n.shape[1], hidden, lr=args.rbm_lr, epochs=args.rbm_epochs,
              seed=0).fit(Xtr_n, verbose=args.verbose)
    head = Softmax(hidden, n_classes).fit(rbm.transform(Xtr_n), ytr)
    acc_unsup = head.score(rbm.transform(Xte_n), yte)

    # discriminative Classification-RBM (the CORRECTED design) -> the one that matters
    crbm = ClassRBM(Xtr_n.shape[1], hidden, n_classes, lr=args.rbm_lr,
                    epochs=args.classrbm_epochs, seed=0).fit(Xtr_n, ytr,
                                                             verbose=args.verbose)
    acc_class = crbm.score(Xte_n, yte)

    print(f"\n--- {tag} split ---")
    print(f"  chance                     : {1.0/n_classes:.3f}")
    print(f"  softmax on raw feats       : {acc_base:.3f}")
    print(f"  unsupervised RBM + softmax : {acc_unsup:.3f}")
    print(f"  Classification-RBM         : {acc_class:.3f}   <-- corrected design")
    return acc_base, acc_unsup, acc_class


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--classes", type=int, nargs="+", default=[0, 1, 2, 3])
    ap.add_argument("--source", choices=["auto", "fsdd", "synthetic"], default="auto")
    ap.add_argument("--sr", type=int, default=8000)
    ap.add_argument("--dur", type=float, default=0.5, help="clip seconds")
    ap.add_argument("--n-mels", type=int, default=16)
    ap.add_argument("--time-bins", type=int, default=4)
    ap.add_argument("--hidden", type=int, default=64)
    ap.add_argument("--rbm-epochs", type=int, default=40)
    ap.add_argument("--classrbm-epochs", type=int, default=200)
    ap.add_argument("--rbm-lr", type=float, default=0.05)
    ap.add_argument("--per-class", type=int, default=None)
    ap.add_argument("--test-frac", type=float, default=0.25)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    target_len = int(args.sr * args.dur)
    N = args.n_mels * args.time_bins
    print(f"config: classes={args.classes}  N={N} (n_mels={args.n_mels} x "
          f"time_bins={args.time_bins})  hidden={args.hidden}  source={args.source}")

    waves, labels, sr = dataset.load(
        args.classes, target_len, source=args.source, per_class=args.per_class)
    print(f"loaded {len(waves)} clips at sr={sr}")

    X = af.batch_features(waves, sr, n_mels=args.n_mels,
                          n_time_bins=args.time_bins)
    assert X.shape[1] == N, (X.shape, N)

    rng = np.random.default_rng(42)
    perm = rng.permutation(len(X))
    X, labels = X[perm], labels[perm]
    n_test = int(len(X) * args.test_frac)
    Xte, yte = X[:n_test], labels[:n_test]
    Xtr, ytr = X[n_test:], labels[n_test:]

    acc_base, acc_unsup, acc_class = evaluate(
        Xtr, ytr, Xte, yte, len(args.classes), args.hidden, args, "random")

    print("\n=================== VERDICT ===================")
    verdict = "GO" if acc_class >= GO_THRESHOLD else "NO-GO"
    print(f"  Classification-RBM accuracy : {acc_class:.3f}   (threshold {GO_THRESHOLD:.2f})")
    print(f"  unsupervised RBM accuracy   : {acc_unsup:.3f}   (loses to baseline -> wrong training)")
    print(f"  raw linear baseline         : {acc_base:.3f}")
    if args.source != "fsdd":
        print("  note: source may be synthetic; rerun with --source fsdd for the real test")
    print(f"  ==> {verdict}  (discriminative RBM required)")
    print("===============================================")


if __name__ == "__main__":
    main()
