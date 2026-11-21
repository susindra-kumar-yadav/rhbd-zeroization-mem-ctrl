`timescale 1ns / 1ps
// =============================================================================
// File:        scrubber.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Autonomous Background Memory Scrubber with Parameterized CW
//              and DEC-TED Double-Error Correction Capabilities.
//
// Purpose in RHBD Systems:
//   In radiation environments, Single Event Upsets (SEUs) accumulate over time.
//   The scrubber periodically visits every memory address during IDLE cycles,
//   identifies 1-bit and 2-bit SEUs, and autonomously writes back the repaired
//   codeword, preventing latent faults from accumulating beyond the T=2 capacity.
//
// Features & Enhancements (Phase 1):
//   - Fully parameterized codeword width CW (default 18 for DEC-TED).
//   - Uses ecc_dec to correct all errors of weight <= T_ERR (T_ERR = 2).
//   - Performs autonomous write-back for both 1-bit and 2-bit correctable errors.
//   - Flags uncorrectable errors (> 2 bits).
//   - Yields immediately to host requests (pause_req) with zero host starvation.
// =============================================================================

module scrubber #(
    parameter AW             = 8,
    parameter DATA_W         = 8,
    parameter CHK_W          = 10,
    parameter CW             = 18,
    parameter DW             = CW,
    parameter SCRUB_INTERVAL = 16,
    parameter T_ERR          = 2
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          fsm_idle,
    input  wire          pause_req,
    input  wire          scrub_grant,
    input  wire [CW-1:0] ram_rdata,

    output reg           scrub_req,
    output reg  [AW-1:0] scrub_addr,
    output reg           scrub_we,
    output reg  [CW-1:0] scrub_din,
    output reg           scrub_single_err,
    output reg           scrub_double_err,
    output reg           scrub_corrected_err,
    output reg           scrub_uncorrectable_err,
    output reg  [15:0]   corrected_count,
    output reg  [15:0]   uncorrectable_count,
    output reg           scrub_sweep_done
);

    // Scrubber FSM States
    localparam [2:0]
        SC_IDLE       = 3'd0,
        SC_REQ        = 3'd1,
        SC_READ_WAIT  = 3'd2,
        SC_CHECK      = 3'd3,
        SC_WRITE_BACK = 3'd4;

    reg [2:0]  state;
    reg [31:0] idle_timer;

    // -------------------------------------------------------------------------
    // Dynamic ECC Decoder for Scrubbing Inspection
    // -------------------------------------------------------------------------
    wire [DATA_W-1:0] dec_data;
    wire [CW-1:0]     dec_code_cor;
    wire [1:0]        dec_err_wt;
    wire              dec_uncorr;
    wire              dec_single_err;
    wire              dec_double_err;
    wire              dec_corr_err;
    wire [CHK_W-1:0]  dec_syn;

    ecc_dec #(
        .DATA_W(DATA_W),
        .CHK_W (CHK_W),
        .CW_W  (CW),
        .T_ERR (T_ERR)
    ) sc_dec (
        .code          (ram_rdata),
        .data_corrected(dec_data),
        .code_corrected(dec_code_cor),
        .error_weight  (dec_err_wt),
        .uncorrectable (dec_uncorr),
        .single_err    (dec_single_err),
        .double_err    (dec_double_err),
        .corrected_err (dec_corr_err),
        .syndrome      (dec_syn)
    );

    always @(posedge clk) begin
        if (rst) begin
            state                   <= SC_IDLE;
            idle_timer              <= 32'd0;
            scrub_req               <= 1'b0;
            scrub_addr              <= {AW{1'b0}};
            scrub_we                <= 1'b0;
            scrub_din               <= {CW{1'b0}};
            scrub_single_err        <= 1'b0;
            scrub_double_err        <= 1'b0;
            scrub_corrected_err     <= 1'b0;
            scrub_uncorrectable_err <= 1'b0;
            corrected_count         <= 16'd0;
            uncorrectable_count     <= 16'd0;
            scrub_sweep_done        <= 1'b0;
        end else begin
            // Default single-cycle pulse resets
            scrub_single_err        <= 1'b0;
            scrub_double_err        <= 1'b0;
            scrub_corrected_err     <= 1'b0;
            scrub_uncorrectable_err <= 1'b0;
            scrub_sweep_done        <= 1'b0;
            scrub_we                <= 1'b0;

            // Immediate Preemption: Yield to host requests or tamper at any time
            if (pause_req) begin
                scrub_req  <= 1'b0;
                idle_timer <= 32'd0;
                state      <= SC_IDLE;
            end else begin
                case (state)
                    SC_IDLE: begin
                        scrub_req <= 1'b0;
                        if (fsm_idle) begin
                            if (idle_timer >= SCRUB_INTERVAL - 1) begin
                                idle_timer <= 32'd0;
                                scrub_req  <= 1'b1;
                                state      <= SC_REQ;
                            end else begin
                                idle_timer <= idle_timer + 1'b1;
                            end
                        end else begin
                            idle_timer <= 32'd0;
                        end
                    end

                    SC_REQ: begin
                        // Wait for central FSM to acknowledge and enter SCRUB state
                        if (scrub_grant) begin
                            state <= SC_READ_WAIT;
                        end
                    end

                    SC_READ_WAIT: begin
                        // RAM registered read latency: data is available on the next cycle
                        state <= SC_CHECK;
                    end

                    SC_CHECK: begin
                        if (dec_corr_err) begin
                            // Correctable SEU (weight 1 or 2) detected -> Initiate in-situ write-back
                            scrub_we            <= 1'b1;
                            scrub_din           <= dec_code_cor;
                            scrub_corrected_err <= 1'b1;
                            if (dec_err_wt == 2'd1) scrub_single_err <= 1'b1;
                            if (dec_err_wt == 2'd2) scrub_double_err <= 1'b1;
                            corrected_count     <= corrected_count + 1'b1;
                            state               <= SC_WRITE_BACK;
                        end else begin
                            if (dec_uncorr) begin
                                scrub_uncorrectable_err <= 1'b1;
                                uncorrectable_count     <= uncorrectable_count + 1'b1;
                            end
                            // Advance to next address
                            if (scrub_addr == {AW{1'b1}}) begin
                                scrub_addr       <= {AW{1'b0}};
                                scrub_sweep_done <= 1'b1;
                            end else begin
                                scrub_addr <= scrub_addr + 1'b1;
                            end
                            scrub_req <= 1'b0;
                            state     <= SC_IDLE;
                        end
                    end

                    SC_WRITE_BACK: begin
                        // In-situ write-back cycle completes
                        scrub_we <= 1'b0;
                        if (scrub_addr == {AW{1'b1}}) begin
                            scrub_addr       <= {AW{1'b0}};
                            scrub_sweep_done <= 1'b1;
                        end else begin
                            scrub_addr <= scrub_addr + 1'b1;
                        end
                        scrub_req <= 1'b0;
                        state     <= SC_IDLE;
                    end

                    default: state <= SC_IDLE;
                endcase
            end
        end
    end

endmodule
