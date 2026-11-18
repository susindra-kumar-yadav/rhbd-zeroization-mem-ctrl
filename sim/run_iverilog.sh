#!/bin/bash
# =============================================================================
# File:        run_iverilog.sh
# Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
# Description: Automated simulation script using Icarus Verilog (iverilog & vvp)
# =============================================================================

set -e

# Project directories (relative to sim/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RTL_DIR="$PROJECT_DIR/rtl"
TB_DIR="$PROJECT_DIR/tb"

echo "=================================================================="
echo "   RHBD MEMORY CONTROLLER - ICARUS VERILOG SIMULATION SUITE       "
echo "=================================================================="
echo "Project Directory: $PROJECT_DIR"
echo "RTL Directory:     $RTL_DIR"
echo "TB Directory:      $TB_DIR"
echo ""

RTL_FILES="$RTL_DIR/hamming_secded_enc.v \
           $RTL_DIR/hamming_secded_dec.v \
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
    iverilog -g2001 -o "${TESTNAME}.vvp" $TBSOURCE $EXTRA_RTL
    if vvp "${TESTNAME}.vvp"; then
        echo ">>> RESULT: $TESTNAME PASSED"
    else
        echo ">>> RESULT: $TESTNAME FAILED"
        FAILED=$((FAILED + 1))
    fi
    echo ""
}

# 1. tb_ecc (SECDED Encoder & Decoder)
run_test "tb_ecc" "$TB_DIR/tb_ecc.v" "$RTL_DIR/hamming_secded_enc.v $RTL_DIR/hamming_secded_dec.v"

# 2. tb_ram_faults (RAM with fault injection & write-back)
run_test "tb_ram_faults" "$TB_DIR/tb_ram_faults.v" "$RTL_FILES"

# 3. tb_fsm_tmr (TMR-protected FSM self-healing)
run_test "tb_fsm_tmr" "$TB_DIR/tb_fsm_tmr.v" "$RTL_DIR/mem_ctrl_fsm.v $RTL_DIR/tmr_voter.v $RTL_DIR/hamming_secded_enc.v $RTL_DIR/hamming_secded_dec.v $RTL_DIR/ecc_ram.v"

# 4. tb_zeroize (Multi-pass anti-tamper zeroization engine)
run_test "tb_zeroize" "$TB_DIR/tb_zeroize.v" "$RTL_FILES"

# 5. tb_top (Full End-to-End System Integration)
run_test "tb_top" "$TB_DIR/tb_top.v" "$RTL_FILES"

echo "=================================================================="
if [ $FAILED -eq 0 ]; then
    echo "   ALL TESTBENCHES COMPLETED SUCCESSFULLY! (0 FAILURES)           "
else
    echo "   SIMULATION COMPLETED WITH $FAILED FAILURE(S)                   "
    exit 1
fi
echo "=================================================================="

