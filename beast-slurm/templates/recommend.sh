#!/bin/bash
# Recommend a BEAST/BEAGLE config on Maestro from the benchmarking guidelines
# (Fosse, Duchene & Duitama Gonzalez, bioRxiv 2026.03.10.710534;
#  https://www.biorxiv.org/content/10.64898/2026.03.10.710534v1 — please cite if used).
#
# Usage:
#   ./recommend.sh <unique_site_patterns> [num_partitions]
#
#   <unique_site_patterns>  total unique site patterns (integer)
#   [num_partitions]        K, if the alignment is partitioned (default: 1 = unpartitioned)
#
# Thresholds (A40-calibrated; Maestro's RTX PRO 6000 Blackwell is faster, so the
# real GPU crossover is likely at or below ~860 — GPU favoured even sooner):
#   GPU worthwhile (unpartitioned) at >= ~860 patterns
#   Second GPU worthwhile only at > ~25000 patterns

set -euo pipefail

PATTERNS="${1:?Usage: recommend.sh <unique_site_patterns> [num_partitions]}"
K="${2:-1}"

GPU_THRESHOLD=860
TWO_GPU_THRESHOLD=25000

echo "Site patterns: ${PATTERNS}    Partitions: ${K}"
echo "----------------------------------------------"

if [ "${K}" -gt 1 ]; then
    echo "Recommendation: CPU (partition 'edid'), one thread per partition."
    echo "  Template : beast_cpu.sbatch"
    echo "  Threads  : ${K}   (--cpus-per-task=${K}, -threads ${K}, -beagle_instances ${K})"
    echo "  Why      : for partitioned data, GPU runs are >2x slower than multithreading;"
    echo "             one thread per partition was the fastest CPU option."
elif [ "${PATTERNS}" -lt "${GPU_THRESHOLD}" ]; then
    echo "Recommendation: CPU (partition 'edid'), ~11 threads."
    echo "  Template : beast_cpu.sbatch"
    echo "  Threads  : 11  (6->11 improved performance; 16 degraded it)"
    echo "  Why      : below ~${GPU_THRESHOLD} site patterns, GPU is slower than CPU."
else
    echo "Recommendation: single GPU (partition 'edid_rtx6000')."
    echo "  Template : beast_gpu.sbatch"
    echo "  GPUs     : 1   (--gres=gpu:rtx6000:1, -beagle_GPU, -threads 11)"
    echo "  Why      : >= ~${GPU_THRESHOLD} site patterns => ~2x speedup over CPU."
    if [ "${PATTERNS}" -gt "${TWO_GPU_THRESHOLD}" ]; then
        echo
        echo "  NOTE: >${TWO_GPU_THRESHOLD} patterns -- a 2nd GPU MAY help, but gains are"
        echo "        marginal. Benchmark before committing two cards."
    fi
fi

echo "----------------------------------------------"
echo "Caveat: the ~${GPU_THRESHOLD}-pattern threshold was measured on NVIDIA A40;"
echo "Maestro has a faster RTX PRO 6000 Blackwell, so the real crossover is likely"
echo "at or below ~${GPU_THRESHOLD} (GPU favoured even sooner). Benchmark borderline cases."
