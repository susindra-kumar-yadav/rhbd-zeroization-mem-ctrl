`timescale 1ns / 1ps
// File:        hamming_secded_enc.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Hamming (12,8) Single Error Correction, Double Error Detection
//              (SECDED) Encoder.
//
// Codeword Layout (13 bits total):
//   bit[0]  : p0 (overall even parity over bits 1..12)
//   bit[1]  : p1 (parity bit for Hamming set 1)
//   bit[2]  : p2 (parity bit for Hamming set 2)
//   bit[3]  : data[0]
//   bit[4]  : p4 (parity bit for Hamming set 4)
//   bit[5]  : data[1]
//   bit[6]  : data[2]
//   bit[7]  : data[3]
//   bit[8]  : p8 (parity bit for Hamming set 8)
//   bit[9]  : data[4]
//   bit[10] : data[5]
//   bit[11] : data[6]
//   bit[12] : data[7]
//
// Key Property:
//   data = 8'h00 -> code = 13'h0000 (essential for secure memory zeroization).

module hamming_secded_enc (
    input  wire [7:0]  data,
    output wire [12:0] code
);
    // Hamming Parity Generation (Even Parity)
    // -------------------------------------------------------------------------
    // Parity bits cover 1-indexed bit positions whose binary indices have 1 in
    // their respective bit positions:
    //   p1: positions {1, 3, 5, 7, 9, 11} -> data bits {0, 1, 3, 4, 6}
    //   p2: positions {2, 3, 6, 7, 10, 11} -> data bits {0, 2, 3, 5, 6}
    //   p4: positions {4, 5, 6, 7, 12} -> data bits {1, 2, 3, 7}
    //   p8: positions {8, 9, 10, 11, 12} -> data bits {4, 5, 6, 7}
    wire p1 = data[0] ^ data[1] ^ data[3] ^ data[4] ^ data[6];
    wire p2 = data[0] ^ data[2] ^ data[3] ^ data[5] ^ data[6];
    wire p4 = data[1] ^ data[2] ^ data[3] ^ data[7];
    wire p8 = data[4] ^ data[5] ^ data[6] ^ data[7];

    // Overall parity p0 covers all 12 bits (code[12:1]) to ensure the entire
    // 13-bit codeword has even parity.
    wire p0 = p1 ^ p2 ^ data[0] ^ p4 ^ data[1] ^ data[2] ^ data[3] ^
              p8 ^ data[4] ^ data[5] ^ data[6] ^ data[7];

    // -------------------------------------------------------------------------
    assign code[0]  = p0;
    assign code[1]  = p1;
    assign code[2]  = p2;
    assign code[3]  = data[0];
    assign code[4]  = p4;
    assign code[5]  = data[1];
    assign code[6]  = data[2];
    assign code[7]  = data[3];
    assign code[8]  = p8;
    assign code[9]  = data[4];
    assign code[10] = data[5];
    assign code[11] = data[6];
    assign code[12] = data[7];

endmodule

