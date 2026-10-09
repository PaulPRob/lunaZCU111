#!/usr/bin/env bash
# Run the VHDL unit simulations (Vivado xsim) and compare against the golden
# models.  Usage:  hw/sim/run_sim.sh [trig|cap|all|spec|full]   (all = trig+cap)
#   spec : spectrometer with the CSIRO PFB/DFB cores (needs refernces/PFB,
#          runs Vivado in project mode, several hours: the PFB model is slow);  full = all + spec
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HDL="$HERE/../hdl"
BUILD="$HERE/build"
WHAT="${1:-all}"
mkdir -p "$BUILD"
cd "$BUILD"
# shellcheck disable=SC1091
source "${XILINX_VIVADO_SETTINGS:-$HOME/Xilinx/Vivado/2023.2/settings64.sh}" >/dev/null
# shellcheck disable=SC1091
[[ -f "$HOME/Xilinx/license.sh" ]] && source "$HOME/Xilinx/license.sh"

SRCS="luna_pkg adc_gearbox chan_detect trig_logic capture_mem capture_ctrl trig_regs_axil trigger_capture_top"
# compile quietly, but show the log if anything fails
run() { "$@" > run.log 2>&1 || { grep -E "ERROR|error" run.log || cat run.log; exit 1; }; }

for f in $SRCS; do
  run xvhdl --relax "$HDL/$f.vhd"
done

fail=0

if [[ "$WHAT" == trig || "$WHAT" == all || "$WHAT" == full ]]; then
  run xvhdl --relax "$HERE/tb_trig.vhd"
  run xelab -relax -debug off tb_trig -s tb_trig
  # mode N W mask veto   (veto = channel, -1 = none; used in anti-coincidence only)
  CFGS=(
    "0 1 64 255 -1" "0 2 64 255 -1" "0 3 64 255 -1" "0 4 64 255 -1" "0 5 64 255 -1"
    "0 6 64 255 -1" "0 7 64 255 -1" "0 8 64 255 -1" "0 2 1 255 -1" "0 2 16 255 -1"
    "0 3 17 255 -1" "0 2 200 255 -1" "0 2 255 255 -1" "0 2 64 165 -1" "0 4 31 127 -1"
    "0 2 64 255 3"
    "1 1 64 255 -1" "1 1 1 255 -1" "1 1 16 255 -1" "1 1 17 255 -1" "1 1 100 255 -1"
    "1 1 255 255 -1" "1 1 64 90 -1"
    "1 1 64 255 0" "1 1 64 255 7" "1 1 17 255 4" "1 1 1 255 2" "1 1 255 255 5"
    "1 1 64 90 0" "1 1 64 90 3" "1 1 33 254 0"
  )
  seed=1
  for cfg in "${CFGS[@]}"; do
    # shellcheck disable=SC2086
    python3 "$HERE/trig_model.py" gen $seed $cfg trig_stim.txt trig_expect.txt
    xsim tb_trig -R >/dev/null
    printf "trig  mode/N/W/mask/veto = %-17s " "$cfg"
    python3 "$HERE/trig_model.py" cmp trig_expect.txt trig_out.txt || fail=1
    seed=$((seed + 1))
  done
fi

if [[ "$WHAT" == cap || "$WHAT" == all || "$WHAT" == full ]]; then
  run xvhdl --relax "$HERE/tb_capture.vhd"
  run xelab -relax -debug off tb_capture -s tb_capture
  xsim tb_capture -R | grep -E "^(Note|Error|Failure)|TB" || true
  python3 "$HERE/check_capture.py" cap_stream.txt cap_log.txt || fail=1
fi

if [[ "$WHAT" == spec || "$WHAT" == full ]]; then
  if [[ -d "$HERE/../../refernces/PFB" || -n "${LUNA_PFB_IP:-}" ]]; then
    # two Vivado/xsim runs in parallel: data (full chain) and restart (no PFB)
    for t in data restart; do
      SPEC_TEST=$t vivado -mode batch -nojournal -log "sim_spec_$t.log" \
        -source "$HERE/sim_spec.tcl" > "sim_spec_$t.stdout" 2>&1 &
    done
    wait || true
    for t in data restart; do
      echo "== spectrometer $t test"
      grep -E "TB |Failure|ERROR" "sim_spec_$t.stdout" || true
      python3 "$HERE/check_spec.py" --mode "$t" \
        "spec_sim_$t/spec_sim.sim/sim_1/behav/xsim/spec_writes.txt" || fail=1
    done
  else
    echo "spec: skipped (refernces/PFB with the CSIRO cores not present)"
  fi
fi

if [[ $fail -ne 0 ]]; then
  echo "SIMULATION FAILURES"
  exit 1
fi
echo "ALL SIMULATIONS PASSED"
