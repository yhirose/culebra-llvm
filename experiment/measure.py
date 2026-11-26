"""CPU seconds of `culebra --jit` per variant, variants interleaved per round.

usage: measure.py <culebra checkout> <out dir> <test name>...
"""
import os
import statistics
import subprocess
import sys

culebra, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
variants = ["apt22", "own", "pgo"]
programs = ["examples/hello.cul"] + [f"tests/{n}.cul" for n in names]
rounds = 7


def run(variant, program):
    p = subprocess.Popen(
        [f"{out}/culebra-{variant}/culebra", "--jit", program],
        cwd=culebra, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    _, status, usage = os.wait4(p.pid, 0)
    return usage.ru_utime + usage.ru_stime, os.waitstatus_to_exitcode(status)


times = {(v, p): [] for v in variants for p in programs}
codes = {(v, p): set() for v in variants for p in programs}
for r in range(rounds):
    for p in programs:
        for v in variants[r % 3:] + variants[:r % 3]:
            t, c = run(v, p)
            times[v, p].append(t)
            codes[v, p].add(c)

print(f"== CPU seconds, median of {rounds} (min-max)")
total = dict.fromkeys(variants, 0.0)
for p in programs:
    base = statistics.median(times["apt22", p])
    for v in variants:
        m = statistics.median(times[v, p])
        total[v] += m
        print(f"{p:32} {v:6} {m:7.3f} ({min(times[v, p]):.3f}-{max(times[v, p]):.3f})"
              f"  x{m / base:.3f}  exit {sorted(codes[v, p])}")
print("== total of medians")
for v in variants:
    print(f"{v:6} {total[v]:7.3f}  x{total[v] / total['apt22']:.3f}")
