`timescale 1ns / 1ps
// =============================================================================
// File:        ecc_params.vh
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Global Parameters for Double-Error-Correcting (DEC-TED, T=2) Memory ECC.
//
// Parameters:
//   DATA_W   = 8  (Information payload bits)
//   CHK_W    = 10 (Parity check bits)
//   CW_W     = 18 (Total codeword width)
//   T_ERR    = 2  (Maximum correctable bit errors)
//   D_MIN    = 6  (Minimum Hamming distance)
// =============================================================================

`ifndef ECC_PARAMS_VH
`define ECC_PARAMS_VH

parameter ECC_DATA_W = 8;
parameter ECC_CHK_W  = 10;
parameter ECC_CW_W   = 18;
parameter ECC_T      = 2;
parameter ECC_DMIN   = 6;

`endif // ECC_PARAMS_VH
