#!/bin/bash
# Full measurement ladder for tomorrow. Run: sudo-ish (pkexec for A only).
# Order chosen so the quiet configs come first and the module swap is last,
# leaving the machine in its normal state (D) at the end.
set -uo pipefail
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="python3 $TOOLS_DIR/speaker-suite.py"
CFG="$TOOLS_DIR/speaker-config.sh"

echo "=== volume to 60% (moderate, panel-safe first pass) ==="
wpctl set-volume 75 0.6

for CFGNAME in D C B; do
  echo; echo "########## CONFIG $CFGNAME ##########"
  bash "$CFG" "$CFGNAME"
  sleep 1
  $SUITE measure "$CFGNAME"
done

echo; echo "########## CONFIG A (stock module; audio blinks ~15 s) ##########"
pkexec bash "$CFG" A
sleep 1
$SUITE measure A

echo; echo "=== restoring config D (all pairs on) ==="
bash "$CFG" D

echo; echo "=== analysis per config ==="
for R in D C B A; do
  echo "--- $R:"
  $SUITE analyze "$R"
done
echo "DONE. Results: /tmp/speaker-suite/*-table.json"
