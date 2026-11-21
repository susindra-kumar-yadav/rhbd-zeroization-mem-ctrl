@echo off
setlocal enabledelayedexpansion

echo ==================================================================
echo    RHBD MEMORY CONTROLLER - VIVADO 2026.2 XSIM SUITE (WIN)       
echo ==================================================================

set RTL_DIR=..\rtl
set TB_DIR=..\tb
set TOOLS_DIR=..\tools

REM Vivado binary location
set XVLOG_BIN=E:\vivado\2026.2\Vivado\bin\xvlog.bat
set XELAB_BIN=E:\vivado\2026.2\Vivado\bin\xelab.bat
set XSIM_BIN=E:\vivado\2026.2\Vivado\bin\xsim.bat

if not exist "%XVLOG_BIN%" (
    echo [!] Vivado 2026.2 not detected at E:\vivado\2026.2. Checking PATH...
    set XVLOG_BIN=xvlog
    set XELAB_BIN=xelab
    set XSIM_BIN=xsim
)

set RTL_ALL=%RTL_DIR%\ecc_enc.v %RTL_DIR%\ecc_dec.v %RTL_DIR%\state_ecc_enc.v %RTL_DIR%\state_ecc_dec.v %RTL_DIR%\tmr_voter.v %RTL_DIR%\ecc_ram.v %RTL_DIR%\scrubber.v %RTL_DIR%\zeroize_engine.v %RTL_DIR%\mem_ctrl_fsm.v %RTL_DIR%\rhbd_mem_top.v

set FAILED=0

REM Step 0: Generate ECC
set PY_CMD=
if exist "%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe" set PY_CMD="%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe"
if "%PY_CMD%"=="" where py >nul 2>&1 && set PY_CMD=py
if "%PY_CMD%"=="" where python >nul 2>&1 && set PY_CMD=python

if not "%PY_CMD%"=="" (
    echo [0/7] Running Python ECC Code Generator...
    %PY_CMD% %TOOLS_DIR%\gen_ecc_code.py --target all --out_dir %RTL_DIR%
)

echo.
echo [1/7] Compiling and simulating tb_ecc_exhaustive in Vivado xsim...
call %XVLOG_BIN% -i %RTL_DIR% %TB_DIR%\tb_ecc_exhaustive.v %RTL_DIR%\ecc_enc.v %RTL_DIR%\ecc_dec.v
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XELAB_BIN% -debug typical tb_ecc_exhaustive -s snap_v_exh
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XSIM_BIN% snap_v_exh -R
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [2/7] Compiling and simulating tb_ecc in Vivado xsim...
call %XVLOG_BIN% -i %RTL_DIR% %TB_DIR%\tb_ecc.v %RTL_DIR%\ecc_enc.v %RTL_DIR%\ecc_dec.v
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XELAB_BIN% -debug typical tb_ecc -s snap_v_ecc
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XSIM_BIN% snap_v_ecc -R
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [3/7] Compiling and simulating tb_ram_faults in Vivado xsim...
call %XVLOG_BIN% -i %RTL_DIR% %TB_DIR%\tb_ram_faults.v %RTL_ALL%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XELAB_BIN% -debug typical tb_ram_faults -s snap_v_ram
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XSIM_BIN% snap_v_ram -R
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [4/7] Compiling and simulating tb_fsm_tmr in Vivado xsim...
call %XVLOG_BIN% -i %RTL_DIR% %TB_DIR%\tb_fsm_tmr.v %RTL_ALL%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XELAB_BIN% -debug typical tb_fsm_tmr -s snap_v_fsm
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XSIM_BIN% snap_v_fsm -R
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [5/7] Compiling and simulating tb_zeroize in Vivado xsim...
call %XVLOG_BIN% -i %RTL_DIR% %TB_DIR%\tb_zeroize.v %RTL_ALL%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XELAB_BIN% -debug typical tb_zeroize -s snap_v_zero
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XSIM_BIN% snap_v_zero -R
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [6/7] Compiling and simulating tb_top in Vivado xsim...
call %XVLOG_BIN% -i %RTL_DIR% %TB_DIR%\tb_top.v %RTL_ALL%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XELAB_BIN% -debug typical tb_top -s snap_v_top
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XSIM_BIN% snap_v_top -R
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [7/7] Compiling and simulating tb_scrub_experiment in Vivado xsim...
call %XVLOG_BIN% -i %RTL_DIR% %TB_DIR%\tb_scrub_experiment.v %RTL_ALL%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XELAB_BIN% -debug typical tb_scrub_experiment -s snap_v_scrub
if errorlevel 1 ( set /a FAILED+=1 & goto end )
call %XSIM_BIN% snap_v_scrub -R
if errorlevel 1 ( set /a FAILED+=1 )

:end
echo.
echo ==================================================================
if %FAILED% equ 0 (
    echo    ALL VIVADO 2026.2 XSIM TESTS COMPLETED WITH 0 FAILURES!
) else (
    echo    VIVADO SIMULATION FINISHED WITH %FAILED% FAILURES
)
echo ==================================================================
if not "%1"=="nopause" pause
