`timescale 1ns / 1ps
// =============================================================================
// File:        state_ecc_dec.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Parameterized Combinational FSM State Register ECC Decoder.
//              Supports both:
//                - T_ERR = 2 (default): DEC-TED [11, 3, 6], 67 table entries, corrects 2 bits.
//                - T_ERR = 1          : SECDED  [7, 3, 4],  8 table entries, corrects 1 bit.
//
// Behavior:
//   - Flips <= T_ERR are repaired locally and raise corrected_err (single_err / double_err).
//   - Flips > T_ERR raise uncorrectable (copy_bad) when detectable.
//   - For T_ERR = 2, d_min = 6 mathematically guarantees 100% detection of all 165
//     weight-3 bit flips as uncorrectable with 0 miscorrections.
// =============================================================================

module state_ecc_dec #(
    parameter DATA_W = 3,
    parameter T_ERR  = 2,
    parameter CHK_W  = (T_ERR == 1) ? 4 : 8,
    parameter CW_W   = DATA_W + CHK_W
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

    generate
        if (CHK_W == 4 || T_ERR == 1) begin : gen_t1_secded
            // Syndrome Calculation for [7,3,4] SECDED
            wire [3:0] syn;
            assign syn[0] = code[4] ^ code[5] ^ code[6] ^ code[0];
            assign syn[1] = code[4] ^ code[6] ^ code[1];
            assign syn[2] = code[4] ^ code[5] ^ code[2];
            assign syn[3] = code[5] ^ code[6] ^ code[3];

            reg [6:0] err_pat;
            reg [1:0] err_wt;
            reg       uncorr;

            always @(*) begin
                case (syn)
                    4'd0: begin err_pat = 7'b0000000; err_wt = 2'd0; uncorr = 1'b0; end
                    4'd1: begin err_pat = 7'b0000001; err_wt = 2'd1; uncorr = 1'b0; end
                    4'd2: begin err_pat = 7'b0000010; err_wt = 2'd1; uncorr = 1'b0; end
                    4'd4: begin err_pat = 7'b0000100; err_wt = 2'd1; uncorr = 1'b0; end
                    4'd7: begin err_pat = 7'b0010000; err_wt = 2'd1; uncorr = 1'b0; end
                    4'd8: begin err_pat = 7'b0001000; err_wt = 2'd1; uncorr = 1'b0; end
                    4'd11: begin err_pat = 7'b1000000; err_wt = 2'd1; uncorr = 1'b0; end
                    4'd13: begin err_pat = 7'b0100000; err_wt = 2'd1; uncorr = 1'b0; end
                    default: begin
                        err_pat = 7'b0000000;
                        err_wt  = 2'd0;
                        uncorr  = 1'b1;
                    end
                endcase
            end

            wire [6:0] corr_code = code[6:0] ^ err_pat;

            assign syndrome       = syn;
            assign code_corrected = corr_code;
            assign data_corrected = corr_code[6:4];
            assign error_weight   = err_wt;
            assign uncorrectable  = uncorr;
            assign single_err     = (err_wt == 2'd1);
            assign double_err     = 1'b0;
            assign corrected_err  = (err_wt != 2'd0);

        end else begin : gen_t2_dected
            // Syndrome Calculation for [11,3,6] DEC-TED
            wire [7:0] syn;
            assign syn[0] = code[8] ^ code[9] ^ code[10] ^ code[0];
            assign syn[1] = code[8] ^ code[9] ^ code[10] ^ code[1];
            assign syn[2] = code[8] ^ code[9] ^ code[2];
            assign syn[3] = code[8] ^ code[10] ^ code[3];
            assign syn[4] = code[8] ^ code[4];
            assign syn[5] = code[9] ^ code[10] ^ code[5];
            assign syn[6] = code[9] ^ code[6];
            assign syn[7] = code[10] ^ code[7];

            reg [10:0] err_pat;
            reg [1:0]  err_wt;
            reg        uncorr;

            always @(*) begin
                case (syn)
                    8'd0: begin err_pat = 11'b00000000000; err_wt = 2'd0; uncorr = 1'b0; end
                    8'd1: begin err_pat = 11'b00000000001; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd2: begin err_pat = 11'b00000000010; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd4: begin err_pat = 11'b00000000100; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd8: begin err_pat = 11'b00000001000; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd16: begin err_pat = 11'b00000010000; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd31: begin err_pat = 11'b00100000000; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd32: begin err_pat = 11'b00000100000; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd64: begin err_pat = 11'b00001000000; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd103: begin err_pat = 11'b01000000000; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd128: begin err_pat = 11'b00010000000; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd171: begin err_pat = 11'b10000000000; err_wt = 2'd1; uncorr = 1'b0; end
                    8'd3: begin err_pat = 11'b00000000011; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd5: begin err_pat = 11'b00000000101; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd6: begin err_pat = 11'b00000000110; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd9: begin err_pat = 11'b00000001001; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd10: begin err_pat = 11'b00000001010; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd12: begin err_pat = 11'b00000001100; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd15: begin err_pat = 11'b00100010000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd17: begin err_pat = 11'b00000010001; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd18: begin err_pat = 11'b00000010010; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd20: begin err_pat = 11'b00000010100; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd23: begin err_pat = 11'b00100001000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd24: begin err_pat = 11'b00000011000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd27: begin err_pat = 11'b00100000100; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd29: begin err_pat = 11'b00100000010; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd30: begin err_pat = 11'b00100000001; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd33: begin err_pat = 11'b00000100001; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd34: begin err_pat = 11'b00000100010; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd36: begin err_pat = 11'b00000100100; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd39: begin err_pat = 11'b01001000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd40: begin err_pat = 11'b00000101000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd43: begin err_pat = 11'b10010000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd48: begin err_pat = 11'b00000110000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd63: begin err_pat = 11'b00100100000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd65: begin err_pat = 11'b00001000001; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd66: begin err_pat = 11'b00001000010; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd68: begin err_pat = 11'b00001000100; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd71: begin err_pat = 11'b01000100000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd72: begin err_pat = 11'b00001001000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd80: begin err_pat = 11'b00001010000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd95: begin err_pat = 11'b00101000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd96: begin err_pat = 11'b00001100000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd99: begin err_pat = 11'b01000000100; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd101: begin err_pat = 11'b01000000010; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd102: begin err_pat = 11'b01000000001; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd111: begin err_pat = 11'b01000001000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd119: begin err_pat = 11'b01000010000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd120: begin err_pat = 11'b01100000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd129: begin err_pat = 11'b00010000001; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd130: begin err_pat = 11'b00010000010; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd132: begin err_pat = 11'b00010000100; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd136: begin err_pat = 11'b00010001000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd139: begin err_pat = 11'b10000100000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd144: begin err_pat = 11'b00010010000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd159: begin err_pat = 11'b00110000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd160: begin err_pat = 11'b00010100000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd163: begin err_pat = 11'b10000001000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd169: begin err_pat = 11'b10000000010; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd170: begin err_pat = 11'b10000000001; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd175: begin err_pat = 11'b10000000100; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd180: begin err_pat = 11'b10100000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd187: begin err_pat = 11'b10000010000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd192: begin err_pat = 11'b00011000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd204: begin err_pat = 11'b11000000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd231: begin err_pat = 11'b01010000000; err_wt = 2'd2; uncorr = 1'b0; end
                    8'd235: begin err_pat = 11'b10001000000; err_wt = 2'd2; uncorr = 1'b0; end
                    default: begin
                        err_pat = 11'b00000000000;
                        err_wt  = 2'd0;
                        uncorr  = 1'b1;
                    end
                endcase
            end

            wire [10:0] corr_code = code[10:0] ^ err_pat;

            assign syndrome       = syn;
            assign code_corrected = corr_code;
            assign data_corrected = corr_code[10:8];
            assign error_weight   = err_wt;
            assign uncorrectable  = uncorr;
            assign single_err     = (err_wt == 2'd1);
            assign double_err     = (err_wt == 2'd2);
            assign corrected_err  = (err_wt != 2'd0);

        end
    endgenerate

endmodule
