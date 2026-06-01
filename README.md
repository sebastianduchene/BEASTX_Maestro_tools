# BEASTX Maestro tools

Tools and a [Claude Code](https://claude.com/claude-code) **skill** for running
[BEAST X](https://beast.community/) phylogenetic analyses on the Institut Pasteur
**Maestro** cluster, using the **edid** team's dedicated CPU and GPU resources.

It bakes in the resource-allocation guidelines from our benchmarking paper
(Fosse, Duchene & Duitama González, bioRxiv 2026.03.10.710534) so that runs are
configured for the shortest wall-clock time — and so we don't waste GPU time or
energy when a CPU run would be just as fast.

> **The core rules**
> - **Partitioned alignment** → CPU (`edid`), **one thread per partition** (GPU is >2× slower here).
> - **Unpartitioned, < ~860 unique site patterns** → CPU (`edid`), ~11 threads.
> - **Unpartitioned, ≥ ~860 site patterns** → **single GPU** (`edid_rtx6000`); ~2× faster.
> - **Never** request 2 GPUs unless > ~25–30k patterns (gains are marginal).
>
> The ~860 threshold was calibrated on NVIDIA A40; Maestro's RTX PRO 6000 Blackwell
> is faster, so GPU is favoured at least as early. Benchmark borderline cases.

## What's here

```
beast-slurm/              # the Claude Code skill
  SKILL.md                # decision logic + Maestro/edid reference + citation
  templates/
    beast_cpu.sbatch      # CPU template (edid partition)
    beast_gpu.sbatch      # GPU template (edid_rtx6000, single RTX PRO 6000)
    recommend.sh          # print the recommended config for <patterns> [partitions]
    submit.sh             # pick the right template, set threads, and sbatch it
examples/
  beast_aln_2905_FLC_stems.sbatch   # a real worked GPU run
```

## How to use

The typical workflow on Maestro is three steps:

1. **Know two things about your run** — is the alignment *partitioned* (and into how
   many partitions `K`), and roughly how many *unique site patterns* it has. These
   two facts decide CPU vs GPU and the thread count (see the rules above). You can
   usually skip counting patterns — for a large single alignment it's far above 860
   (→ GPU), and for partitioned data `K` alone decides it (→ CPU).
2. **Pick the config** — let `recommend.sh` (or the Claude Code skill) choose the
   partition, CPU/GPU, and threads for you.
3. **Submit** — run `submit.sh` (or `sbatch` a template) **from the folder where you
   want the output files**, then watch the queue with `squeue -A edid`.

Two ways to do steps 2–3: the standalone scripts, or the Claude Code skill.

### Option 1 — standalone scripts (no Claude Code)

The helper scripts are plain Bash and work on Maestro on their own.

```bash
git clone https://github.com/sebastianduchene/BEASTX_Maestro_tools.git
cd BEASTX_Maestro_tools/beast-slurm/templates

# What config should I use? (e.g. 4634 patterns, unpartitioned)
./recommend.sh 4634

# Build the right sbatch command and preview it (nothing is submitted):
./submit.sh /path/to/analysis.xml --patterns 4634 --dry-run

# Submit for real (run from the folder where you want the outputs):
./submit.sh /path/to/analysis.xml --patterns 4634
```

`submit.sh` options: `--partitions K`, `--threads T`, `--time D-HH:MM:SS`,
`--mem 32G`, `--dry-run`, `-h`. Or copy a `templates/*.sbatch` file, edit the
`#SBATCH` lines, and `sbatch` it directly.

**Example output.** `--dry-run` prints the decision and the exact `sbatch` command
without submitting. A large unpartitioned alignment routes to a single GPU:

```text
$ ./submit.sh analysis.xml --patterns 4634 --dry-run
============================================================
 BEAST submit — analysis.xml
   site patterns : 4634   partitions: 1
   decision      : GPU / single RTX PRO 6000 Blackwell
   reason        : >= ~860 site patterns: single GPU ~2x faster than CPU.
   template      : beast_gpu.sbatch
   threads       : 11   mem: 16G   time: 2-00:00:00
   caveat        : ~860 threshold was A40-calibrated; Maestro's RTX PRO 6000 Blackwell is faster (threshold conservative).
============================================================
[dry-run] sbatch --cpus-per-task=11 --time=2-00:00:00 --mem=16G --job-name=beast_analysis beast_gpu.sbatch analysis.xml
```

…while a partitioned alignment routes to CPU with one thread per partition:

```text
$ ./submit.sh analysis.xml --patterns 480 --partitions 11 --dry-run
============================================================
 BEAST submit — analysis.xml
   site patterns : 480   partitions: 11
   decision      : CPU / partitioned
   reason        : partitioned data: GPU >2x slower than multithreading; one thread per partition is fastest.
   template      : beast_cpu.sbatch
   threads       : 11   mem: 16G   time: 2-00:00:00
   caveat        : ~860 threshold was A40-calibrated; Maestro's RTX PRO 6000 Blackwell is faster (threshold conservative).
============================================================
[dry-run] sbatch --cpus-per-task=11 --time=2-00:00:00 --mem=16G --job-name=beast_analysis beast_cpu.sbatch analysis.xml
```

Drop `--dry-run` to actually submit.

**Getting the site-pattern count:** start a short run on a compute node
(`beast <file>.xml`), let the `... <N> patterns` line print, then Ctrl-C. You can
usually skip this — for a large single alignment patterns far exceed 860 (→ GPU),
and for partitioned data the number of partitions alone decides it (→ CPU).

### Option 2 — as a Claude Code skill

Install the skill so Claude writes/submits the scripts for you. Pick one:

```bash
# Option A — symlink (stays in sync with git pull)
git clone https://github.com/sebastianduchene/BEASTX_Maestro_tools.git
ln -s "$(pwd)/BEASTX_Maestro_tools/beast-slurm" ~/.claude/skills/beast-slurm

# Option B — copy
cp -r BEASTX_Maestro_tools/beast-slurm ~/.claude/skills/beast-slurm
```

Then in Claude Code just ask, e.g. *"write a Maestro SLURM script for `run.xml`,
it's partitioned into 11 genes"* or *"…unpartitioned, ~4,600 site patterns"*, and
the `beast-slurm` skill produces the right `sbatch` file.

## Maestro reference (edid team)

| | `edid` (CPU) | `edid_rtx6000` (GPU) |
|---|---|---|
| Nodes | 4 | 1 (maestro-3447) |
| Cores/node | 96 | 128 |
| RAM/node | ~720 GB | ~1.4 TB |
| GPUs | none | 7× NVIDIA RTX PRO 6000 Blackwell Max-Q, ~96 GB each (`--gres=gpu:rtx6000:N`) |
| Account | `edid` | `edid` |

- **Submit without `--qos`** — each partition auto-applies its own QOS
  (`qos365d` / `edid_rtx6000`, both 365-day walltime), which overrides the default
  `normal` 1-day cap. Do **not** pass `--qos=long` (it caps cores-per-user and is
  rejected for multi-core jobs).
- **GPUs are invisible on the submit node.** Verify inside an allocation:
  `srun -A edid -p edid_rtx6000 --gres=gpu:rtx6000:1 -c 4 --mem=16G -t 00:30:00 --pty bash`,
  then `module load graalvm/ce-java8-20.0.0 beagle-lib beast/v1.10.4 && beast -beagle_info`.
- **Launch stack:** `module load graalvm/ce-java8-20.0.0 beagle-lib beast/v1.10.4`.

## Citation

If you use these tools/guidelines in published work, please cite:

> Fosse S, Duchene S, Duitama González C. **Benchmarking BEAGLE to find optimal
> parameters for BEAST X.** bioRxiv 2026.03.10.710534 (2026).
> doi:10.64898/2026.03.10.710534.
> <https://www.biorxiv.org/content/10.64898/2026.03.10.710534v1>

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

Please also cite BEAST X, BEAGLE, and the substitution/clock/tree models you use.

## License

MIT — see [LICENSE](LICENSE).
