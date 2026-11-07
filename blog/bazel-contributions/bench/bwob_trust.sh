#!/usr/bin/env bash
# Benchmark: incremental Build without the Bytes after a broader download policy.
#
# Sequence, repeated RUNS times on one server:
#   1. bazel build //:app  --remote_download_outputs=toplevel   (once, setup)
#   2. bazel build //:tool --remote_download_outputs=all        (e.g. an IDE sync)
#   3. bazel build //:app  --remote_download_outputs=toplevel   (measured; nothing changed)
#
# Nothing changed between 1 and 3, so step 3 should evaluate zero actions.
# The measured numbers are the remote cache hits reported for step 3 and its
# wall time.
source "$(dirname "$0")/common.sh"

N="${N:-500}"
RUNS="${RUNS:-5}"
OUT="${OUT:-$(dirname "$0")/results/bwob_trust.tsv}"

ws="$BENCH_ROOT/bwob_ws"
rm -rf "$ws" && mkdir -p "$ws"
touch "$ws/MODULE.bazel"
{
  for i in $(seq 1 "$N"); do
    echo "genrule(name = \"lib$i\", outs = [\"out/lib$i.txt\"], cmd = \"echo lib$i > \$@\")"
  done
  printf 'genrule(name = "app", srcs = ['
  for i in $(seq 1 "$N"); do printf '":lib%s",' "$i"; done
  printf '], outs = ["out/app.txt"], cmd = "cat $(SRCS) > $@")\n'
  echo 'genrule(name = "tool", outs = ["out/tool.txt"], cmd = "echo tool > $@")'
} > "$ws/BUILD"

printf "binary\trun\tseconds\tremote_cache_hits\tprocesses\n" > "$OUT"

trap stop_worker EXIT
for pair in "before:$BAZEL_BEFORE" "after:$BAZEL_AFTER"; do
  label="${pair%%:*}"
  bazel="${pair#*:}"
  ob="$BENCH_ROOT/ob_bwob_$label"
  rm -rf "$ws/bazel-"*
  start_worker 8
  common=(--remote_executor="grpc://localhost:$WORKER_PORT" --curses=no --color=no)
  (cd "$ws" && "$bazel" --output_base="$ob" build //:app "${common[@]}" \
      --remote_download_outputs=toplevel) > "$BENCH_ROOT/bwob_${label}_setup.log" 2>&1
  for run in $(seq 1 "$RUNS"); do
    (cd "$ws" && "$bazel" --output_base="$ob" build //:tool "${common[@]}" \
        --remote_download_outputs=all) > "$BENCH_ROOT/bwob_${label}_tool_$run.log" 2>&1
    log="$BENCH_ROOT/bwob_${label}_app_$run.log"
    t0=$(now)
    (cd "$ws" && "$bazel" --output_base="$ob" build //:app "${common[@]}" \
        --remote_download_outputs=toplevel) > "$log" 2>&1
    t1=$(now)
    procs=$(grep -Eo '[0-9]+ processes?:.*' "$log" | tail -1 || true)
    hits=$(grep -Eo '[0-9]+ remote cache hit' <<<"$procs" | grep -Eo '^[0-9]+' || echo 0)
    printf "%s\t%s\t%s\t%s\t%s\n" "$label" "$run" "$(elapsed "$t0" "$t1")" "$hits" "${procs:-none}" | tee -a "$OUT"
  done
  "$bazel" --output_base="$ob" shutdown
  stop_worker
done
