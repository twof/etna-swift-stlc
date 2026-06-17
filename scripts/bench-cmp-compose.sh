#!/bin/bash
# Benchmark: does composing the cmp boundary-distance channel onto pathTrie help
# find the hard de Bruijn mutant shift_var_leq? The mutant must already be active
# (etna mutation set shift_var_leq) and the workload built. Arms:
#   A  ptk-pathtrie            / default scheduler   (edge-only baseline)
#   B  ptk-pathtrie-boundary   / default scheduler   (+ cmp acceptance)
#   C  ptk-pathtrie-boundary   / boundary-culled     (+ cmp acceptance & culling)
# Reports per-trial wall-clock to counterexample (status=failed) or TIMEOUT
# (status=passed within budget). Usage: bench-cmp-compose.sh <n> <seconds>
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N="${1:-20}"
DUR="${2:-30}"
OUT="/tmp/stlc-cmp-compose-bench.tsv"
: > "$OUT"
echo -e "arm\ttrial\tstatus\ttests\ttime_ns" | tee -a "$OUT"

run_arm() {
  local arm="$1" strat="$2" sched="$3"
  for i in $(seq 1 "$N"); do
    line=$(PTK_SCHEDULER="$sched" "$ROOT/scripts/run-stlc.sh" "$strat" SinglePreserve "$DUR" 2>/dev/null | tail -1)
    status=$(echo "$line" | sed -E 's/.*"status":"([^"]*)".*/\1/')
    tests=$(echo "$line"  | sed -E 's/.*"tests":([0-9]*).*/\1/')
    tns=$(echo "$line"    | sed -E 's/.*"time":"([0-9]*)ns".*/\1/')
    echo -e "${arm}\t${i}\t${status}\t${tests}\t${tns}" | tee -a "$OUT"
  done
}

run_arm A ptk-pathtrie          ""               # default scheduler (unset)
run_arm B ptk-pathtrie-boundary ""
run_arm C ptk-pathtrie-boundary boundary-culled
echo "@@@ BENCH DONE @@@" | tee -a "$OUT"
