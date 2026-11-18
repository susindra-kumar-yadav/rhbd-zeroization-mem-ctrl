## =============================================================================
## File:        board.xdc
## Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
## Target:      Xilinx Artix-7 FPGA (Vivado 2026.2)
## Description: Master Constraints and Pin Assignment Template.
##
## !!! IMPORTANT NOTE FOR STUDENTS / LAB INSTRUCTORS !!!
## Target FPGA board is not finalized yet. The pin numbers below are PLACEHOLDERS
## (using standard Artix-7 package pin names like W5, V17, U16 etc. commonly found
## on Basys 3 / Nexys A7 boards).
## YOU MUST EDIT PIN NUMBERS FOR YOUR SPECIFIC BOARD AND PACKAGE BEFORE BITSTREAM!
## =============================================================================

## -----------------------------------------------------------------------------
## 1. Primary Clock Constraint (100 MHz System Clock = 10.000 ns period)
## -----------------------------------------------------------------------------
# EDIT PIN NUMBER FOR YOUR BOARD (e.g. W5 for Basys 3, E3 for Nexys A7)
set_property PACKAGE_PIN W5 [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk_100mhz]

## -----------------------------------------------------------------------------
## 2. Push Buttons (Active-High, Debounced in RTL)
## -----------------------------------------------------------------------------
# EDIT PIN NUMBERS FOR YOUR BOARD
set_property PACKAGE_PIN U18 [get_ports btn_rst]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst]

set_property PACKAGE_PIN T18 [get_ports btn_wr]
set_property IOSTANDARD LVCMOS33 [get_ports btn_wr]

set_property PACKAGE_PIN W19 [get_ports btn_rd]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rd]

set_property PACKAGE_PIN T17 [get_ports btn_inj_1bit]
set_property IOSTANDARD LVCMOS33 [get_ports btn_inj_1bit]

set_property PACKAGE_PIN U17 [get_ports btn_inj_2bit]
set_property IOSTANDARD LVCMOS33 [get_ports btn_inj_2bit]

set_property PACKAGE_PIN V19 [get_ports btn_inj_fsm]
set_property IOSTANDARD LVCMOS33 [get_ports btn_inj_fsm]

set_property PACKAGE_PIN P18 [get_ports btn_tamper]
set_property IOSTANDARD LVCMOS33 [get_ports btn_tamper]

## -----------------------------------------------------------------------------
## 3. Slide Switches: Address [7:0] and Write Data [7:0]
## -----------------------------------------------------------------------------
# sw_addr [7:0] - EDIT PIN NUMBERS FOR YOUR BOARD
set_property PACKAGE_PIN V17 [get_ports {sw_addr[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_addr[0]}]
set_property PACKAGE_PIN V16 [get_ports {sw_addr[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_addr[1]}]
set_property PACKAGE_PIN W16 [get_ports {sw_addr[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_addr[2]}]
set_property PACKAGE_PIN W17 [get_ports {sw_addr[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_addr[3]}]
set_property PACKAGE_PIN W15 [get_ports {sw_addr[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_addr[4]}]
set_property PACKAGE_PIN V15 [get_ports {sw_addr[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_addr[5]}]
set_property PACKAGE_PIN W14 [get_ports {sw_addr[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_addr[6]}]
set_property PACKAGE_PIN W13 [get_ports {sw_addr[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_addr[7]}]

# sw_data [7:0] - EDIT PIN NUMBERS FOR YOUR BOARD
set_property PACKAGE_PIN V2  [get_ports {sw_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_data[0]}]
set_property PACKAGE_PIN T3  [get_ports {sw_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_data[1]}]
set_property PACKAGE_PIN T2  [get_ports {sw_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_data[2]}]
set_property PACKAGE_PIN R3  [get_ports {sw_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_data[3]}]
set_property PACKAGE_PIN W2  [get_ports {sw_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_data[4]}]
set_property PACKAGE_PIN U1  [get_ports {sw_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_data[5]}]
set_property PACKAGE_PIN T1  [get_ports {sw_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_data[6]}]
set_property PACKAGE_PIN R2  [get_ports {sw_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_data[7]}]

## -----------------------------------------------------------------------------
## 4. Status LEDs
## -----------------------------------------------------------------------------
# EDIT PIN NUMBERS FOR YOUR BOARD
set_property PACKAGE_PIN U16 [get_ports led_single_err]
set_property IOSTANDARD LVCMOS33 [get_ports led_single_err]

set_property PACKAGE_PIN E19 [get_ports led_double_err]
set_property IOSTANDARD LVCMOS33 [get_ports led_double_err]

set_property PACKAGE_PIN U19 [get_ports led_tmr_mismatch]
set_property IOSTANDARD LVCMOS33 [get_ports led_tmr_mismatch]

set_property PACKAGE_PIN V19 [get_ports led_zeroize_busy]
set_property IOSTANDARD LVCMOS33 [get_ports led_zeroize_busy]

set_property PACKAGE_PIN W18 [get_ports led_zeroize_done]
set_property IOSTANDARD LVCMOS33 [get_ports led_zeroize_done]

set_property PACKAGE_PIN U15 [get_ports led_zeroize_fail]
set_property IOSTANDARD LVCMOS33 [get_ports led_zeroize_fail]

set_property PACKAGE_PIN U14 [get_ports led_busy]
set_property IOSTANDARD LVCMOS33 [get_ports led_busy]

## -----------------------------------------------------------------------------
## 5. Read Data LEDs [7:0]
## -----------------------------------------------------------------------------
# EDIT PIN NUMBERS FOR YOUR BOARD
set_property PACKAGE_PIN V14 [get_ports {led_rdata[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_rdata[0]}]
set_property PACKAGE_PIN V13 [get_ports {led_rdata[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_rdata[1]}]
set_property PACKAGE_PIN V3  [get_ports {led_rdata[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_rdata[2]}]
set_property PACKAGE_PIN W3  [get_ports {led_rdata[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_rdata[3]}]
set_property PACKAGE_PIN U3  [get_ports {led_rdata[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_rdata[4]}]
set_property PACKAGE_PIN P3  [get_ports {led_rdata[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_rdata[5]}]
set_property PACKAGE_PIN N3  [get_ports {led_rdata[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_rdata[6]}]
set_property PACKAGE_PIN P1  [get_ports {led_rdata[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_rdata[7]}]

## -----------------------------------------------------------------------------
## 6. Seven Segment Display (Cathodes seg[6:0] and Anodes an[3:0])
## -----------------------------------------------------------------------------
# EDIT PIN NUMBERS FOR YOUR BOARD
set_property PACKAGE_PIN W7 [get_ports {seg[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[0]}]
set_property PACKAGE_PIN W6 [get_ports {seg[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[1]}]
set_property PACKAGE_PIN U8 [get_ports {seg[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[2]}]
set_property PACKAGE_PIN V8 [get_ports {seg[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[3]}]
set_property PACKAGE_PIN U5 [get_ports {seg[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[4]}]
set_property PACKAGE_PIN V5 [get_ports {seg[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[5]}]
set_property PACKAGE_PIN U7 [get_ports {seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[6]}]

set_property PACKAGE_PIN U2 [get_ports {an[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[0]}]
set_property PACKAGE_PIN U4 [get_ports {an[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[1]}]
set_property PACKAGE_PIN V4 [get_ports {an[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[2]}]
set_property PACKAGE_PIN W4 [get_ports {an[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[3]}]

## -----------------------------------------------------------------------------
## 7. Configuration and Bitstream Properties
## -----------------------------------------------------------------------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

