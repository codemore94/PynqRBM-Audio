# hw/scripts/gen_softplus_lut.py

import numpy as np

# Sama kuin common/fixedpoint.py:ssa
FIXED_TOTAL_BITS = 16
FIXED_FRAC_BITS  = 11

FIXED_SCALE = 1 << FIXED_FRAC_BITS
FIXED_MAX = (1 << (FIXED_TOTAL_BITS - 1)) - 1
FIXED_MIN = - (1 << (FIXED_TOTAL_BITS - 1))

def float_to_fixed_scalar(x: float) -> int:
    y = int(round(x * FIXED_SCALE))
    y = max(min(y, FIXED_MAX), FIXED_MIN)
    # muutetaan 16-bittiseksi allekirjoitetuksi
    if y < 0:
        y = (1 << FIXED_TOTAL_BITS) + y
    return y

def softplus(x):
    # numeerisesti vakaa softplus
    # softplus(x) = log(1 + exp(x))
    # jos x iso, log1p(exp(x)) ≈ x
    if x > 20:
        return x
    if x < -20:
        return np.exp(x)  # log(1+e^x) ~ e^x kun x<<0
    return float(np.log1p(np.exp(x)))

def main():
    N = 256
    x_min = -8.0
    x_max =  8.0

    xs = np.linspace(x_min, x_max, N)
    ys = [softplus(x) for x in xs]

    # Kirjoitetaan .mem-tyyppinen heksatiedosto LUT:lle
    with open("softplus_lut.mem", "w") as f:
        for y in ys:
            val = float_to_fixed_scalar(y)  # 16-bit signed fixed
            f.write(f"{val:04X}\n")

    print("Generated softplus_lut.mem")

if __name__ == "__main__":
    main()
