#!/usr/bin/env python3
"""Compare RTL simulation samples against the C reference model.

usage: compare.py <rtl_samples.csv> <model_samples.csv>

Checks every sample (latch cycle, x, y, hit) and the final hit count,
total count and Q3.29 pi result. Exits non-zero on the first mismatch.
"""
import sys


def load(path):
    samples, final = [], None
    with open(path) as f:
        next(f)  # header
        for line in f:
            line = line.strip()
            if line.startswith("final"):
                final = dict(kv.split("=") for kv in line.split(",")[1:])
            elif line:
                samples.append(line.split(","))
    return samples, final


def main():
    rtl, rtl_final = load(sys.argv[1])
    model, model_final = load(sys.argv[2])
    fields = ["idx", "cycle", "x", "y", "hit"]

    if len(rtl) != len(model):
        print(f"FAIL: sample count differs (rtl {len(rtl)}, model {len(model)})")
        return 1

    for r, m in zip(rtl, model):
        if r != m:
            diffs = [f"{n}: rtl={a} model={b}" for n, a, b in zip(fields, r, m) if a != b]
            print(f"FAIL: first mismatch at sample {r[0]} -> " + "; ".join(diffs))
            return 1

    if rtl_final != model_final:
        print(f"FAIL: final result differs\n  rtl  : {rtl_final}\n  model: {model_final}")
        return 1

    pi = int(rtl_final["pi_q"]) / 2**29
    print(f"PASS: {len(rtl)} samples match bit-for-bit "
          f"(cycle, x, y, hit); hits={rtl_final['hits']} total={rtl_final['total']} "
          f"pi_q={rtl_final['pi_q']} ({pi:.9f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
