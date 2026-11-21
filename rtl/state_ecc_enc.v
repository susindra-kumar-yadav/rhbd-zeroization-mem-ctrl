`timescale 1ns / 1ps
// =============================================================================
// File:        state_ecc_enc.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Generated:   Automated generation by tools/gen_ecc_code.py
// Standards:   Verilog-2001
// Description: Parameterized Combinational FSM State Register ECC Encoder.
//              Supports both:
//                - T_ERR = 2 (default): DEC-TED [11, 3, 6] (CHK=8, CW=11)
//                - T_ERR = 1          : SECDED  [7, 3, 4]  (CHK=4, CW=7)
//
// Key Mathematical Property:
//   data = 3'b000 (ST_IDLE) -> code = 0 (clean reset & state self-healing).
// =============================================================================

module state_ecc_enc #(
    parameter DATA_W = 3,
    parameter T_ERR  = 2,
    parameter CHK_W  = (T_ERR == 1) ? 4 : 8,
    parameter CW_W   = DATA_W + CHK_W
)(
    input  wire [DATA_W-1:0] data,
    output wire [CW_W-1:0]   code
);

    generate
        if (CHK_W == 4 || T_ERR == 1) begin : gen_t1_secded
            // SECDED [7,3,4]: P = [7, 13, 11]
            // p0 = d0 ^ d1 ^ d2
            // p1 = d0 ^ d2
            // p2 = d0 ^ d1
            // p3 = d1 ^ d2
            wire p0 = data[0] ^ data[1] ^ data[2];
            wire p1 = data[0] ^ data[2];
            wire p2 = data[0] ^ data[1];
            wire p3 = data[1] ^ data[2];
            assign code = {data, p3, p2, p1, p0};
        end else begin : gen_t2_dected
            // DEC-TED [11,3,6]: P = [31, 103, 171]
            // 31  = 8'b00011111 (d0 covers p0, p1, p2, p3, p4)
            // 103 = 8'b01100111 (d1 covers p0, p1, p2, p5, p6)
            // 171 = 8'b10101011 (d2 covers p0, p1, p3, p5, p7)
            wire p0 = data[0] ^ data[1] ^ data[2];
            wire p1 = data[0] ^ data[1] ^ data[2];
            wire p2 = data[0] ^ data[1];
            wire p3 = data[0] ^ data[2];
            wire p4 = data[0];
            wire p5 = data[1] ^ data[2];
            wire p6 = data[1];
            wire p7 = data[2];
            assign code = {data, p7, p6, p5, p4, p3, p2, p1, p0};
        end
    endgenerate

endmodule
