---
name: beast-slurm
description: Generate SLURM (sbatch) scripts to run BEAST X / BEAGLE phylogenetic analyses on the Institut Pasteur Maestro cluster using the edid team's dedicated resources. Use when the user wants to submit, schedule, or write an sbatch/SLURM script for BEAST, decide CPU vs GPU, or choose -threads / -beagle_GPU / -beagle_instances / -beagle_SSE settings for a phylogenetic run.
---

# BEAST on Maestro — SLURM script generator

Produce a ready-to-submit `sbatch` script for a BEAST X run on the Institut Pasteur **Maestro** cluster, choosing CPU vs GPU and the BEAGLE flags using the benchmarking guidelines from Fosse, Duchene & Duitama González (bioRxiv 2026.03.10.710534, "Benchmarking BEAGLE to find optimal parameters for BEAST X").

The goal: pick the configuration that minimises **wall-clock time** (and avoids wasting GPU/energy) for the dataset at hand. There is **no single optimal config** — it depends on the number of unique site patterns and whether the alignment is partitioned.

---

## Step 1 — Gather the two facts that drive the decision

1. **Number of unique site patterns** (per partition if partitioned, and the total).
   - BEAST prints `... <N> patterns` per alignment at startup. Get it from a short run on a compute node — e.g. start `beast <file>.xml`, let the patterns line print, then Ctrl-C. (A CPU node is fine for just reading the count; you do **not** need a GPU for this.)
   - You can often skip this: it only changes the decision near the ~860 threshold. For a large single alignment (e.g. a whole-genome alignment of hundreds of kb–Mb), patterns are far above 860, so GPU is the answer without counting. For a known partition layout, K alone decides it (partitioned → CPU).
   - For DENV-like data the paper's per-partition counts are ~40–1,300 and a complete CDS is ~4,600 (Table IV).
2. **Partitioned or not** — is the XML one alignment, or split into K sub-alignments (e.g. one per gene)? If partitioned, get **K = number of partitions**.

If the user hasn't supplied these, ask, or offer to run the quick pattern-counting dry run. You can also run `templates/recommend.sh <patterns> <partitions>` for a one-line recommendation.

**One-shot path:** if the user just wants it submitted, `templates/submit.sh <analysis.xml> --patterns N [--partitions K]` applies all the rules below, picks the CPU or GPU template, sets the thread count, and runs `sbatch`. Add `--dry-run` to preview the exact `sbatch` command without submitting; `--time`, `--mem`, `--threads` override the defaults. Use this rather than hand-editing a template when the inputs are known.

## Step 2 — Apply the decision rules (from the paper)

**Non-partitioned (single alignment):**
- **< ~860 unique site patterns → CPU.** GPU is slower than even a single core below this threshold. Use the `edid` CPU partition with multithreading (~11 threads is the sweet spot for these data; the paper saw 6→11 threads improve but 16 degrade).
- **≥ ~860 site patterns → single GPU.** ~2× faster than CPU for complete datasets. Use `edid_rtx6000` with **one** GPU.
- **Never request 2 GPUs** unless > ~25,000–30,000 site patterns, and even then the gain is marginal and rarely worth the cost — default to one.

**Partitioned (K partitions):**
- **Use CPU, not GPU.** For partitioned data GPU runs are > 2× slower than multithreading.
- **One thread per partition is fastest** (slightly better than two threads per partition). So set `-threads K` and `-beagle_instances K` on the `edid` partition.

> ⚠️ **Hardware caveat:** the ~860-pattern threshold was measured on **NVIDIA A40** cards. Maestro's `edid_rtx6000` partition has **RTX PRO 6000 Blackwell** GPUs (newer and faster, ~96 GB), so the real crossover is likely **at or below** 860 — i.e. GPU is favoured even sooner. Treat 860 as a conservative starting point; if a borderline dataset matters, benchmark both once (see Step 4). The 96 GB also means GPU memory is essentially never the constraint.

## Step 3 — Fill the template

Two templates live in `templates/`. Copy the right one, substitute the values, and write it next to the user's XML (or wherever they ask).

- `templates/beast_cpu.sbatch` — partition `edid`, no GPU.
- `templates/beast_gpu.sbatch` — partition `edid_rtx6000`, single RTX PRO 6000 Blackwell.

**Values to set:**

