`timescale 1ns / 1ps
// =============================================================================
// File:        ecc_enc.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Pure Combinational Systematic Linear ECC Encoder.
//
// Parameters & Geometry:
//   - DATA_W = 8 bits (payload)
//   - CHK_W  = 10 bits (parity check bits)
//   - CW_W   = 18 bits (total codeword width)
//
// Codeword Layout (Systematic Form):
//   - code[17:10] : Data bits payload (data[7:0])
//   - code[9:0]  : Parity check bits (parity[9:0])
//
// Key Mathematical Property:
//   data = 8'h00 -> code = 18'h0 (Essential for secure zeroization / clean reset).
// =============================================================================

module ecc_enc #(
    parameter DATA_W = 8,
    parameter CHK_W  = 10,
    parameter CW_W   = 18
)(
    input  wire [DATA_W-1:0] data,
    output wire [CW_W-1:0]   code
);

    // -------------------------------------------------------------------------
    // Parity Generation Logic (Combinational XOR Trees)
    // -------------------------------------------------------------------------
    wire p0 = data[0] ^ data[1] ^ data[2] ^ data[5] ^ data[6] ^ data[7];
    wire p1 = data[1] ^ data[3] ^ data[4] ^ data[6];
    wire p2 = data[1] ^ data[3] ^ data[5] ^ data[6] ^ data[7];
    wire p3 = data[1] ^ data[2] ^ data[3] ^ data[4] ^ data[5];
    wire p4 = data[0] ^ data[2] ^ data[4] ^ data[5];
    wire p5 = data[0] ^ data[2] ^ data[3] ^ data[5] ^ data[6];
    wire p6 = data[2] ^ data[3] ^ data[6] ^ data[7];
    wire p7 = data[0] ^ data[1] ^ data[2] ^ data[4] ^ data[7];
    wire p8 = data[0] ^ data[1] ^ data[6] ^ data[7];
    wire p9 = data[1] ^ data[2] ^ data[4] ^ data[6];

    // -------------------------------------------------------------------------
    // Codeword Assembly: Systematic concatenation {data, parity}
    // -------------------------------------------------------------------------
    assign code[0] = p0;
    assign code[1] = p1;
    assign code[2] = p2;
    assign code[3] = p3;
    assign code[4] = p4;
    assign code[5] = p5;
    assign code[6] = p6;
    assign code[7] = p7;
    assign code[8] = p8;
    assign code[9] = p9;
    assign code[10] = data[0];
    assign code[11] = data[1];
    assign code[12] = data[2];
    assign code[13] = data[3];
    assign code[14] = data[4];
    assign code[15] = data[5];
    assign code[16] = data[6];
    assign code[17] = data[7];

endmodule
