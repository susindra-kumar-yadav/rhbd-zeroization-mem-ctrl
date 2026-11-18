`timescale 1ns / 1ps
// =============================================================================
// File:        mem_ctrl_fsm.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Central Memory Controller Finite State Machine with Triple
//              Modular Redundancy (TMR) Self-Healing State Protection.
//
// State Encoding Choice:
//   3-bit Gray code is selected:
//     - Minimizes Hamming distance (single-bit transitions) between consecutive
//       states, reducing dynamic power and glitch-induced Single Event Upsets (SEUs).
//     - Compact width allows direct bitwise TMR voting and low gate count.
//
// TMR Architecture:
//   - 3 separate physical state registers: state_r0, state_r1, state_r2.
//   - tmr_voter continuously computes majority vote (state_voted).
//   - Next-state logic is evaluated strictly using state_voted.
//   - Every clock edge, all three copies are rewritten with the voted next state.
//     If an SEU flips one copy, it is automatically repaired on the next clock edge!
//   - tmr_fix_count logs every clock cycle in which a mismatch was healed.
//   - fsm_fault_inject[2:0] flips state_r0, state_r1, or state_r2 for demonstration.
//
// Priority Hierarchy:
//   1. ZEROIZE (tamper event) -> highest priority (blocks all host transactions).
//   2. Host Write / Read.
//   3. Background Autonomous Scrubbing.
// =============================================================================

module mem_ctrl_fsm #(
    parameter AW = 8,
    parameter DW = 13
)(
    input  wire          clk,
    input  wire          rst,

    // Host Request Interface
    input  wire          req_wr,
    input  wire          req_rd,
    input  wire [AW-1:0] host_addr,
    input  wire [7:0]    host_wdata,
    output reg  [7:0]    host_rdata,
    output reg           rdata_valid,
    output wire          busy,

    // Security & Scrubbing Handshakes
    input  wire          tamper,
    input  wire          zeroize_busy,
    input  wire          zeroize_done,
    input  wire          scrub_req,
    output wire          scrub_grant,

    // TMR Fault Injection & Monitoring
    input  wire [2:0]    fsm_fault_inject,
    output wire          state_mismatch,
    output reg  [15:0]   tmr_fix_count,
    output wire [2:0]    current_state,

    // RAM Control Interface (Host path)
    output reg  [AW-1:0] fsm_ram_addr,
    output reg           fsm_ram_we,
    output reg  [DW-1:0] fsm_ram_din,
    input  wire [DW-1:0] ram_dout,

    // Error Reporting
    output reg           single_err_seen,
    output reg           double_err_seen
);

    // -------------------------------------------------------------------------
    // Gray Code State Definitions
    // -------------------------------------------------------------------------
    localparam [2:0]
        ST_IDLE       = 3'b000,
        ST_WRITE      = 3'b001,
        ST_READ_WAIT  = 3'b011,
        ST_READ_DONE  = 3'b010,
        ST_SCRUB      = 3'b110,
        ST_ZEROIZE    = 3'b111,
        ST_LOCKED_ERR = 3'b101;

    // -------------------------------------------------------------------------
    // TMR Triplicated State Registers & Majority Voter
    // -------------------------------------------------------------------------
    reg [2:0] state_r0;
    reg [2:0] state_r1;
    reg [2:0] state_r2;

    wire [2:0] state_voted;
    wire       mismatch_detected;

    tmr_voter #(.WIDTH(3)) fsm_voter_inst (
        .a       (state_r0),
        .b       (state_r1),
        .c       (state_r2),
        .y       (state_voted),
        .mismatch(mismatch_detected)
    );

    assign state_mismatch = mismatch_detected;
    assign current_state  = state_voted;

    // Latch tamper input so a fast pulse is never missed
    reg tamper_latch;
    always @(posedge clk) begin
        if (rst) begin
            tamper_latch <= 1'b0;
        end else if (tamper) begin
            tamper_latch <= 1'b1;
        end
    end

    // System is busy whenever performing any operation or zeroizing
    assign busy = (state_voted != ST_IDLE) || tamper_latch || zeroize_busy || zeroize_done;
    assign scrub_grant = (state_voted == ST_SCRUB);

    // -------------------------------------------------------------------------
    // SECDED Encoder (for Host Write Path)
    // -------------------------------------------------------------------------
    wire [12:0] host_encoded_code;
    hamming_secded_enc host_enc (
        .data(host_wdata),
        .code(host_encoded_code)
    );

    // -------------------------------------------------------------------------
    // SECDED Decoder (for Host Read Path)
    // -------------------------------------------------------------------------
    wire [7:0]  dec_data_corr;
    wire        dec_single_err;
    wire        dec_double_err;
    wire [3:0]  dec_syndrome;
    wire [12:0] dec_code_corr;

    hamming_secded_dec host_dec (
        .code          (ram_dout),
        .data_corrected(dec_data_corr),
        .single_err    (dec_single_err),
        .double_err    (dec_double_err),
        .syndrome      (dec_syndrome),
        .code_corrected(dec_code_corr)
    );

    // Latched request parameters
    reg [AW-1:0] latched_addr;
    reg [12:0]   latched_wcode;

    // -------------------------------------------------------------------------
    // Combinational Next-State Logic (Evaluated strictly on state_voted)
    // -------------------------------------------------------------------------
    reg [2:0] state_next;

    always @(*) begin
        state_next = state_voted;
        case (state_voted)
            ST_IDLE: begin
                if (tamper || tamper_latch || zeroize_busy) begin
                    state_next = ST_ZEROIZE;
                end else if (zeroize_done) begin
                    state_next = ST_IDLE; // Blocked until reset
                end else if (req_wr) begin
                    state_next = ST_WRITE;
                end else if (req_rd) begin
                    state_next = ST_READ_WAIT;
                end else if (scrub_req) begin
                    state_next = ST_SCRUB;
                end else begin
                    state_next = ST_IDLE;
                end
            end

            ST_WRITE: begin
                if (tamper || tamper_latch || zeroize_busy) begin
                    state_next = ST_ZEROIZE;
                end else begin
                    state_next = ST_IDLE;
                end
            end

            ST_READ_WAIT: begin
                if (tamper || tamper_latch || zeroize_busy) begin
                    state_next = ST_ZEROIZE;
                end else begin
                    state_next = ST_READ_DONE;
                end
            end

            ST_READ_DONE: begin
                if (tamper || tamper_latch || zeroize_busy) begin
                    state_next = ST_ZEROIZE;
                end else if (dec_double_err) begin
                    state_next = ST_LOCKED_ERR; // Lock controller on uncorrectable multi-bit fault
                end else begin
                    state_next = ST_IDLE;
                end
            end

            ST_SCRUB: begin
                if (tamper || tamper_latch || zeroize_busy) begin
                    state_next = ST_ZEROIZE;
                end else if (req_wr || req_rd || !scrub_req) begin
                    state_next = ST_IDLE; // Yield immediately to host requests or upon completion
                end else begin
                    state_next = ST_SCRUB;
                end
            end

            ST_ZEROIZE: begin
                // Remain in ZEROIZE state until zeroize engine finishes
                if (!zeroize_busy && zeroize_done) begin
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_ZEROIZE;
                end
            end

            ST_LOCKED_ERR: begin
                // Uncorrectable error lock: stays locked unless zeroize/tamper is invoked
                if (tamper || tamper_latch || zeroize_busy) begin
                    state_next = ST_ZEROIZE;
                end else begin
                    state_next = ST_LOCKED_ERR;
                end
            end

            default: state_next = ST_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Synchronous TMR State Update, Self-Healing & Fault Injection
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state_r0      <= ST_IDLE;
            state_r1      <= ST_IDLE;
            state_r2      <= ST_IDLE;
            tmr_fix_count <= 16'd0;
        end else begin
            // Increment TMR fix counter whenever an SEU causes a copy mismatch
            if (mismatch_detected) begin
                tmr_fix_count <= tmr_fix_count + 1'b1;
            end

            // Self-healing: Every cycle, all three copies are rewritten with the
            // voted next state. Fault injection bits simulate radiation upsets by
            // flipping bit 0 of the targeted copy for that clock edge.
            state_r0 <= (fsm_fault_inject[0]) ? (state_next ^ 3'b001) : state_next;
            state_r1 <= (fsm_fault_inject[1]) ? (state_next ^ 3'b001) : state_next;
            state_r2 <= (fsm_fault_inject[2]) ? (state_next ^ 3'b001) : state_next;
        end
    end

    // -------------------------------------------------------------------------
    // Datapath & RAM Control Logic
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            host_rdata      <= 8'h00;
            rdata_valid     <= 1'b0;
            single_err_seen <= 1'b0;
            double_err_seen <= 1'b0;
            latched_addr    <= {AW{1'b0}};
            latched_wcode   <= {DW{1'b0}};
            fsm_ram_we      <= 1'b0;
            fsm_ram_addr    <= {AW{1'b0}};
            fsm_ram_din     <= {DW{1'b0}};
        end else begin
            // Default single-cycle pulse resets
            rdata_valid     <= 1'b0;
            single_err_seen <= 1'b0;
            double_err_seen <= 1'b0;
            fsm_ram_we      <= 1'b0;

            case (state_voted)
                ST_IDLE: begin
                    if (!busy && req_wr) begin
                        latched_addr  <= host_addr;
                        latched_wcode <= host_encoded_code;
                        fsm_ram_we    <= 1'b1;
                        fsm_ram_addr  <= host_addr;
                        fsm_ram_din   <= host_encoded_code;
                    end else if (!busy && req_rd) begin
                        latched_addr <= host_addr;
                        fsm_ram_we   <= 1'b0;
                        fsm_ram_addr <= host_addr;
                    end
                end

                ST_WRITE: begin
                    // Write was asserted during IDLE -> WRITE transition; release WE
                    fsm_ram_we <= 1'b0;
                end

                ST_READ_WAIT: begin
                    // Address held for RAM synchronous read latency
                    fsm_ram_we   <= 1'b0;
                    fsm_ram_addr <= latched_addr;
                end

                ST_READ_DONE: begin
                    // Data is valid on RAM dout
                    host_rdata  <= dec_data_corr;
                    rdata_valid <= 1'b1;

                    if (dec_single_err) begin
                        single_err_seen <= 1'b1;
                        // Autonomous write-back of corrected SECDED codeword to memory
                        fsm_ram_we   <= 1'b1;
                        fsm_ram_addr <= latched_addr;
                        fsm_ram_din  <= dec_code_corr;
                    end else if (dec_double_err) begin
                        double_err_seen <= 1'b1;
                    end
                end

                default: begin
                    fsm_ram_we <= 1'b0;
                end
            endcase
        end
    end

endmodule