| Field | Rule |
|---|---|
| `--cpus-per-task` / `-threads` | Partitioned: `K`. Non-partitioned CPU: `11`. GPU: `11` (matches the paper's fastest single-GPU run). |
| `-beagle_instances` | CPU only: equal to `-threads`. Omit for GPU runs. |
| `--gres=gpu:rtx6000:1` | GPU script only. Keep at `:1` unless > ~25k patterns. |
| `--qos` | **Omit it.** Both dedicated partitions auto-apply their own partition QOS (`qos365d` on `edid`, `edid_rtx6000` on the GPU partition), granting 365-day walltime that overrides your default `normal` (1-day) cap. Do **not** pass `--qos=long` — it caps cores-per-user and is rejected for multi-core BEAST jobs (`QOSMaxCpuPerUserLimit`). |
| `--time` | Default `2-00:00:00`. Bump for large partitioned runs (some in the paper exceeded 24 h). Must stay ≤ the QOS MaxWall. |
| `--mem` | Default `16G`. The paper used 5–20 GB; raise to `32G`/`64G` for large alignments. Nodes have ≥ 720 GB, so memory is rarely the constraint. |
| `--job-name` | Derive from the XML basename. |

Always keep `-overwrite` and the `module load` stack, and the `beast -beagle_info` pre-flight line so the user can confirm BEAGLE sees the expected devices.

## Step 4 — (Optional) benchmark a borderline case

If a dataset sits near the threshold and runtime matters, submit the CPU and GPU scripts on the **same** XML, compare the reported wall time (or "time per million states" from the BEAST log for a short chain), and keep the faster one. This is the paper's suggested way to recalibrate for a model/hardware combination it didn't test.

---

## Maestro reference (edid team)

```
Account:  edid

CPU  partition: edid           4 nodes, 96 cores/node, ~720 GB RAM, no GPU
GPU  partition: edid_rtx6000   1 node, 128 cores, ~1.4 TB RAM,
                               7x NVIDIA RTX PRO 6000 Blackwell Max-Q,
                               ~96 GB GPU mem each (--gres=gpu:rtx6000:N)
                               (also a MIG-sliced card: gpu:2g.48gb)
                               GPUs visible only inside an allocation, not on submit node.

QOS handling: SUBMIT WITHOUT --qos. Each dedicated partition auto-applies its own
partition QOS, which overrides your default 'normal' (1-day) cap:
  partition edid          -> QOS qos365d        (365-day walltime)
  partition edid_rtx6000  -> QOS edid_rtx6000   (365-day walltime, top priority)
Verified: no-qos 5-day submit is accepted on both; --qos=long is REJECTED on
multi-core jobs (QOSMaxCpuPerUserLimit). Requestable QOS (fast/normal/long/gpu/
ultrafast/clcbio/clcgwb) are not needed for these partitions.

Launch stack:
  module load graalvm/ce-java8-20.0.0
  module load beagle-lib
  module load beast/v1.10.4
  beast -beagle_info          # list BEAGLE resources/devices
  beast -overwrite [flags] analysis.xml
```

Handy checks: `squeue -A edid`, `squeue -p edid_rtx6000`, `sinfo -p edid,edid_rtx6000`.

**Verifying GPU access (do this once, or before a long GPU job).** The GPU is **not visible on the submit node** — `beast -beagle_info` there shows only `0 : CPU`. The card appears only inside a SLURM allocation. Grab a short interactive GPU session to confirm the device, its memory, and that a run actually starts on it:

```
srun -A edid -p edid_rtx6000 --gres=gpu:rtx6000:1 -c 4 --mem=16G -t 00:30:00 --pty bash
module load graalvm/ce-java8-20.0.0 beagle-lib beast/v1.10.4
nvidia-smi --query-gpu=name,memory.total --format=csv     # expect RTX PRO 6000 Blackwell, ~96 GB
beast -beagle_info                                         # should list "1 : NVIDIA RTX PRO 6000 ... FRAMEWORK_CUDA"
beast -beagle_GPU -beagle_order 1 <file>.xml              # let it start sampling, then Ctrl-C
```

Confirmed on this cluster: resource `1` is an **NVIDIA RTX PRO 6000 Blackwell Max-Q, ~96 GB** (Global memory 97250 MB), `FRAMEWORK_CUDA`, single + double precision. With 96 GB, GPU memory is effectively never the limiting factor for BEAST nucleotide runs.

## Citation

If you use this skill (or its guidelines) for work you publish, please cite the
benchmarking paper the rules come from:

> Fosse S, Duchene S, Duitama González C. **Benchmarking BEAGLE to find optimal
> parameters for BEAST X.** bioRxiv 2026.03.10.710534 (2026).
> doi:10.64898/2026.03.10.710534. https://www.biorxiv.org/content/10.64898/2026.03.10.710534v1

BibTeX:

```bibtex
@article{fosse2026benchmarking,
  title   = {Benchmarking {BEAGLE} to find optimal parameters for {BEAST X}},
  author  = {Fosse, Samuel and Duchene, Sebastian and Duitama Gonz\'alez, Camila},
  journal = {bioRxiv},
  year    = {2026},
  doi     = {10.64898/2026.03.10.710534},
  url     = {https://www.biorxiv.org/content/10.64898/2026.03.10.710534v1},
  note    = {preprint}
}
```

You should also cite BEAST X, BEAGLE, and the models you use — see the paper's
references for the canonical list.

## BEAGLE flag cheat-sheet

| Flag | Meaning |
|---|---|
| `-beagle_SSE` | CPU SSE vectorisation (use on all CPU runs) |
| `-beagle_CPU` | force CPU backend |
| `-beagle_GPU` | use GPU backend |
| `-beagle_order 1` | map BEAGLE instance(s) to device(s); `1,2` for two GPUs |
| `-threads N` | BEAST compute threads |
| `-beagle_instances N` | split each partition's patterns across N BEAGLE instances (CPU) |
| `-beagle_info` | print available BEAGLE resources and exit |
