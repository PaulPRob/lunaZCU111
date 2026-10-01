#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build.sh - run hw/scripts/build.tcl with the Vivado environment and licence
#
#   hw/scripts/build.sh [bd|synth|all] [jobs]      (default: all 3)
#
# Keep jobs <= 4 on a 16-24 GB machine, and do not run PetaLinux at the
# same time.  Log: hw/build/build.log, console copy: hw/build/build.stdout
# -----------------------------------------------------------------------------
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BDIR="$HERE/../build"
STAGE="${1:-all}"
JOBS="${2:-3}"

# shellcheck disable=SC1091
source "${XILINX_VIVADO_SETTINGS:-$HOME/Xilinx/Vivado/2023.2/settings64.sh}" >/dev/null
# shellcheck disable=SC1091
[[ -f "$HOME/Xilinx/license.sh" ]] && source "$HOME/Xilinx/license.sh"

mkdir -p "$BDIR"
cd "$BDIR"
vivado -mode batch -nojournal -log build.log -source "$HERE/build.tcl" \
    -tclargs "$STAGE" "$JOBS" 2>&1 | tee build.stdout
exit "${PIPESTATUS[0]}"
