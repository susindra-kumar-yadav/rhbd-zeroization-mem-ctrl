#!/bin/bash
# =============================================================================
# File:        run_iverilog.sh
# Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
# Description: Automated simulation script using Icarus Verilog (iverilog & vvp)
#              Runs the Python ECC code generator first, then runs all testbenches.
# =============================================================================

set -e

# Project directories (relative to sim/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RTL_DIR="$PROJECT_DIR/rtl"
TB_DIR="$PROJECT_DIR/tb"
TOOLS_DIR="$PROJECT_DIR/tools"

echo "=================================================================="
echo "   RHBD MEMORY CONTROLLER - ICARUS VERILOG SIMULATION SUITE       "
echo "=================================================================="
echo "Project Directory: $PROJECT_DIR"
echo "RTL Directory:     $RTL_DIR"
echo "TB Directory:      $TB_DIR"
echo "Tools Directory:   $TOOLS_DIR"
echo ""

# -----------------------------------------------------------------------------
# Step 0: Run Python ECC Generator to build rtl/ecc_params.vh, ecc_enc.v, ecc_dec.v,
#         state_ecc_params.vh, state_ecc_enc.v, state_ecc_dec.v
# -----------------------------------------------------------------------------
echo "------------------------------------------------------------------"
echo " Step 0: Running Python ECC Code Generator (Memory DEC-TED & State ECC)"
echo "------------------------------------------------------------------"
if command -v python3 &>/dev/null; then
    python3 "$TOOLS_DIR/gen_ecc_code.py" --target all --out_dir "$RTL_DIR"
elif command -v python &>/dev/null; then
    python "$TOOLS_DIR/gen_ecc_code.py" --target all --out_dir "$RTL_DIR"
elif command -v py &>/dev/null; then
    py "$TOOLS_DIR/gen_ecc_code.py" --target all --out_dir "$RTL_DIR"
else
    echo "[!] Warning: Python executable not found in PATH; using existing generated RTL."
fi
echo ""

RTL_FILES="$RTL_DIR/ecc_enc.v \
           $RTL_DIR/ecc_dec.v \
           $RTL_DIR/state_ecc_enc.v \
           $RTL_DIR/state_ecc_dec.v \
           $RTL_DIR/tmr_voter.v \
           $RTL_DIR/ecc_ram.v \
           $RTL_DIR/scrubber.v \
           $RTL_DIR/zeroize_engine.v \
           $RTL_DIR/mem_ctrl_fsm.v \
           $RTL_DIR/rhbd_mem_top.v"

FAILED=0

run_test() {
    TESTNAME=$1
    TBSOURCE=$2
    EXTRA_RTL=$3

    echo "------------------------------------------------------------------"
    echo " Running Testbench: $TESTNAME"
    echo "------------------------------------------------------------------"
    iverilog -g2001 -I "$RTL_DIR" -o "${TESTNAME}.vvp" $TBSOURCE $EXTRA_RTL
    if vvp "${TESTNAME}.vvp"; then
        echo ">>> RESULT: $TESTNAME PASSED"
    else
        echo ">>> RESULT: $TESTNAME FAILED"
        FAILED=$((FAILED + 1))
    fi
    echo ""
}

# 1. tb_ecc_exhaustive (Exhaustive 44,032 check suite + weight-3 analysis)
run_test "tb_ecc_exhaustive" "$TB_DIR/tb_ecc_exhaustive.v" "$RTL_DIR/ecc_enc.v $RTL_DIR/ecc_dec.v"

# 2. tb_ecc (DEC-TED Encoder & Decoder Validation)
run_test "tb_ecc" "$TB_DIR/tb_ecc.v" "$RTL_DIR/ecc_enc.v $RTL_DIR/ecc_dec.v"

# 3. tb_ram_faults (RAM with fault injection & write-back)
run_test "tb_ram_faults" "$TB_DIR/tb_ram_faults.v" "$RTL_FILES"

# 4. tb_fsm_tmr (TMR-protected FSM self-healing with per-copy state ECC)
run_test "tb_fsm_tmr" "$TB_DIR/tb_fsm_tmr.v" "$RTL_FILES"

# 5. tb_zeroize (Multi-pass anti-tamper zeroization engine)
run_test "tb_zeroize" "$TB_DIR/tb_zeroize.v" "$RTL_FILES"

# 6. tb_top (Full End-to-End System Integration)
run_test "tb_top" "$TB_DIR/tb_top.v" "$RTL_FILES"

# 7. tb_scrub_experiment (Scrub-Interval Reliability Experiment)
run_test "tb_scrub_experiment" "$TB_DIR/tb_scrub_experiment.v" "$RTL_FILES"

echo "=================================================================="
if [ $FAILED -eq 0 ]; then
    echo "   ALL TESTBENCHES COMPLETED SUCCESSFULLY! (0 FAILURES)           "
else
    echo "   SIMULATION COMPLETED WITH $FAILED FAILURE(S)                   "
    exit 1
fi
echo "=================================================================="
