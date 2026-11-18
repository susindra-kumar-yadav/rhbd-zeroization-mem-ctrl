`timescale 1ns / 1ps
// =============================================================================
// File:        zeroize_engine.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Military/Cryptographic Grade Secure Memory Zeroization Engine.
//
// Operation & Features:
//   - Triggered by tamper input (asynchronous or synchronous glitch/pulse/level).
//   - Tamper event is permanently latched until synchronous reset or clear.
//   - Configurable multi-pass overwrite (PASSES = 1 or 3):
//       * PASSES == 1: Single pass of 13'h0000 (encoded 8'h00).
//       * PASSES == 3: DoD 5220.22-M style overwrite:
//           Pass 1: Write all zeros (13'h0000)
//           Pass 2: Write all ones  (13'h1EEE, encoded 8'hFF)
//           Pass 3: Write all zeros (13'h0000)
//   - Autonomous Post-Wipe Verification Pass:
//       * Sweeps through all 256 words checking each location decodes to 8'h00.
//       * Raises zeroize_fail if any residual or corrupted pattern remains.
//   - Outputs:
//       * zeroize_busy: High during active zeroization and verification.
//       * zeroize_done: Stays high once complete until rst/clear.
//       * zeroize_fail: Latched high if post-wipe verification fails.
// =============================================================================

module zeroize_engine #(
    parameter AW     = 8,
    parameter DW     = 13,
    parameter PASSES = 3
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          tamper,
    input  wire          zeroize_clear,
    input  wire [DW-1:0] ram_rdata,

    output wire          zeroize_we,
    output wire [AW-1:0] zeroize_addr,
    output wire [DW-1:0] zeroize_din,
    output reg           zeroize_busy,
    output reg           zeroize_done,
    output reg           zeroize_fail
);

    // Encoded constants for zeroization
    // 8'h00 encodes to 13'h0000 (all zeros)
    // 8'hFF encodes to 13'h1EEE (13'b1_1110_1110_1110)
    localparam [DW-1:0] CODE_ZERO = 13'h0000;
    localparam [DW-1:0] CODE_ONES = 13'h1EEE;

    // FSM State Encoding
    localparam [1:0]
        S_IDLE        = 2'd0,
        S_WRITE_PASS  = 2'd1,
        S_VERIFY_RUN  = 2'd2,
        S_DONE        = 2'd3;

    reg [1:0] state;
    reg       tamper_latched;
    reg [1:0] pass_cnt;
    reg [8:0] w_cnt;
    reg [8:0] v_cnt;

    // SECDED Decoder instance for post-wipe verification
    wire [7:0]  v_data;
    wire        v_single_err;
    wire        v_double_err;
    wire [3:0]  v_syn;
    wire [12:0] v_code_cor;

    hamming_secded_dec verify_dec (
        .code          (ram_rdata),
        .data_corrected(v_data),
        .single_err    (v_single_err),
        .double_err    (v_double_err),
        .syndrome      (v_syn),
        .code_corrected(v_code_cor)
    );

    // Continuous assignment of RAM control signals avoids register latency issues
    assign zeroize_we   = (state == S_WRITE_PASS);
    assign zeroize_addr = (state == S_WRITE_PASS) ? w_cnt[AW-1:0] :
                          (state == S_VERIFY_RUN)  ? v_cnt[AW-1:0] : {AW{1'b0}};
    assign zeroize_din  = (PASSES == 3 && pass_cnt == 2'd1) ? CODE_ONES : CODE_ZERO;

    // -------------------------------------------------------------------------
    // Tamper Latch: Catches pulses or levels and holds until reset / clear
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || zeroize_clear) begin
            tamper_latched <= 1'b0;
        end else if (tamper) begin
            tamper_latched <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Zeroization Execution Engine FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || zeroize_clear) begin
            state        <= S_IDLE;
            pass_cnt     <= 2'd0;
            w_cnt        <= 9'd0;
            v_cnt        <= 9'd0;
            zeroize_busy <= 1'b0;
            zeroize_done <= 1'b0;
            zeroize_fail <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (tamper || tamper_latched) begin
                        zeroize_busy <= 1'b1;
                        zeroize_done <= 1'b0;
                        zeroize_fail <= 1'b0;
                        pass_cnt     <= 2'd0;
                        w_cnt        <= 9'd0;
                        v_cnt        <= 9'd0;
                        state        <= S_WRITE_PASS;
                    end
                end

                S_WRITE_PASS: begin
                    if (w_cnt == (1 << AW) - 1) begin
                        w_cnt <= 9'd0;
                        if (pass_cnt == (PASSES - 1)) begin
                            // Finished all overwrite passes, transition directly to verification
                            v_cnt <= 9'd0;
                            state <= S_VERIFY_RUN;
                        end else begin
                            pass_cnt <= pass_cnt + 2'd1;
                        end
                    end else begin
                        w_cnt <= w_cnt + 1'b1;
                    end
                end

                S_VERIFY_RUN: begin
                    // Evaluate previous read word:
                    // When v_cnt > 0, ram_rdata contains data from address (v_cnt - 1)
                    if (v_cnt > 9'd0) begin
                        if ((v_data != 8'h00) || v_double_err || (ram_rdata != CODE_ZERO)) begin
                            zeroize_fail <= 1'b1;
                        end
                    end

                    // Pipeline counter: increments from 0 to 256
                    if (v_cnt == (1 << AW)) begin
                        state        <= S_DONE;
                        zeroize_busy <= 1'b0;
                        zeroize_done <= 1'b1;
                    end else begin
                        v_cnt <= v_cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    zeroize_busy <= 1'b0;
                    zeroize_done <= 1'b1;
                    // Remains in S_DONE until reset or zeroize_clear
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
