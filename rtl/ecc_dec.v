`timescale 1ns / 1ps
// =============================================================================
// File:        ecc_dec.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Pure Combinational Systematic Linear ECC Decoder.
//
// Capabilities:
//   - T = 2 (Corrects up to 2 bit flips anywhere in the 18-bit stored word)
//   - Case-statement lookup table maps every correctable syndrome to its unique
//     error pattern. Any unlisted syndrome is flagged uncorrectable.
//
// Ports:
//   - code           : Raw codeword (18-bit)
//   - data_corrected : Corrected payload (8-bit)
//   - code_corrected : Corrected full codeword (18-bit)
//   - error_weight   : Number of bit errors identified (0..2)
//   - uncorrectable  : High when an uncorrectable multi-bit fault is detected
//   - single_err     : Pulses high if exactly 1 bit error was corrected
//   - double_err     : Pulses high if exactly 2 bit errors were corrected
//   - corrected_err  : High if any correctable error (1..2) was repaired
//   - syndrome       : Raw 10-bit parity syndrome
// =============================================================================

module ecc_dec #(
    parameter DATA_W = 8,
    parameter CHK_W  = 10,
    parameter CW_W   = 18,
    parameter T_ERR  = 2
)(
    input  wire [CW_W-1:0]   code,
    output wire [DATA_W-1:0] data_corrected,
    output wire [CW_W-1:0]   code_corrected,
    output wire [1:0]        error_weight,
    output wire              uncorrectable,
    output wire              single_err,
    output wire              double_err,
    output wire              corrected_err,
    output wire [CHK_W-1:0]  syndrome
);

    // -------------------------------------------------------------------------
    // 1. Syndrome Calculation
    // -------------------------------------------------------------------------
    wire [CHK_W-1:0] syn;
    assign syn[0] = (code[10] ^ code[11] ^ code[12] ^ code[15] ^ code[16] ^ code[17]) ^ code[0];
    assign syn[1] = (code[11] ^ code[13] ^ code[14] ^ code[16]) ^ code[1];
    assign syn[2] = (code[11] ^ code[13] ^ code[15] ^ code[16] ^ code[17]) ^ code[2];
    assign syn[3] = (code[11] ^ code[12] ^ code[13] ^ code[14] ^ code[15]) ^ code[3];
    assign syn[4] = (code[10] ^ code[12] ^ code[14] ^ code[15]) ^ code[4];
    assign syn[5] = (code[10] ^ code[12] ^ code[13] ^ code[15] ^ code[16]) ^ code[5];
    assign syn[6] = (code[12] ^ code[13] ^ code[16] ^ code[17]) ^ code[6];
    assign syn[7] = (code[10] ^ code[11] ^ code[12] ^ code[14] ^ code[17]) ^ code[7];
    assign syn[8] = (code[10] ^ code[11] ^ code[16] ^ code[17]) ^ code[8];
    assign syn[9] = (code[11] ^ code[12] ^ code[14] ^ code[16]) ^ code[9];

    assign syndrome = syn;

    // -------------------------------------------------------------------------
    // 2. Syndrome Lookup Table for Error Pattern & Weight
    // -------------------------------------------------------------------------
    reg [CW_W-1:0] err_pattern;
    reg [1:0]      err_weight;
    reg            uncorr;

    always @(*) begin
        case (syn)
            10'd0: begin
                err_pattern = 18'b000000000000000000;
                err_weight  = 2'd0;
                uncorr      = 1'b0;
            end
            10'd1: begin
                err_pattern = 18'b000000000000000001;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd2: begin
                err_pattern = 18'b000000000000000010;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd4: begin
                err_pattern = 18'b000000000000000100;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd8: begin
                err_pattern = 18'b000000000000001000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd16: begin
                err_pattern = 18'b000000000000010000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd32: begin
                err_pattern = 18'b000000000000100000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd61: begin
                err_pattern = 18'b001000000000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd64: begin
                err_pattern = 18'b000000000001000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd110: begin
                err_pattern = 18'b000010000000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd128: begin
                err_pattern = 18'b000000000010000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd256: begin
                err_pattern = 18'b000000000100000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd433: begin
                err_pattern = 18'b000000010000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd453: begin
                err_pattern = 18'b100000000000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd512: begin
                err_pattern = 18'b000000001000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd666: begin
                err_pattern = 18'b000100000000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd761: begin
                err_pattern = 18'b000001000000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd871: begin
                err_pattern = 18'b010000000000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd911: begin
                err_pattern = 18'b000000100000000000;
                err_weight  = 2'd1;
                uncorr      = 1'b0;
            end
            10'd3: begin
                err_pattern = 18'b000000000000000011;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd5: begin
                err_pattern = 18'b000000000000000101;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd6: begin
                err_pattern = 18'b000000000000000110;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd9: begin
                err_pattern = 18'b000000000000001001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd10: begin
                err_pattern = 18'b000000000000001010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd12: begin
                err_pattern = 18'b000000000000001100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd17: begin
                err_pattern = 18'b000000000000010001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd18: begin
                err_pattern = 18'b000000000000010010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd20: begin
                err_pattern = 18'b000000000000010100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd24: begin
                err_pattern = 18'b000000000000011000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd29: begin
                err_pattern = 18'b001000000000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd33: begin
                err_pattern = 18'b000000000000100001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd34: begin
                err_pattern = 18'b000000000000100010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd36: begin
                err_pattern = 18'b000000000000100100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd40: begin
                err_pattern = 18'b000000000000101000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd45: begin
                err_pattern = 18'b001000000000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd46: begin
                err_pattern = 18'b000010000001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd48: begin
                err_pattern = 18'b000000000000110000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd53: begin
                err_pattern = 18'b001000000000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd57: begin
                err_pattern = 18'b001000000000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd60: begin
                err_pattern = 18'b001000000000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd63: begin
                err_pattern = 18'b001000000000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd65: begin
                err_pattern = 18'b000000000001000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd66: begin
                err_pattern = 18'b000000000001000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd68: begin
                err_pattern = 18'b000000000001000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd72: begin
                err_pattern = 18'b000000000001001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd78: begin
                err_pattern = 18'b000010000000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd80: begin
                err_pattern = 18'b000000000001010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd83: begin
                err_pattern = 18'b001010000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd96: begin
                err_pattern = 18'b000000000001100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd99: begin
                err_pattern = 18'b000101000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd102: begin
                err_pattern = 18'b000010000000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd106: begin
                err_pattern = 18'b000010000000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd108: begin
                err_pattern = 18'b000010000000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd111: begin
                err_pattern = 18'b000010000000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd116: begin
                err_pattern = 18'b100000010000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd125: begin
                err_pattern = 18'b001000000001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd126: begin
                err_pattern = 18'b000010000000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd129: begin
                err_pattern = 18'b000000000010000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd130: begin
                err_pattern = 18'b000000000010000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd132: begin
                err_pattern = 18'b000000000010000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd136: begin
                err_pattern = 18'b000000000010001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd144: begin
                err_pattern = 18'b000000000010010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd154: begin
                err_pattern = 18'b000100001000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd160: begin
                err_pattern = 18'b000000000010100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd177: begin
                err_pattern = 18'b000000010100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd189: begin
                err_pattern = 18'b001000000010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd192: begin
                err_pattern = 18'b000000000011000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd197: begin
                err_pattern = 18'b100000000100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd232: begin
                err_pattern = 18'b010000100000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd238: begin
                err_pattern = 18'b000010000010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd249: begin
                err_pattern = 18'b000001001000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd257: begin
                err_pattern = 18'b000000000100000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd258: begin
                err_pattern = 18'b000000000100000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd260: begin
                err_pattern = 18'b000000000100000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd264: begin
                err_pattern = 18'b000000000100001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd272: begin
                err_pattern = 18'b000000000100010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd277: begin
                err_pattern = 18'b000100100000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd288: begin
                err_pattern = 18'b000000000100100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd305: begin
                err_pattern = 18'b000000010010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd317: begin
                err_pattern = 18'b001000000100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd320: begin
                err_pattern = 18'b000000000101000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd325: begin
                err_pattern = 18'b100000000010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd359: begin
                err_pattern = 18'b010000001000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd366: begin
                err_pattern = 18'b000010000100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd374: begin
                err_pattern = 18'b000001100000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd384: begin
                err_pattern = 18'b000000000110000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd389: begin
                err_pattern = 18'b100000000001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd396: begin
                err_pattern = 18'b001000010000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd399: begin
                err_pattern = 18'b000000101000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd401: begin
                err_pattern = 18'b000000010000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd414: begin
                err_pattern = 18'b010001000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd417: begin
                err_pattern = 18'b000000010000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd427: begin
                err_pattern = 18'b100010000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd432: begin
                err_pattern = 18'b000000010000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd435: begin
                err_pattern = 18'b000000010000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd437: begin
                err_pattern = 18'b000000010000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd441: begin
                err_pattern = 18'b000000010000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd449: begin
                err_pattern = 18'b100000000000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd452: begin
                err_pattern = 18'b100000000000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd455: begin
                err_pattern = 18'b100000000000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd461: begin
                err_pattern = 18'b100000000000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd469: begin
                err_pattern = 18'b100000000000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd479: begin
                err_pattern = 18'b000010010000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd485: begin
                err_pattern = 18'b100000000000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd497: begin
                err_pattern = 18'b000000010001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd504: begin
                err_pattern = 18'b101000000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd509: begin
                err_pattern = 18'b010100000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd513: begin
                err_pattern = 18'b000000001000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd514: begin
                err_pattern = 18'b000000001000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd516: begin
                err_pattern = 18'b000000001000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd520: begin
                err_pattern = 18'b000000001000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd528: begin
                err_pattern = 18'b000000001000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd538: begin
                err_pattern = 18'b000100000010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd544: begin
                err_pattern = 18'b000000001000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd573: begin
                err_pattern = 18'b001000001000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd574: begin
                err_pattern = 18'b000000110000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd576: begin
                err_pattern = 18'b000000001001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd586: begin
                err_pattern = 18'b100000100000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd615: begin
                err_pattern = 18'b010000000100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd622: begin
                err_pattern = 18'b000010001000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd633: begin
                err_pattern = 18'b000001000010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd640: begin
                err_pattern = 18'b000000001010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd650: begin
                err_pattern = 18'b000100000000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd655: begin
                err_pattern = 18'b000000100100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd658: begin
                err_pattern = 18'b000100000000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd663: begin
                err_pattern = 18'b000011000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd664: begin
                err_pattern = 18'b000100000000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd667: begin
                err_pattern = 18'b000100000000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd670: begin
                err_pattern = 18'b000100000000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd674: begin
                err_pattern = 18'b110000000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd679: begin
                err_pattern = 18'b001100000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd697: begin
                err_pattern = 18'b000001000001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd698: begin
                err_pattern = 18'b000100000000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd708: begin
                err_pattern = 18'b001001000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd726: begin
                err_pattern = 18'b010000010000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd729: begin
                err_pattern = 18'b000001000000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd730: begin
                err_pattern = 18'b000100000001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd745: begin
                err_pattern = 18'b000001000000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd753: begin
                err_pattern = 18'b000001000000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd756: begin
                err_pattern = 18'b000110000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd760: begin
                err_pattern = 18'b000001000000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd763: begin
                err_pattern = 18'b000001000000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd765: begin
                err_pattern = 18'b000001000000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd768: begin
                err_pattern = 18'b000000001100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd777: begin
                err_pattern = 18'b010010000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd783: begin
                err_pattern = 18'b000000100010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd807: begin
                err_pattern = 18'b010000000001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd811: begin
                err_pattern = 18'b000100010000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd828: begin
                err_pattern = 18'b100001000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd839: begin
                err_pattern = 18'b010000000000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd840: begin
                err_pattern = 18'b000001010000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd858: begin
                err_pattern = 18'b011000000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd863: begin
                err_pattern = 18'b100100000000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd867: begin
                err_pattern = 18'b010000000000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd869: begin
                err_pattern = 18'b010000000000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd870: begin
                err_pattern = 18'b010000000000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd879: begin
                err_pattern = 18'b010000000000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd887: begin
                err_pattern = 18'b010000000000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd903: begin
                err_pattern = 18'b000000100000001000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd907: begin
                err_pattern = 18'b000000100000000100;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd909: begin
                err_pattern = 18'b000000100000000010;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd910: begin
                err_pattern = 18'b000000100000000001;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd922: begin
                err_pattern = 18'b000100000100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd927: begin
                err_pattern = 18'b000000100000010000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd943: begin
                err_pattern = 18'b000000100000100000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd945: begin
                err_pattern = 18'b000000011000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd946: begin
                err_pattern = 18'b001000100000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd965: begin
                err_pattern = 18'b100000001000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd975: begin
                err_pattern = 18'b000000100001000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd993: begin
                err_pattern = 18'b000010100000000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd999: begin
                err_pattern = 18'b010000000010000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            10'd1017: begin
                err_pattern = 18'b000001000100000000;
                err_weight  = 2'd2;
                uncorr      = 1'b0;
            end
            default: begin
                err_pattern = 18'd0;
                err_weight  = 2'd0;
                uncorr      = 1'b1;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // 3. Error Correction & Output Decoding
    // -------------------------------------------------------------------------
    wire [CW_W-1:0] corrected_codeword = code ^ err_pattern;

    assign code_corrected = corrected_codeword;
    assign data_corrected = corrected_codeword[CW_W-1:CHK_W];
    assign error_weight   = err_weight;
    assign uncorrectable  = uncorr;
    assign single_err     = (err_weight == 2'd1);
    assign double_err     = (err_weight == 2'd2);
    assign corrected_err  = (err_weight != 2'd0);

endmodule
