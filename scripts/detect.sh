#!/bin/bash
# Reproduce the mutant-detection result using ETNA's source-swap model: for each
# mutant, activate the marauder variant, rebuild, and run a property that should
# catch it. Prints (mutant/property -> status, counterexample).
#   ./scripts/detect.sh [duration_seconds]   (default 8)
#
# Requires the `etna` CLI (wraps marauder) and the patched toolchain. The
# workload's marauder.toml registers Swift as a custom language so `etna
# mutation set` can find the variants. All 10 STLC mutants are caught by
# SinglePreserve (preservation already breaks after a single bad step).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUR="${1:-8}"

reset() { etna mutation reset -p "$ROOT" >/dev/null 2>&1 || true; }
build() { "$ROOT/scripts/swift-toolchain.sh" build >/dev/null 2>&1; }
run()   { "$ROOT/scripts/run-stlc.sh" ptk "$1" "$DUR" 2>/dev/null | tail -1; }
field() { echo "$1" | sed -E "s/.*\"$2\":(\"?[^\",]*\"?).*/\1/"; }

trap reset EXIT

echo "# clean baselines (a mutant is only *genuinely* detected where clean passes)"
reset; build
for prop in SinglePreserve MultiPreserve; do
  echo "clean / $prop -> $(field "$(run "$prop")" status)"
done

echo "# mutants (each: reset -> set -> rebuild -> solve)"
for mut in shift_var_none shift_var_all shift_var_leq shift_abs_no_incr \
           subst_var_all subst_var_none subst_abs_no_shift subst_abs_no_incr \
           substTop_no_shift substTop_no_shift_back; do
  reset; etna mutation set "$mut" -p "$ROOT" >/dev/null 2>&1; build
  line=$(run "SinglePreserve")
  echo "$mut / SinglePreserve -> $(field "$line" status)   cex=$(field "$line" counterexample)"
done
