#!/usr/bin/env bash
# Shared helpers for the benchmarks in this directory.
#
# Required environment:
#   BAZEL_AFTER   bazel binary built from a commit that contains the change
#   BAZEL_BEFORE  bazel binary built from the same commit with the change reverted
#   WORKER_JAR    path to the remote worker deploy jar (//src/tools/remote:worker_deploy.jar)
#   BENCH_ROOT    scratch directory for workspaces, output bases and worker state
#   WORKER_JAVA   (optional) java binary for the worker; it needs the JDK Bazel was built with
set -euo pipefail

: "${BENCH_ROOT:?set BENCH_ROOT}"
mkdir -p "$BENCH_ROOT"

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'; }

# median of numbers on stdin
median() {
  sort -n | awk '{ v[NR] = $1 } END {
    if (NR % 2) { printf "%.2f", v[(NR + 1) / 2] }
    else { printf "%.2f", (v[NR / 2] + v[NR / 2 + 1]) / 2 } }'
}

WORKER_PID=""
WORKER_PORT="${WORKER_PORT:-18080}"

start_worker() {
  local jobs="${1:-32}"
  local dir="$BENCH_ROOT/worker"
  rm -rf "$dir" && mkdir -p "$dir/work" "$dir/cas"
  # The worker only resolves an Xcode helper through runfiles, which is unused
  # on Linux, so an empty runfiles directory is enough.
  mkdir -p "$dir/runfiles"
  RUNFILES_DIR="$dir/runfiles" "${WORKER_JAVA:-java}" -jar "${WORKER_JAR:?set WORKER_JAR}" \
    --listen_port="$WORKER_PORT" \
    --work_path="$dir/work" \
    --cas_path="$dir/cas" \
    --jobs="$jobs" > "$dir/worker.log" 2>&1 &
  WORKER_PID=$!
  for _ in $(seq 1 60); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$WORKER_PORT") 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "worker failed to start" >&2
  cat "$dir/worker.log" >&2
  return 1
}

stop_worker() {
  if [[ -n "$WORKER_PID" ]]; then
    kill "$WORKER_PID" 2>/dev/null || true
    wait "$WORKER_PID" 2>/dev/null || true
    WORKER_PID=""
  fi
}

# Writes a minimal module with a self-contained test rule, so no external
# rulesets need to be fetched.
write_test_rule() {
  local ws="$1"
  mkdir -p "$ws"
  touch "$ws/MODULE.bazel"
  cat > "$ws/sleep_test.bzl" <<'BZL'
def _sleep_test_impl(ctx):
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        script,
        "#!/bin/sh\nsleep {}\necho {} done\n".format(ctx.attr.seconds, ctx.label.name),
        is_executable = True,
    )
    return [DefaultInfo(executable = script)]

sleep_test = rule(
    implementation = _sleep_test_impl,
    attrs = {"seconds": attr.int(default = 1)},
    test = True,
)
BZL
}
