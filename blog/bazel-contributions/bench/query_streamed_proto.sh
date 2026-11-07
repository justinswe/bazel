#!/usr/bin/env bash
# Benchmark: bazel query --output=streamed_proto, serial vs. parallel serialization.
#
# Generates PKGS packages with TARGETS genrules each, warms the server so all
# packages are loaded, then alternates serial and parallel runs of
#   bazel query //... --output=streamed_proto --output_file=<file>
# Every parallel output is compared byte for byte against the serial output.
source "$(dirname "$0")/common.sh"

PKGS="${PKGS:-200}"
TARGETS="${TARGETS:-500}"
RUNS="${RUNS:-7}"
BAZEL="${BAZEL:-$BAZEL_AFTER}"
OUT="${OUT:-$(dirname "$0")/results/query_streamed_proto.tsv}"
ORDER="${ORDER:-auto}"

ws="$BENCH_ROOT/query_ws"
if [[ ! -f "$ws/.generated_${PKGS}_${TARGETS}" ]]; then
  rm -rf "$ws" && mkdir -p "$ws"
  touch "$ws/MODULE.bazel"
  for p in $(seq 1 "$PKGS"); do
    mkdir -p "$ws/pkg$p"
    {
      for t in $(seq 1 "$TARGETS"); do
        deps=""
        [[ $t -gt 1 ]] && deps="\":t$((t - 1))\""
        [[ $t -gt 2 ]] && deps="$deps, \":t$((t - 2))\""
        echo "genrule(name = \"t$t\", srcs = [$deps], outs = [\"t$t.out\"], cmd = \"cat \$(SRCS) > \$@; echo pkg$p/t$t >> \$@\", tags = [\"team-$((t % 7))\", \"tier-$((t % 3))\"], visibility = [\"//visibility:public\"])"
      done
    } > "$ws/pkg$p/BUILD"
  done
  touch "$ws/.generated_${PKGS}_${TARGETS}"
fi

ob="$BENCH_ROOT/ob_query"
q() {
  (cd "$ws" && "$BAZEL" --output_base="$ob" query //... --output=streamed_proto \
      --order_output="$ORDER" --output_file="$1" --curses=no --color=no "${@:2}") \
      > /dev/null 2>"$BENCH_ROOT/query_stderr.log"
}

# Warm up: load every package and JIT both code paths.
q "$BENCH_ROOT/serial.pb"
q "$BENCH_ROOT/parallel.pb" --experimental_parallel_streamed_proto_output
q "$BENCH_ROOT/serial.pb"
q "$BENCH_ROOT/parallel.pb" --experimental_parallel_streamed_proto_output

printf "mode\trun\tseconds\tbytes\tidentical\n" > "$OUT"
for run in $(seq 1 "$RUNS"); do
  t0=$(now); q "$BENCH_ROOT/serial.pb"; t1=$(now)
  printf "serial\t%s\t%s\t%s\t-\n" "$run" "$(elapsed "$t0" "$t1")" "$(stat -c %s "$BENCH_ROOT/serial.pb")" | tee -a "$OUT"
  t0=$(now); q "$BENCH_ROOT/parallel.pb" --experimental_parallel_streamed_proto_output; t1=$(now)
  same=no; cmp -s "$BENCH_ROOT/serial.pb" "$BENCH_ROOT/parallel.pb" && same=yes
  printf "parallel\t%s\t%s\t%s\t%s\n" "$run" "$(elapsed "$t0" "$t1")" "$(stat -c %s "$BENCH_ROOT/parallel.pb")" "$same" | tee -a "$OUT"
done
"$BAZEL" --output_base="$ob" shutdown
