#!/bin/bash
# Pick the right BEAST/BEAGLE config on Maestro and submit it.
# Applies the benchmarking guidelines (bioRxiv 2026.03.10.710534, Fosse, Duchene &
# Duitama Gonzalez; https://www.biorxiv.org/content/10.64898/2026.03.10.710534v1 —
# please cite if used), chooses the CPU or GPU template, sets threads, runs sbatch.
#
# Usage:
#   ./submit.sh <analysis.xml> --patterns N [options]
#
# Required:
#   <analysis.xml>        BEAST XML to run
#   --patterns N          total unique site patterns (integer)
#
# Options:
#   --partitions K        number of data partitions (default: 1 = unpartitioned)
#   --threads T           override the recommended thread count
#   --time D-HH:MM:SS      walltime (default: 2-00:00:00)
#   --mem M               memory, e.g. 16G or 32G (default: 16G)
#   --dry-run             print the sbatch command instead of submitting
#   -h | --help           show this help
#
# Thresholds (A40-calibrated; Maestro's RTX PRO 6000 Blackwell is faster, so the
# real GPU crossover is likely at or below ~860 — GPU favoured even sooner):
#   GPU worthwhile (unpartitioned) at >= ~860 patterns
#   Second GPU only at > ~25000 patterns (this wrapper still uses ONE GPU;
#   edit beast_gpu.sbatch's two-GPU variant by hand if you really need it).

set -euo pipefail

GPU_THRESHOLD=860
TWO_GPU_THRESHOLD=25000
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; exit "${1:-0}"; }

# --- parse args ---
XML=""
PATTERNS=""
K=1
THREADS=""
TIME="2-00:00:00"
MEM="16G"
DRYRUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --patterns)   PATTERNS="${2:?--patterns needs a value}"; shift 2 ;;
        --partitions) K="${2:?--partitions needs a value}"; shift 2 ;;
        --threads)    THREADS="${2:?--threads needs a value}"; shift 2 ;;
        --time)       TIME="${2:?--time needs a value}"; shift 2 ;;
        --mem)        MEM="${2:?--mem needs a value}"; shift 2 ;;
        --dry-run)    DRYRUN=1; shift ;;
        -h|--help)    usage 0 ;;
        -*)           echo "Unknown option: $1" >&2; usage 1 ;;
        *)            if [ -z "${XML}" ]; then XML="$1"; else echo "Unexpected arg: $1" >&2; usage 1; fi; shift ;;
    esac
done

# --- validate ---
[ -n "${XML}" ]      || { echo "ERROR: missing <analysis.xml>" >&2; usage 1; }
[ -f "${XML}" ]      || { echo "ERROR: file not found: ${XML}" >&2; exit 1; }
[ -n "${PATTERNS}" ] || { echo "ERROR: missing --patterns N" >&2; usage 1; }
case "${PATTERNS}${K}${THREADS}" in *[!0-9]*) echo "ERROR: --patterns/--partitions/--threads must be integers" >&2; exit 1;; esac

# --- decide config (mirrors recommend.sh) ---
if [ "${K}" -gt 1 ]; then
    TEMPLATE="beast_cpu.sbatch"; MODE="CPU / partitioned"; REC_THREADS="${K}"
    REASON="partitioned data: GPU >2x slower than multithreading; one thread per partition is fastest."
elif [ "${PATTERNS}" -lt "${GPU_THRESHOLD}" ]; then
    TEMPLATE="beast_cpu.sbatch"; MODE="CPU / unpartitioned"; REC_THREADS=11
    REASON="< ~${GPU_THRESHOLD} site patterns: GPU is slower than CPU."
else
    TEMPLATE="beast_gpu.sbatch"; MODE="GPU / single RTX PRO 6000 Blackwell"; REC_THREADS=11
    REASON=">= ~${GPU_THRESHOLD} site patterns: single GPU ~2x faster than CPU."
fi
THREADS="${THREADS:-${REC_THREADS}}"

# --- report ---
echo "============================================================"
echo " BEAST submit — ${XML}"
echo "   site patterns : ${PATTERNS}   partitions: ${K}"
echo "   decision      : ${MODE}"
echo "   reason        : ${REASON}"
echo "   template      : ${TEMPLATE}"
echo "   threads       : ${THREADS}   mem: ${MEM}   time: ${TIME}"
if [ "${TEMPLATE}" = "beast_gpu.sbatch" ] && [ "${PATTERNS}" -gt "${TWO_GPU_THRESHOLD}" ]; then
    echo "   NOTE          : >${TWO_GPU_THRESHOLD} patterns — a 2nd GPU MAY help (marginal). Still using ONE."
fi
echo "   caveat        : ~${GPU_THRESHOLD} threshold was A40-calibrated; Maestro's RTX PRO 6000 Blackwell is faster (threshold conservative)."
echo "============================================================"

# --threads/-c override propagates to -threads & -beagle_instances inside the script
# (both read SLURM_CPUS_PER_TASK). --qos is intentionally NOT set (partition QOS applies).
CMD=(sbatch
     --cpus-per-task="${THREADS}"
     --time="${TIME}"
     --mem="${MEM}"
     --job-name="beast_$(basename "${XML}" .xml)"
     "${HERE}/${TEMPLATE}" "${XML}")

if [ "${DRYRUN}" -eq 1 ]; then
    echo "[dry-run] ${CMD[*]}"
else
    "${CMD[@]}"
fi
