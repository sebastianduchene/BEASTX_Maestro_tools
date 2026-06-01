#!/bin/bash
# BEAST X run for aln_2905_FLC_stems.xml on Maestro (edid_rtx6000, single RTX 6000).
# Unpartitioned ~1.4 Mb nucleotide alignment, 62 taxa, HKY+G, 50M states + MLE step.
# Decision: GPU — site patterns >> ~860 break-even (bioRxiv 2026.03.10.710534).
# Submit FROM the folder containing the XML (outputs land in the working dir):
#   sbatch beast_aln_2905_FLC_stems.sbatch

#SBATCH --job-name=beast_FLC_stems
#SBATCH --account=edid
#SBATCH --partition=edid_rtx6000
# No --qos: partition auto-applies its own QOS (edid_rtx6000: top priority, 365 d).
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=11
#SBATCH --gres=gpu:rtx6000:1     # single GPU: RTX PRO 6000 Blackwell, 96 GB (gres name 'rtx6000')
#SBATCH --mem=64G                # host RAM for the large alignment (node has ~1.4 TB)
#SBATCH --time=14-00:00:00       # generous: 50M states + path-sampling MLE is slow; adjust
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -euo pipefail

module purge
module load graalvm/ce-java8-20.0.0
module load beagle-lib
module load beast/v1.10.4

XML="aln_2905_FLC_stems.xml"

# Pre-flight: confirm BEAGLE sees the RTX 6000, and (in the run log) the pattern count.
beast -beagle_info

# Single-GPU run. -beagle_order 1 maps the BEAGLE instance to the GPU device.
beast -overwrite \
      -beagle_GPU \
      -beagle_order 1 \
      -threads 11 \
      "${XML}"

# Device: NVIDIA RTX PRO 6000 Blackwell, ~95 GB GPU memory (beast -beagle_info) —
# ample for this alignment; no out-of-memory concern. Newer/faster than the A40
# used in the benchmarking paper, so the GPU choice is well clear of the threshold.
