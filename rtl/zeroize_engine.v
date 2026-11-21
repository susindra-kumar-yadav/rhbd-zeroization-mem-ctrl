`timescale 1ns / 1ps
// =============================================================================
// File:        zeroize_engine.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Military-Grade Anti-Tamper Secure Zeroization Engine with
//              Triple Redundancy and Dual Complementary Address Counter Checking.
//
// Radiation-Hardened & Security Features (Phase 2):
//   1. Triple-Redundant Tamper Latch:
//      - Three independent flip-flops (tamper_latch_r0, r1, r2) with (* DONT_TOUCH = "TRUE" *).
//      - Bitwise majority voting prevents a single radiation upset from either
//        triggering a false wipe or clearing an active tamper latch.
//   2. Triple-Redundant Done Flag:
//      - Three independent flip-flops (zeroize_done_r0, r1, r2) with (* DONT_TOUCH = "TRUE" *).
//      - Majority voted output prevents premature completion signaling.
//   3. Dual Complementary Counter Invariant Check:
//      - An up-counter (w_cnt / v_cnt) and a down-counter (w_down_cnt / v_down_cnt)
//        traverse the memory array concurrently.
//      - Invariant: (up_cnt + down_cnt) MUST equal ((1 << AW) - 1) on every cycle.
//      - Any single-event upset (SEU) corrupting either counter immediately trips
//        the `zeroize_counter_fault` alert signal.
//   4. Multi-Pass DoD Overwrite & Verification:
//      - Pass 0: 8'h00 (encoded via ecc_enc to all-zeros codeword).
//      - Pass 1: 8'hFF (encoded via ecc_enc to all-ones data codeword).
//      - Pass 2: 8'h00 (encoded via ecc_enc to all-zeros codeword).
//      - Post-Wipe Hardware Verification Pass: Decodes all words via ecc_dec
//        to verify zeroization integrity before unlocking.
// =============================================================================

module zeroize_engine #(
    parameter AW     = 8,
    parameter DATA_W = 8,
    parameter CHK_W  = 10,
    parameter CW     = 18,
    parameter DW     = CW,
    parameter PASSES = 3
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          tamper,
    input  wire          zeroize_clear,
    input  wire [CW-1:0] ram_rdata,

    // Fault Injection for Verification / Demonstration
    input  wire          tamper_fault_inject,  // Inverts tamper latch copy 0
    input  wire          zeroize_fault_inject, // Corrupts down-counter to trip safety check

    // RAM Control Interface
    output wire          zeroize_we,
    output wire [AW-1:0] zeroize_addr,
    output wire [CW-1:0] zeroize_din,
    output reg           zeroize_busy,
    output wire          zeroize_done,
    output reg           zeroize_fail,
    output reg           zeroize_counter_fault
);

    // -------------------------------------------------------------------------
    // FSM States for Zeroization Sequence
    // -------------------------------------------------------------------------
    localparam [1:0]
        S_IDLE        = 2'd0,
        S_WRITE_PASS  = 2'd1,
        S_VERIFY_RUN  = 2'd2,
        S_DONE        = 2'd3;

    reg [1:0] state;
    reg [1:0] pass_cnt;

    // Up-counters and Down-counters for Address Integrity
    reg [8:0]    w_cnt;
    reg [8:0]    w_down_cnt;
    reg [8:0]    v_cnt;
    reg [8:0]    v_down_cnt;

    // -------------------------------------------------------------------------
    // 1. Triple-Redundant Tamper Latch with Majority Voting
    // -------------------------------------------------------------------------
    // Synthesis directive DONT_TOUCH prevents Vivado logic optimization from
    // merging these three redundant flip-flops into a single point of failure.
    (* DONT_TOUCH = "TRUE" *) reg tamper_latch_r0;
    (* DONT_TOUCH = "TRUE" *) reg tamper_latch_r1;
    (* DONT_TOUCH = "TRUE" *) reg tamper_latch_r2;

    // Majority voting logic: (A & B) | (B & C) | (A & C)
    wire tamper_voted = (tamper_latch_r0 & tamper_latch_r1) |
                        (tamper_latch_r1 & tamper_latch_r2) |
                        (tamper_latch_r0 & tamper_latch_r2);

    always @(posedge clk) begin
        if (rst || zeroize_clear) begin
            tamper_latch_r0 <= 1'b0;
            tamper_latch_r1 <= 1'b0;
            tamper_latch_r2 <= 1'b0;
        end else if (tamper) begin
            tamper_latch_r0 <= 1'b1;
            tamper_latch_r1 <= 1'b1;
            tamper_latch_r2 <= 1'b1;
        end else begin
            // Self-healing: continually restore the voted state back into all copies.
            // tamper_fault_inject permits deliberate corruption of copy 0 for viva testing.
            tamper_latch_r0 <= (tamper_fault_inject) ? ~tamper_voted : tamper_voted;
            tamper_latch_r1 <= tamper_voted;
            tamper_latch_r2 <= tamper_voted;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Triple-Redundant Zeroize Done Flag with Majority Voting
    // -------------------------------------------------------------------------
    (* DONT_TOUCH = "TRUE" *) reg zeroize_done_r0;
    (* DONT_TOUCH = "TRUE" *) reg zeroize_done_r1;
    (* DONT_TOUCH = "TRUE" *) reg zeroize_done_r2;

    wire zeroize_done_voted = (zeroize_done_r0 & zeroize_done_r1) |
                              (zeroize_done_r1 & zeroize_done_r2) |
                              (zeroize_done_r0 & zeroize_done_r2);

    assign zeroize_done = zeroize_done_voted;

    // -------------------------------------------------------------------------
    // 3. Dynamic ECC Encoder for Zeroization Write Patterns
    // -------------------------------------------------------------------------
    // Pass 0: 8'h00 -> all zeros codeword
    // Pass 1: 8'hFF -> fully encoded 0xFF codeword (if PASSES == 3)
    // Pass 2: 8'h00 -> all zeros codeword
    wire [DATA_W-1:0] zeroize_data_byte = (PASSES == 3 && pass_cnt == 2'd1) ? {DATA_W{1'b1}} : {DATA_W{1'b0}};
    wire [CW-1:0]     zeroize_encoded_cw;

    ecc_enc #(
        .DATA_W(DATA_W),
        .CHK_W (CHK_W),
        .CW_W  (CW)
    ) z_enc (
        .data(zeroize_data_byte),
        .code(zeroize_encoded_cw)
    );

    // RAM Control signal muxing
    assign zeroize_we   = (state == S_WRITE_PASS);
    assign zeroize_addr = (state == S_WRITE_PASS) ? w_cnt[AW-1:0] :
                          (state == S_VERIFY_RUN)  ? v_cnt[AW-1:0] : {AW{1'b0}};
    assign zeroize_din  = zeroize_encoded_cw;

    // -------------------------------------------------------------------------
    // 4. Dynamic ECC Decoder for Post-Wipe Hardware Verification
    // -------------------------------------------------------------------------
    wire [DATA_W-1:0] v_data;
    wire [CW-1:0]     v_code_cor;
    wire [1:0]        v_err_wt;
    wire              v_uncorr;
    wire              v_single_err;
    wire              v_double_err;
    wire              v_corr_err;
    wire [CHK_W-1:0]  v_syn;

    ecc_dec #(
        .DATA_W(DATA_W),
        .CHK_W (CHK_W),
        .CW_W  (CW),
        .T_ERR (2)
    ) verify_dec (
        .code          (ram_rdata),
        .data_corrected(v_data),
        .code_corrected(v_code_cor),
        .error_weight  (v_err_wt),
        .uncorrectable (v_uncorr),
        .single_err    (v_single_err),
        .double_err    (v_double_err),
        .corrected_err (v_corr_err),
        .syndrome      (v_syn)
    );

    // -------------------------------------------------------------------------
    // 5. Dual Counter Invariant Checking Logic
    // -------------------------------------------------------------------------
    // Invariant: At every address sweep step, w_cnt + w_down_cnt MUST equal (2^AW - 1).
    // For AW=8: 8'h00 + 8'hFF = 8'hFF, 8'h01 + 8'hFE = 8'hFF, ..., 8'hFF + 8'h00 = 8'hFF.
    wire [AW-1:0] max_addr = {AW{1'b1}};
    wire write_counter_match  = ((w_cnt[AW-1:0] + w_down_cnt[AW-1:0]) == max_addr);
    wire verify_counter_match = ((v_cnt[AW-1:0] + v_down_cnt[AW-1:0]) == max_addr);

    // -------------------------------------------------------------------------
    // 6. Zeroization Execution Engine FSM & Dual Counter Updates
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst || zeroize_clear) begin
            state                 <= S_IDLE;
            pass_cnt              <= 2'd0;
            w_cnt                 <= 9'd0;
            w_down_cnt            <= {1'b0, {AW{1'b1}}};
            v_cnt                 <= 9'd0;
            v_down_cnt            <= {1'b0, {AW{1'b1}}};
            zeroize_busy          <= 1'b0;
            zeroize_done_r0       <= 1'b0;
            zeroize_done_r1       <= 1'b0;
            zeroize_done_r2       <= 1'b0;
            zeroize_fail          <= 1'b0;
            zeroize_counter_fault <= 1'b0;
        end else begin
            // Invariant check during active sweeps
            if (state == S_WRITE_PASS && !write_counter_match) begin
                zeroize_counter_fault <= 1'b1;
            end else if (state == S_VERIFY_RUN && v_cnt > 9'd0 && v_cnt < (1 << AW) && !verify_counter_match) begin
                zeroize_counter_fault <= 1'b1;
            end

            case (state)
                S_IDLE: begin
                    zeroize_done_r0 <= 1'b0;
                    zeroize_done_r1 <= 1'b0;
                    zeroize_done_r2 <= 1'b0;
                    if (tamper || tamper_voted) begin
                        zeroize_busy          <= 1'b1;
                        zeroize_fail          <= 1'b0;
                        zeroize_counter_fault <= 1'b0;
                        pass_cnt              <= 2'd0;
                        w_cnt                 <= 9'd0;
                        w_down_cnt            <= {1'b0, {AW{1'b1}}};
                        v_cnt                 <= 9'd0;
                        v_down_cnt            <= {1'b0, {AW{1'b1}}};
                        state                 <= S_WRITE_PASS;
                    end
                end

                S_WRITE_PASS: begin
                    if (w_cnt == (1 << AW) - 1) begin
                        w_cnt      <= 9'd0;
                        w_down_cnt <= {1'b0, {AW{1'b1}}};
                        if (pass_cnt == (PASSES - 1)) begin
                            // Finished all overwrite passes, transition directly to verification
                            v_cnt      <= 9'd0;
                            v_down_cnt <= {1'b0, {AW{1'b1}}};
                            state      <= S_VERIFY_RUN;
                        end else begin
                            pass_cnt <= pass_cnt + 2'd1;
                        end
                    end else begin
                        w_cnt      <= w_cnt + 1'b1;
                        // Down-counter counts down; fault injection allows testing safety trip
                        if (zeroize_fault_inject) begin
                            w_down_cnt <= w_down_cnt ^ 9'h001; // Corrupt down counter
                        end else begin
                            w_down_cnt <= w_down_cnt - 1'b1;
                        end
                    end
                end

                S_VERIFY_RUN: begin
                    // Evaluate previous read word:
                    // When v_cnt > 0, ram_rdata contains data from address (v_cnt - 1)
                    if (v_cnt > 9'd0) begin
                        if ((v_data != {DATA_W{1'b0}}) || v_uncorr || (v_err_wt != 2'd0) || (ram_rdata != {CW{1'b0}})) begin
                            zeroize_fail <= 1'b1;
                        end
                    end

                    // Pipeline counter: increments from 0 to 256
                    if (v_cnt == (1 << AW)) begin
                        state           <= S_DONE;
                        zeroize_busy    <= 1'b0;
                        zeroize_done_r0 <= 1'b1;
                        zeroize_done_r1 <= 1'b1;
                        zeroize_done_r2 <= 1'b1;
                    end else begin
                        v_cnt      <= v_cnt + 1'b1;
                        v_down_cnt <= (v_down_cnt > 9'd0) ? (v_down_cnt - 1'b1) : 9'd0;
                    end
                end

                S_DONE: begin
                    zeroize_busy    <= 1'b0;
                    // Continual self-healing for done flag copies
                    zeroize_done_r0 <= zeroize_done_voted;
                    zeroize_done_r1 <= zeroize_done_voted;
                    zeroize_done_r2 <= zeroize_done_voted;
                    // Remains in S_DONE until master reset or zeroize_clear
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
