@echo off
setlocal enabledelayedexpansion

echo ==================================================================
echo    RHBD MEMORY CONTROLLER - ICARUS VERILOG SIMULATION SUITE (WIN)  
echo ==================================================================

set RTL_DIR=..\rtl
set TB_DIR=..\tb
set TOOLS_DIR=..\tools

set RTL_FILES=%RTL_DIR%\ecc_enc.v %RTL_DIR%\ecc_dec.v %RTL_DIR%\state_ecc_enc.v %RTL_DIR%\state_ecc_dec.v %RTL_DIR%\tmr_voter.v %RTL_DIR%\ecc_ram.v %RTL_DIR%\scrubber.v %RTL_DIR%\zeroize_engine.v %RTL_DIR%\mem_ctrl_fsm.v %RTL_DIR%\rhbd_mem_top.v

set FAILED=0

REM Locate Python executable
set PY_CMD=
if exist "%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe" set PY_CMD="%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe"
if "%PY_CMD%"=="" if exist "%LOCALAPPDATA%\Python\bin\python3.exe" set PY_CMD="%LOCALAPPDATA%\Python\bin\python3.exe"
if "%PY_CMD%"=="" where py >nul 2>&1 && set PY_CMD=py
if "%PY_CMD%"=="" where python3 >nul 2>&1 && set PY_CMD=python3
if "%PY_CMD%"=="" where python >nul 2>&1 && set PY_CMD=python

if not "%PY_CMD%"=="" (
    echo [0/7] Running Python ECC Code Generator: Memory DEC-TED and State ECC
    %PY_CMD% %TOOLS_DIR%\gen_ecc_code.py --target all --out_dir %RTL_DIR%
) else (
    echo [!] Python not detected. Using existing generated RTL files.
)

echo.
echo [1/7] Compiling and running tb_ecc_exhaustive
iverilog -g2001 -I %RTL_DIR% -o tb_ecc_exhaustive.vvp %TB_DIR%\tb_ecc_exhaustive.v %RTL_DIR%\ecc_enc.v %RTL_DIR%\ecc_dec.v
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_ecc_exhaustive.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [2/7] Compiling and running tb_ecc
iverilog -g2001 -I %RTL_DIR% -o tb_ecc.vvp %TB_DIR%\tb_ecc.v %RTL_DIR%\ecc_enc.v %RTL_DIR%\ecc_dec.v
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_ecc.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [3/7] Compiling and running tb_ram_faults
iverilog -g2001 -I %RTL_DIR% -o tb_ram_faults.vvp %TB_DIR%\tb_ram_faults.v %RTL_FILES%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_ram_faults.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [4/7] Compiling and running tb_fsm_tmr
iverilog -g2001 -I %RTL_DIR% -o tb_fsm_tmr.vvp %TB_DIR%\tb_fsm_tmr.v %RTL_FILES%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_fsm_tmr.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [5/7] Compiling and running tb_zeroize
iverilog -g2001 -I %RTL_DIR% -o tb_zeroize.vvp %TB_DIR%\tb_zeroize.v %RTL_FILES%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_zeroize.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [6/7] Compiling and running tb_top
iverilog -g2001 -I %RTL_DIR% -o tb_top.vvp %TB_DIR%\tb_top.v %RTL_FILES%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_top.vvp
if errorlevel 1 ( set /a FAILED+=1 )

echo.
echo [7/7] Compiling and running tb_scrub_experiment
iverilog -g2001 -I %RTL_DIR% -o tb_scrub_experiment.vvp %TB_DIR%\tb_scrub_experiment.v %RTL_FILES%
if errorlevel 1 ( set /a FAILED+=1 & goto end )
vvp tb_scrub_experiment.vvp
if errorlevel 1 ( set /a FAILED+=1 )

:end
echo.
echo ==================================================================
if %FAILED% equ 0 (
    echo    ALL TESTBENCHES COMPLETED SUCCESSFULLY: 0 FAILURES
) else (
    echo    SIMULATION FINISHED WITH %FAILED% FAILURE:S
)
echo ==================================================================
if not "%1"=="nopause" pause
