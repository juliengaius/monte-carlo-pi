#!/usr/bin/env bash
# Runs every check for the Monte Carlo accelerator.
# Usage: ./sim/run_tests.sh          (from the repo root)
#        LONG=1 ./sim/run_tests.sh   also runs a 100,000-sample continuous comparison (~3 min)
# Needs: iverilog, a C compiler, python3. Exits non-zero on any failure.

set -u
cd "$(dirname "$0")/.."
mkdir -p build
failed=0

RTL="rtl/control_fsm.v rtl/point_FSM.v rtl/lane.v rtl/lfsr32.v rtl/unitizer_uq16.v \
     rtl/hit_kernel_uq16_comb.v rtl/mc_counters.v rtl/pi_divider.v rtl/sprite_drawer.v \
     sim/object_mem_sim.v"

# Plain Verilog-2005: hit_kernel uses a port named `inside`, a SystemVerilog keyword.
IV="iverilog -g2005"

unit() {  # unit <name> <files...>
  local name="$1"; shift
  echo "=== unit: $name"
  if $IV -o "build/$name.vvp" "$@" && vvp -n "build/$name.vvp" | grep -E "PASS|FAIL"; then
    vvp -n "build/$name.vvp" | grep -q "^PASS" || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
}

unit lfsr32     rtl/lfsr32.v               tb/tb_lfsr32.v
unit hit_kernel rtl/hit_kernel_uq16_comb.v tb/tb_hit_kernel.v
unit pi_divider rtl/pi_divider.v           tb/tb_pi_divider.v

echo "=== C reference model"
cc -O2 -Wall -Wextra -o build/mc_model model/mc_model.c -lm || failed=$((failed + 1))

compare() {  # compare <label> <iverilog -P overrides...>
  local label="$1"; shift
  echo "=== RTL vs C model: $label"
  $IV "$@" -o build/sys.vvp $RTL tb/tb_system.v || { failed=$((failed + 1)); return; }
  vvp -n build/sys.vvp | grep "^rtl:"
  ./build/mc_model dump build/schedule.txt build/model_samples.csv
  python3 sim/compare.py build/rtl_samples.csv build/model_samples.csv || failed=$((failed + 1))
}

# 200 SPACE presses of 10 points each, pseudo-random gaps: how the board is used
compare "200 key presses x 10 points, random gaps" \
  -P tb_system.BATCH=10 -P tb_system.NUM_PRESS=200 -P tb_system.MAX_GAP=1000

if [ "${LONG:-0}" = "1" ]; then
  compare "100,000 points in one continuous batch" \
    -P tb_system.BATCH=100000 -P tb_system.NUM_PRESS=1 -P tb_system.MAX_GAP=50
fi

echo
if [ "$failed" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$failed CHECK GROUP(S) FAILED"; fi
[ "$failed" -eq 0 ]
