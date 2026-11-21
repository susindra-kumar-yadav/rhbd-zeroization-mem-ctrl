`timescale 1ns / 1ps
// =============================================================================
// File:        hamming_secded_dec.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Pure Combinational Hamming (12,8) SECDED Decoder.
//
// Operation & Error Detection Classification:
//   1) syndrome != 0 && overall_parity_wrong: Single bit error in bits 1..12.
//      Bit specified by syndrome is inverted to self-heal the data.
//   2) syndrome == 0 && overall_parity_wrong: Single bit error in bit 0 (p0).
//      Data bits are valid; bit 0 is repaired in code_corrected.
//   3) syndrome != 0 && overall_parity_ok: Double bit error (uncorrectable).
//      double_err flag is raised; data cannot be trusted.
//   4) syndrome == 0 && overall_parity_ok: No error detected.
// =============================================================================

module hamming_secded_dec (
    input  wire [12:0] code,
    output wire [7:0]  data_corrected,
    output wire        single_err,
    output wire        double_err,
    output wire [3:0]  syndrome,
    output wire [12:0] code_corrected
);

    // -------------------------------------------------------------------------
    // 1. Syndrome Calculation
    // -------------------------------------------------------------------------
    // Each syndrome bit checks the parity of its respective Hamming group:
    //   syn[0]: positions {1, 3, 5, 7, 9, 11}
    //   syn[1]: positions {2, 3, 6, 7, 10, 11}
    //   syn[2]: positions {4, 5, 6, 7, 12}
    //   syn[3]: positions {8, 9, 10, 11, 12}
    wire [3:0] syn;
    assign syn[0] = code[1] ^ code[3] ^ code[5] ^ code[7] ^ code[9] ^ code[11];
    assign syn[1] = code[2] ^ code[3] ^ code[6] ^ code[7] ^ code[10] ^ code[11];
    assign syn[2] = code[4] ^ code[5] ^ code[6] ^ code[7] ^ code[12];
    assign syn[3] = code[8] ^ code[9] ^ code[10] ^ code[11] ^ code[12];

    assign syndrome = syn;

    // -------------------------------------------------------------------------
    // 2. Overall Parity Check
    // -------------------------------------------------------------------------
    // XOR reduction across all 13 bits (code[12:0]).
    // In an even-parity system:
    //   overall_parity == 0 -> Parity OK (0 errors or 2 errors)
    //   overall_parity == 1 -> Parity Wrong (1 error or 3 errors)
    wire overall_parity = ^code;
    wire overall_parity_wrong = overall_parity;
    wire syndrome_nonzero     = (syn != 4'd0);

    // -------------------------------------------------------------------------
    // 3. SECDED Decision Logic
    // -------------------------------------------------------------------------
    // Single error: overall parity is violated, and syndrome points to bits 0..12.
    // Double error: overall parity is satisfied (even bit flips), but syndrome is non-zero,
    //               OR parity violated but syndrome exceeds valid bit range (> 12).
    assign single_err = overall_parity_wrong && (syn <= 4'd12);
    assign double_err = (!overall_parity_wrong && syndrome_nonzero) ||
                        (overall_parity_wrong && (syn > 4'd12));

    // -------------------------------------------------------------------------
    // 4. Correction Logic (Combinational)
    // -------------------------------------------------------------------------
    reg [12:0] corrected;
    always @(*) begin
        corrected = code;
        if (single_err) begin
            if (syn >= 4'd1 && syn <= 4'd12) begin
                corrected[syn] = ~code[syn]; // Correct bit at position pointed by syndrome
            end else if (syn == 4'd0) begin
                corrected[0]   = ~code[0];   // Correct overall parity bit (p0)
            end
        end
    end

    assign code_corrected = corrected;

    // -------------------------------------------------------------------------
    // 5. Extract Corrected 8-bit Data Payload
    // -------------------------------------------------------------------------
    assign data_corrected[0] = corrected[3];
    assign data_corrected[1] = corrected[5];
    assign data_corrected[2] = corrected[6];
    assign data_corrected[3] = corrected[7];
    assign data_corrected[4] = corrected[9];
    assign data_corrected[5] = corrected[10];
    assign data_corrected[6] = corrected[11];
    assign data_corrected[7] = corrected[12];

endmodule

