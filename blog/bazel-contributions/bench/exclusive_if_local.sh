#!/usr/bin/env bash
# Benchmark: tests tagged "exclusive-if-local" under remote execution.
#
# Builds N sleep tests tagged exclusive-if-local and runs them against a local
# remote-execution worker. Each test sleeps S seconds. If the tag is honored,
# the tests run remotely in parallel (wall time close to S). If it is treated
# like "exclusive", they are serialized (wall time close to N * S).
#
# A control set tagged "exclusive-if-local" + "no-remote-exec" must stay
# serialized with both binaries, because those tests can only run locally.
source "$(dirname "$0")/common.sh"

N="${N:-12}"
S="${S:-5}"
RUNS="${RUNS:-3}"
OUT="${OUT:-$(dirname "$0")/results/exclusive_if_local.tsv}"

ws="$BENCH_ROOT/exclusive_if_local_ws"
rm -rf "$ws"
write_test_rule "$ws"
{
  echo 'load(":sleep_test.bzl", "sleep_test")'
  for i in $(seq 1 "$N"); do
    echo "sleep_test(name = \"remote_ok_$i\", seconds = $S, tags = [\"exclusive-if-local\"])"
    echo "sleep_test(name = \"local_only_$i\", seconds = $S, tags = [\"exclusive-if-local\", \"no-remote-exec\"])"
  done
  echo 'test_suite(name = "remote_ok", tags = ["exclusive-if-local", "-no-remote-exec"])'
  echo 'test_suite(name = "local_only", tags = ["no-remote-exec"])'
} > "$ws/BUILD"

printf "binary\tsuite\trun\tseconds\tprocesses\n" > "$OUT"

run_suite() {
  local label="$1" bazel="$2" suite="$3" run="$4"
  local ob="$BENCH_ROOT/ob_eil_$label"
  local log="$BENCH_ROOT/eil_${label}_${suite}_${run}.log"
  local t0 t1
  t0=$(now)
  (cd "$ws" && "$bazel" --output_base="$ob" test "//:$suite" \
      --remote_executor="grpc://localhost:$WORKER_PORT" \
      --nocache_test_results --noremote_accept_cached \
      --jobs=64 --test_output=errors --curses=no --color=no) > "$log" 2>&1
  t1=$(now)
  local procs
  procs=$(grep -Eo '[0-9]+ processes?:.*' "$log" | tail -1)
  printf "%s\t%s\t%s\t%s\t%s\n" "$label" "$suite" "$run" "$(elapsed "$t0" "$t1")" "$procs" | tee -a "$OUT"
}

trap stop_worker EXIT
for pair in "before:$BAZEL_BEFORE" "after:$BAZEL_AFTER"; do
  label="${pair%%:*}"
  bazel="${pair#*:}"
  start_worker 64
  # Warm up: start the server and finish analysis outside the timed runs.
  (cd "$ws" && "$bazel" --output_base="$BENCH_ROOT/ob_eil_$label" build //... \
      --remote_executor="grpc://localhost:$WORKER_PORT" --curses=no) \
      > "$BENCH_ROOT/eil_${label}_warmup.log" 2>&1
  for run in $(seq 1 "$RUNS"); do
    run_suite "$label" "$bazel" remote_ok "$run"
  done
  run_suite "$label" "$bazel" local_only 1
  "$bazel" --output_base="$BENCH_ROOT/ob_eil_$label" shutdown
  stop_worker
done
