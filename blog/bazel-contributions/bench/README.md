# Benchmarks

Each script prints one TSV row per run and writes it to `results/`.

| Script | Measures | Binaries |
|---|---|---|
| `exclusive_if_local.sh` | Wall time for N `exclusive-if-local` sleep tests under remote execution, plus a `no-remote-exec` control | before / after |
| `bwob_trust.sh` | Remote cache hits and wall time for a no-op `toplevel` rebuild after an `all` build of another target | before / after |
| `query_streamed_proto.sh` | `streamed_proto` query wall time, serial vs. parallel, with a byte-for-byte check of every output | one (flag-gated) |

## Running

```bash
bazel build //src:bazel-dev //src/tools/remote:worker_deploy.jar
```

```bash
export BENCH_ROOT=/tmp/bench BAZEL_AFTER=/path/to/bazel-after BAZEL_BEFORE=/path/to/bazel-before \
  WORKER_JAR=/path/to/worker_deploy.jar WORKER_JAVA=/path/to/jdk25/bin/java
```

```bash
N=12 S=5 RUNS=3 ./exclusive_if_local.sh
```

```bash
N=2000 RUNS=5 ./bwob_trust.sh
```

```bash
PKGS=200 TARGETS=500 RUNS=7 ./query_streamed_proto.sh
```

Run them one at a time. The query benchmark is CPU-bound, so it needs an otherwise idle machine.

## Results (medians)

| Benchmark | Before | After |
|---|---|---|
| 12 × 5s `exclusive-if-local` tests | 61.85s | 5.60s |
| `no-remote-exec` control | 61.27s | 61.32s |
| No-op rebuild, 2,000 actions: remote cache hits | 2,000 | 0 |
| No-op rebuild, 2,000 actions: wall time | 1.73s | 0.30s |
| `streamed_proto` query, 100k targets (serial → parallel) | 2.24s | 0.89s |

Hardware and source revisions are in `results/environment.txt`.
