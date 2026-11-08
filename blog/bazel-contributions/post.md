# Three Changes I Landed in Bazel

Bazel is most of my day job: monorepo builds, remote execution, CI. When it gets in the way, I'd rather fix it upstream than leave a workaround in place. Three of those fixes are now merged into Bazel.

| Change | Measured result |
|---|---|
| `exclusive-if-local` tests run in parallel under remote execution | 12 tests: 61.9s → 5.6s (11x) |
| Build without the Bytes stops re-running actions after a broader download policy | No-op rebuild: 2,000 remote cache hits → 0 |
| Parallel serialization for `bazel query --output=streamed_proto` | 100k targets: 2.24s → 0.89s (2.5x), byte-identical output |

## 1. `exclusive-if-local` now means "exclusive if local"

[bazelbuild/bazel#29758](https://github.com/bazelbuild/bazel/pull/29758) · merged November 4, 2026

**Problem.** The tag is supposed to serialize a test only when it runs locally. Under remote execution, Bazel treated it the same as `exclusive`. Meaning every tagged test waited for the one before it, even though each one ran on its own remote machine.

**Fix.** Bazel now asks the spawn strategies that can run a test, including the remote side of dynamic execution, whether they execute remotely. If they do, remote-eligible `exclusive-if-local` tests are scheduled as parallel tests. Tests also tagged `local`, `no-remote`, or `no-remote-exec` stay serialized, because they still run locally.

**Result.** 12 tests, each sleeping 5 seconds, against a remote execution worker. Median of 3 runs:

| Tests | Before | After |
|---|---|---|
| `exclusive-if-local` | 61.9s | 5.6s |
| `exclusive-if-local` + `no-remote-exec` (control) | 61.3s | 61.3s |

The control matters as much as the speedup. Tests that have to run locally are still serialized.

## 2. Build without the Bytes keeps trusting remote outputs

[bazelbuild/bazel#30852](https://github.com/bazelbuild/bazel/pull/30852) · merged August 27, 2026

**Problem.** Tools like IDE project generators build with `--remote_download_outputs=all`. The next normal build, with `toplevel` or `minimal`, has nothing to do. Even so, Bazel re-ran every intermediate action as a remote cache hit. The previous build's policy said "download everything", so the current build stopped trusting metadata for files it never needed locally.

**Fix.** `RemoteOutputChecker.shouldTrustMetadata` now checks only the top-level outputs the previous build actually tracked, not its whole download policy. The current build already knows its own policy.

**Result.** 2,000 intermediate genrules feeding one target, then a no-op rebuild after a `--remote_download_outputs=all` build of an unrelated target. I measured the merge commit against its parent. Median of 5 runs:

| | Before | After |
|---|---|---|
| Remote cache hits | 2,000 | 0 |
| Wall time | 1.73s | 0.30s |

The cache ran on localhost, so each hit cost almost nothing. Against a real remote cache, every one of those 2,000 hits is a network round trip.

## 3. Parallel `streamed_proto` query output

[bazelbuild/bazel#30959](https://github.com/bazelbuild/bazel/pull/30959) · merged October 2, 2026 · `--experimental_parallel_streamed_proto_output`

**Problem.** `bazel query --output=streamed_proto` serialized every target on a single thread. On large repos, that's the bottleneck for any tool that reads the query graph. An earlier attempt at this ran into concerns about ordering, memory, and cancellation.

**Fix.** Targets are split into 50-target chunks and serialized on a fixed thread pool. A single writer emits the chunks in their original order. The queue holds at most two pending chunks per core, which caps memory and slows input when output falls behind. An interrupt cancels any outstanding work. With `--proto:rule_classes`, it falls back to serial, because that output depends on the order in which rule classes are first seen.

**Result.** 100,000 genrules across 200 packages, warm server, 7 alternating runs:

| | Serial | Parallel |
|---|---|---|
| Median wall time | 2.24s | 0.89s |

The output was 138 MB and byte-identical to the serial output on every run. This is on 4 cores, and the speedup grows with more.

## How I measured

- 4 vCPU Intel Xeon @ 2.10GHz, 15 GiB RAM, Linux.
- Bazel built from source. Each before/after pair differs only by the change being measured.
- Remote execution and cache from Bazel's own remote worker on localhost.
- Scripts and raw results are in [`bench/`](bench/).

None of these changes is large. Each one fixes a specific thing that cost time on every build or test run, and each comes with tests that keep it fixed.
