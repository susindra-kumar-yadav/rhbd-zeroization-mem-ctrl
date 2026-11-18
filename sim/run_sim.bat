@echo off
setlocal enabledelayedexpansion

echo ==================================================================
echo    RHBD MEMORY CONTROLLER - ICARUS VERILOG SIMULATION SUITE (WIN)  
echo ==================================================================

set RTL_DIR=..\rtl
set TB_DIR=..\tb
set RTL_FILES=%RTL_DIR%\hamming_secded_enc.v %RTL_DIR%\hamming_secded_dec.v %RTL_DIR%\tmr_voter.v %RTL_DIR%\ecc_ram.v %RTL_DIR%\scrubber.v %RTL_DIR%\zeroize_engine.v %RTL_DIR%\mem_ctrl_fsm.v %RTL_DIR%\rhbd_mem_top.v

set FAILED=0

echo [1/5] Compiling and running tb_ecc...
iverilog -g2001 -o tb_ecc.vvp %TB_DIR%\tb_ecc.v %RTL_DIR%\hamming_secded_enc.v %RTL_DIR%\hamming_secded_dec.v
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_ecc.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo [2/5] Compiling and running tb_ram_faults...
iverilog -g2001 -o tb_ram_faults.vvp %TB_DIR%\tb_ram_faults.v %RTL_FILES%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_ram_faults.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo [3/5] Compiling and running tb_fsm_tmr...
iverilog -g2001 -o tb_fsm_tmr.vvp %TB_DIR%\tb_fsm_tmr.v %RTL_DIR%\mem_ctrl_fsm.v %RTL_DIR%\tmr_voter.v %RTL_DIR%\hamming_secded_enc.v %RTL_DIR%\hamming_secded_dec.v %RTL_DIR%\ecc_ram.v
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_fsm_tmr.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo [4/5] Compiling and running tb_zeroize...
iverilog -g2001 -o tb_zeroize.vvp %TB_DIR%\tb_zeroize.v %RTL_FILES%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_zeroize.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo [5/5] Compiling and running tb_top...
iverilog -g2001 -o tb_top.vvp %TB_DIR%\tb_top.v %RTL_FILES%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_top.vvp
if errorlevel 1 ( set /a FAILED+=1 )

:end
echo ==================================================================
if %FAILED% equ 0 (
    echo    ALL TESTBENCHES COMPLETED SUCCESSFULLY! (0 FAILURES)
) else (
    echo    SIMULATION FINISHED WITH %FAILED% FAILURE(S)
)
echo ==================================================================
pause

