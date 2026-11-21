`timescale 1ns / 1ps
// =============================================================================
// File:        state_ecc_params.vh
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Global Parameters for FSM State Register ECC Protection.
//              Supports both T_STATE = 1 (SECDED) and T_STATE = 2 (DEC-TED).
// =============================================================================

`ifndef STATE_ECC_PARAMS_VH
`define STATE_ECC_PARAMS_VH

// Default Configuration: T_STATE = 2 (DEC-TED [11, 3, 6])
parameter STATE_ECC_DATA_W    = 3;
parameter STATE_ECC_DEFAULT_T = 2;
parameter STATE_ECC_T2_CHK_W  = 8;
parameter STATE_ECC_T2_CW_W   = 11;
parameter STATE_ECC_T2_DMIN   = 6;
parameter STATE_ECC_T2_TABLE  = 67;

// Alternate Configuration: T_STATE = 1 (SECDED [7, 3, 4])
parameter STATE_ECC_T1_CHK_W  = 4;
parameter STATE_ECC_T1_CW_W   = 7;
parameter STATE_ECC_T1_DMIN   = 4;
parameter STATE_ECC_T1_TABLE  = 8;

`endif // STATE_ECC_PARAMS_VH
