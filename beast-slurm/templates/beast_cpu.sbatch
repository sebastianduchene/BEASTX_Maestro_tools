#!/bin/bash
# Config guidelines: Fosse, Duchene & Duitama Gonzalez, bioRxiv 2026.03.10.710534
# (https://www.biorxiv.org/content/10.64898/2026.03.10.710534v1) — please cite if used.
#
# BEAST X on Maestro — CPU (edid partition).
# Use for: non-partitioned alignments with < ~860 unique site patterns,
#          OR any partitioned dataset (one thread per partition).
# Usage:   sbatch beast_cpu.sbatch path/to/analysis.xml
#
# Set THREADS below:
#   - partitioned:      = number of partitions K (one thread per partition)
#   - non-partitioned:  = 11 (the benchmarking sweet spot; 16 was slower)
# Keep --cpus-per-task and -threads identical.

#SBATCH --job-name=beast_cpu
#SBATCH --account=edid
#SBATCH --partition=edid
# NOTE: do NOT set --qos. The 'edid' partition auto-applies its own QOS (qos365d),
# which grants 365-day walltime and overrides your default 'normal' (1-day) cap.
# Adding --qos=long is REJECTED here (QOSMaxCpuPerUserLimit caps cores-per-user).
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=11      # = THREADS (= K for partitioned data)
#SBATCH --mem=16G               # paper used 5-20 GB; raise for large alignments
#SBATCH --time=2-00:00:00       # must be <= QOS MaxWall
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -euo pipefail

module purge
module load graalvm/ce-java8-20.0.0
module load beagle-lib
module load beast/v1.10.4

XML="${1:?Usage: sbatch beast_cpu.sbatch <analysis.xml>}"
THREADS="${SLURM_CPUS_PER_TASK}"

# Pre-flight: confirm BEAGLE sees the expected CPU resource.
beast -beagle_info

# CPU run: SSE vectorisation, one BEAGLE instance per thread/partition.
beast -overwrite \
      -beagle_CPU \
      -beagle_SSE \
      -threads "${THREADS}" \
      -beagle_instances "${THREADS}" \
      "${XML}"
