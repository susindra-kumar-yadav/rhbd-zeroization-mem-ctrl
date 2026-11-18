`timescale 1ns / 1ps
// =============================================================================
// File:        scrubber.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Autonomous Background Memory Scrubber.
//
// Purpose in RHBD Systems:
//   In radiation environments (space, high altitude, nuclear facilities),
//   Single Event Upsets (SEUs) accumulate over time. If a second SEU hits
//   a word before the first is corrected, it becomes an uncorrectable double-bit
//   error. The autonomous scrubber periodically visits every memory address,
//   identifies single-bit faults, and writes back the clean SECDED codeword,
//   preventing latent single-bit errors from accumulating into double-bit faults.
//
// Operation:
//   - Triggers when the memory controller is IDLE for SCRUB_INTERVAL cycles.
//   - Immediately pauses and yields bus priority if a host request or tamper
//     event arrives (zero host-starvation).
//   - Preserves scrub pointer so scanning resumes where it left off.
//   - Tracks corrected_count (single errors repaired) and uncorrectable_count.
// =============================================================================

module scrubber #(
    parameter AW             = 8,
    parameter DW             = 13,
    parameter SCRUB_INTERVAL = 16
)(
    input  wire          clk,
    input  wire          rst,
    input  wire          fsm_idle,
    input  wire          pause_req,
    input  wire          scrub_grant,
    input  wire [DW-1:0] ram_rdata,

    output reg           scrub_req,
    output reg  [AW-1:0] scrub_addr,
    output reg           scrub_we,
    output reg  [DW-1:0] scrub_din,
    output reg           scrub_single_err,
    output reg           scrub_double_err,
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

    // SECDED Decoder for scrubbing inspection
    wire [7:0]  dec_data;
    wire        dec_single_err;
    wire        dec_double_err;
    wire [3:0]  dec_syn;
    wire [12:0] dec_code_cor;

    hamming_secded_dec sc_dec (
        .code          (ram_rdata),
        .data_corrected(dec_data),
        .single_err    (dec_single_err),
        .double_err    (dec_double_err),
        .syndrome      (dec_syn),
        .code_corrected(dec_code_cor)
    );

    always @(posedge clk) begin
        if (rst) begin
            state               <= SC_IDLE;
            idle_timer          <= 32'd0;
            scrub_req           <= 1'b0;
            scrub_addr          <= {AW{1'b0}};
            scrub_we            <= 1'b0;
            scrub_din           <= {DW{1'b0}};
            scrub_single_err    <= 1'b0;
            scrub_double_err    <= 1'b0;
            corrected_count     <= 16'd0;
            uncorrectable_count <= 16'd0;
            scrub_sweep_done    <= 1'b0;
        end else begin
            // Default single-cycle pulse resets
            scrub_single_err <= 1'b0;
            scrub_double_err <= 1'b0;
            scrub_sweep_done <= 1'b0;
            scrub_we         <= 1'b0;

            // Immediate Preemption: Yield to host or tamper at any time
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
                        if (dec_single_err) begin
                            // Single error detected -> Initiate autonomous write-back
                            scrub_we         <= 1'b1;
                            scrub_din        <= dec_code_cor;
                            scrub_single_err <= 1'b1;
                            corrected_count  <= corrected_count + 1'b1;
                            state            <= SC_WRITE_BACK;
                        end else begin
                            if (dec_double_err) begin
                                scrub_double_err    <= 1'b1;
                                uncorrectable_count <= uncorrectable_count + 1'b1;
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
                        // Write-back cycle completes
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

