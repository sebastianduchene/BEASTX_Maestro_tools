#!/bin/bash
# Config guidelines: Fosse, Duchene & Duitama Gonzalez, bioRxiv 2026.03.10.710534
# (https://www.biorxiv.org/content/10.64898/2026.03.10.710534v1) — please cite if used.
#
# BEAST X on Maestro — GPU (edid_rtx6000 partition, single RTX PRO 6000 Blackwell, ~96 GB).
# Use for: NON-partitioned alignments with >= ~860 unique site patterns.
#          (For partitioned data, use beast_cpu.sbatch — GPU is >2x slower there.)
# Usage:   sbatch beast_gpu.sbatch path/to/analysis.xml
#
# Keep ONE GPU unless the alignment has > ~25,000-30,000 site patterns
# (two GPUs give only marginal gains and rarely justify the cost).

#SBATCH --job-name=beast_gpu
#SBATCH --account=edid
#SBATCH --partition=edid_rtx6000
# NOTE: do NOT set --qos. The 'edid_rtx6000' partition auto-applies its own QOS
# (edid_rtx6000: top priority, 365-day walltime), overriding the 'normal' default cap.
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=11      # paper's fastest single-GPU run used 11 threads
#SBATCH --gres=gpu:rtx6000:1    # ONE GPU (see note above)
#SBATCH --mem=16G               # paper used 5-20 GB; raise for large alignments
#SBATCH --time=2-00:00:00       # must be <= QOS MaxWall
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -euo pipefail

module purge
module load graalvm/ce-java8-20.0.0
module load beagle-lib
module load beast/v1.10.4

XML="${1:?Usage: sbatch beast_gpu.sbatch <analysis.xml>}"
THREADS="${SLURM_CPUS_PER_TASK}"

# Pre-flight: confirm BEAGLE sees the GPU (RTX PRO 6000 Blackwell) device.
beast -beagle_info

# Single-GPU run. -beagle_order 1 maps the BEAGLE instance to the GPU device.
beast -overwrite \
      -beagle_GPU \
      -beagle_order 1 \
      -threads "${THREADS}" \
      "${XML}"

# ---------------------------------------------------------------------------
# TWO-GPU variant (ONLY if > ~25k-30k site patterns). Replace the gres line
# with:  #SBATCH --gres=gpu:rtx6000:2   and the beast call with:
#   beast -overwrite -beagle_GPU -beagle_order 1,2 -beagle_instances 2 \
#         -threads "${THREADS}" "${XML}"
# ---------------------------------------------------------------------------
