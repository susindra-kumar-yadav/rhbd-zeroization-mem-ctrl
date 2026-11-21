`timescale 1ns / 1ps
// =============================================================================
// File:        rhbd_mem_top.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Top-Level Integration of Radiation-Hardened Memory Controller
//              with DEC-TED (T=2) Memory ECC, Triplicated Voters, Per-Copy SECDED
//              FSM State Protection, Autonomous Watchdog, and Military Anti-Tamper Zeroize.
//
// Submodules Integrated:
//   1. ecc_ram           : Parameterized CW-bit SRAM with physical SEU fault injection.
//   2. mem_ctrl_fsm      : Hardened TMR FSM with per-copy SECDED [7,3,4] state registers,
//                          triplicated voters, illegal state trap, transition checker,
//                          watchdog timer, and lock_clear recovery.
//   3. scrubber          : Autonomous background scrub engine repairing 1-bit and 2-bit SEUs.
//   4. zeroize_engine    : Multi-pass military wipe & verification engine with dual
//                          complementary counter invariant checks and triple-redundant done/tamper.
//
// Ports:
//   - clk, rst                   : System clock and synchronous active-high reset.
//   - req_wr, req_rd             : Host write / read strobe requests.
//   - host_addr, host_wdata      : Host memory address and data payload.
//   - host_rdata, rdata_valid    : Corrected read data and 1-cycle valid strobe.
//   - busy                       : System busy flag (rejects requests during wipe/ops/lockout).
//   - tamper                     : External tamper sensor trigger (initiates zeroize).
//   - lock_clear                 : Clears locked error state, restoring FSM to IDLE without data loss.
//   - Fault Injection Interfaces : inject_en/mask (RAM SEU), fsm_fault_inject / fsm_code_inject (FSM),
//                                  voter_fault_inject, tamper_fault_inject, zeroize_fault_inject.
//   - Health & Telemetry Status  : corrected_err_seen, uncorrectable_err_seen, single_err_seen,
//                                  double_err_seen, tmr_mismatch, tmr_no_majority, tmr_illegal_state,
//                                  tmr_bad_transition, fsm_degraded, fsm_locked, watchdog_timeout,
//                                  zeroize_counter_fault, zeroize_busy, zeroize_done, zeroize_fail,
//                                  corrected_count, uncorrectable_count.
// =============================================================================

module rhbd_mem_top #(
    parameter DW_DATA        = 8,
    parameter AW             = 8,
    parameter CHK_W          = 10,
    parameter CW             = 18,
    parameter DW             = CW,
    parameter SCRUB_INTERVAL = 16,
    parameter PASSES         = 3,
    parameter T_ERR          = 2,
    parameter T_STATE        = 2,
    parameter CHK_STATE      = (T_STATE == 1) ? 4 : 8,
    parameter CW_STATE       = 3 + CHK_STATE,
    parameter WATCHDOG_LIMIT = 256
)(
    input  wire                 clk,
    input  wire                 rst,

    // Host Memory Interface
    input  wire                 req_wr,
    input  wire                 req_rd,
    input  wire [AW-1:0]        host_addr,
    input  wire [DW_DATA-1:0]   host_wdata,
    output wire [DW_DATA-1:0]   host_rdata,
    output wire                 rdata_valid,
    output wire                 busy,

    // Security & Anti-Tamper
    input  wire                 tamper,
    input  wire                 lock_clear,

    // Fault Injection Interfaces (for Validation & Viva Demonstrations)
    input  wire                 inject_en,
    input  wire [AW-1:0]        inject_addr,
    input  wire [CW-1:0]        inject_mask,
    input  wire [2:0]           fsm_fault_inject,
    input  wire [CW_STATE-1:0]  fsm_code_inject0,
    input  wire [CW_STATE-1:0]  fsm_code_inject1,
    input  wire [CW_STATE-1:0]  fsm_code_inject2,
    input  wire [2:0]           voter_fault_inject,
    input  wire [2:0]           tamper_fault_inject,
    input  wire                 zeroize_fault_inject,

    // Health, Telemetry & Hardened Status Outputs
    output wire                 corrected_err_seen,
    output wire                 uncorrectable_err_seen,
    output wire                 single_err_seen,
    output wire                 double_err_seen,
    output wire                 copy_corrected_0,
    output wire                 copy_corrected_1,
    output wire                 copy_corrected_2,
    output wire                 copy_bad_0,
    output wire                 copy_bad_1,
    output wire                 copy_bad_2,
    output wire                 tmr_mismatch,
    output wire                 tmr_no_majority,
    output wire                 tmr_illegal_state,
    output wire                 tmr_bad_transition,
    output wire                 fsm_degraded,
    output wire                 fsm_locked,
    output wire                 watchdog_timeout,
    output wire                 zeroize_counter_fault,
    output wire                 zeroize_busy,
    output wire                 zeroize_done,
    output wire                 zeroize_fail,
    output reg  [15:0]          corrected_count,
    output reg  [15:0]          uncorrectable_count
);

    // -------------------------------------------------------------------------
    // Internal Interconnect Signals
    // -------------------------------------------------------------------------
    // RAM Interface
    reg           ram_we;
    reg  [AW-1:0] ram_addr;
    reg  [CW-1:0] ram_din;
    wire [CW-1:0] ram_dout;

    // FSM <-> RAM Signals
    wire [AW-1:0] fsm_ram_addr;
    wire          fsm_ram_we;
    wire [CW-1:0] fsm_ram_din;
    wire [2:0]    fsm_state;
    wire          fsm_single_err;
    wire          fsm_double_err;
    wire          fsm_corr_err;
    wire          fsm_uncorr_err;
    wire          fsm_tmr_mismatch;
    wire [15:0]   tmr_fix_count;

    // Zeroize <-> RAM Signals
    wire          zero_we;
    wire [AW-1:0] zero_addr;
    wire [CW-1:0] zero_din;
    wire          zero_busy;
    wire          zero_done;
    wire          zero_fail;
    wire          zero_counter_fault;

    // Scrubber <-> RAM Signals
    wire          scrub_req;
    wire          scrub_grant;
    wire [AW-1:0] scrub_addr;
    wire          scrub_we;
    wire [CW-1:0] scrub_din;
    wire          scrub_single_err;
    wire          scrub_double_err;
    wire          scrub_corr_err;
    wire          scrub_uncorr_err;
    wire [15:0]   scrub_corr_cnt;
    wire [15:0]   scrub_uncorr_cnt;
    wire          scrub_sweep_done;

    // Status assignments
    assign zeroize_busy           = zero_busy;
    assign zeroize_done           = zero_done;
    assign zeroize_fail           = zero_fail;
    assign zeroize_counter_fault  = zero_counter_fault;
    assign tmr_mismatch           = fsm_tmr_mismatch;
    assign single_err_seen        = fsm_single_err | scrub_single_err;
    assign double_err_seen        = fsm_double_err | scrub_double_err;
    assign corrected_err_seen     = fsm_corr_err   | scrub_corr_err;
    assign uncorrectable_err_seen = fsm_uncorr_err | scrub_uncorr_err;

    // Error Counters: Combined logging across both Host and Background Scrubber
    always @(posedge clk) begin
        if (rst) begin
            corrected_count     <= 16'd0;
            uncorrectable_count <= 16'd0;
        end else begin
            if (corrected_err_seen) begin
                corrected_count <= corrected_count + 1'b1;
            end
            if (uncorrectable_err_seen) begin
                uncorrectable_count <= uncorrectable_count + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // RAM Bus Arbiter (Strict Priority Hierarchy)
    // -------------------------------------------------------------------------
    // 1. Fault Injection: overrides memory address when inject_en is active
    // 2. Zeroize Engine: overrides all when tamper occurs
    // 3. Scrubber: active when FSM grants SCRUB state
    // 4. Host FSM: handles normal host reads, writes, and write-backs
    always @(*) begin
        if (inject_en) begin
            ram_we   = 1'b0;
            ram_addr = inject_addr;
            ram_din  = {CW{1'b0}};
        end else if (zero_busy || (fsm_state == 3'b111)) begin // ST_ZEROIZE
            ram_we   = zero_we;
            ram_addr = zero_addr;
            ram_din  = zero_din;
        end else if (fsm_state == 3'b110) begin                // ST_SCRUB
            ram_we   = scrub_we;
            ram_addr = scrub_addr;
            ram_din  = scrub_din;
        end else begin                                         // Host Path (IDLE, WRITE, READ)
            ram_we   = fsm_ram_we;
            ram_addr = fsm_ram_addr;
            ram_din  = fsm_ram_din;
        end
    end

    // -------------------------------------------------------------------------
    // Instantiate Core ECC RAM (CW-bit width x 256 depth)
    // -------------------------------------------------------------------------
    ecc_ram #(
        .CW(CW),
        .DW(DW),
        .AW(AW)
    ) ram_inst (
        .clk        (clk),
        .we         (ram_we),
        .addr       (ram_addr),
        .din        (ram_din),
        .dout       (ram_dout),
        .inject_en  (inject_en),
        .inject_mask(inject_mask)
    );

    // -------------------------------------------------------------------------
    // Instantiate Hardened TMR-Protected Memory Controller FSM
    // -------------------------------------------------------------------------
    mem_ctrl_fsm #(
        .AW            (AW),
        .DATA_W        (DW_DATA),
        .CHK_W         (CHK_W),
        .CW            (CW),
        .DW            (DW),
        .T_ERR         (T_ERR),
        .T_STATE       (T_STATE),
        .CHK_STATE     (CHK_STATE),
        .CW_STATE      (CW_STATE),
        .WATCHDOG_LIMIT(WATCHDOG_LIMIT)
    ) fsm_inst (
        .clk                   (clk),
        .rst                   (rst),
        .req_wr                (req_wr),
        .req_rd                (req_rd),
        .host_addr             (host_addr),
        .host_wdata            (host_wdata),
        .host_rdata            (host_rdata),
        .rdata_valid           (rdata_valid),
        .busy                  (busy),
        .tamper                (tamper),
        .zeroize_busy          (zero_busy),
        .zeroize_done          (zero_done),
        .scrub_req             (scrub_req),
        .scrub_grant           (scrub_grant),
        .lock_clear            (lock_clear),
        .fsm_stall             (1'b0),
        .fsm_fault_inject      (fsm_fault_inject),
        .fsm_code_inject0      (fsm_code_inject0),
        .fsm_code_inject1      (fsm_code_inject1),
        .fsm_code_inject2      (fsm_code_inject2),
        .voter_fault_inject    (voter_fault_inject),
        .tamper_fault_inject   (tamper_fault_inject),
        .state_mismatch        (fsm_tmr_mismatch),
        .tmr_fix_count         (tmr_fix_count),
        .current_state         (fsm_state),
        .copy_corrected_0      (copy_corrected_0),
        .copy_corrected_1      (copy_corrected_1),
        .copy_corrected_2      (copy_corrected_2),
        .copy_bad_0            (copy_bad_0),
        .copy_bad_1            (copy_bad_1),
        .copy_bad_2            (copy_bad_2),
        .tmr_no_majority       (tmr_no_majority),
        .tmr_illegal_state     (tmr_illegal_state),
        .tmr_bad_transition    (tmr_bad_transition),
        .fsm_degraded          (fsm_degraded),
        .fsm_locked            (fsm_locked),
        .watchdog_timeout      (watchdog_timeout),
        .fsm_ram_addr          (fsm_ram_addr),
        .fsm_ram_we            (fsm_ram_we),
        .fsm_ram_din           (fsm_ram_din),
        .ram_dout              (ram_dout),
        .single_err_seen       (fsm_single_err),
        .double_err_seen       (fsm_double_err),
        .corrected_err_seen    (fsm_corr_err),
        .uncorrectable_err_seen(fsm_uncorr_err)
    );

    // -------------------------------------------------------------------------
    // Instantiate Autonomous Background Scrubber
    // -------------------------------------------------------------------------
    wire pause_scrubber = req_wr | req_rd | tamper | zero_busy | fsm_locked;

    scrubber #(
        .AW            (AW),
        .DATA_W        (DW_DATA),
        .CHK_W         (CHK_W),
        .CW            (CW),
        .DW            (DW),
        .SCRUB_INTERVAL(SCRUB_INTERVAL),
        .T_ERR         (T_ERR)
    ) scrubber_inst (
        .clk                    (clk),
        .rst                    (rst),
        .fsm_idle               (fsm_state == 3'b000), // ST_IDLE
        .pause_req              (pause_scrubber),
        .scrub_grant            (scrub_grant),
        .ram_rdata              (ram_dout),
        .scrub_req              (scrub_req),
        .scrub_addr             (scrub_addr),
        .scrub_we               (scrub_we),
        .scrub_din              (scrub_din),
        .scrub_single_err       (scrub_single_err),
        .scrub_double_err       (scrub_double_err),
        .scrub_corrected_err    (scrub_corr_err),
        .scrub_uncorrectable_err(scrub_uncorr_err),
        .corrected_count        (scrub_corr_cnt),
        .uncorrectable_count    (scrub_uncorr_cnt),
        .scrub_sweep_done       (scrub_sweep_done)
    );

    // -------------------------------------------------------------------------
    // Instantiate Secure Zeroization Engine
    // -------------------------------------------------------------------------
    zeroize_engine #(
        .AW    (AW),
        .DATA_W(DW_DATA),
        .CHK_W (CHK_W),
        .CW    (CW),
        .DW    (DW),
        .PASSES(PASSES)
    ) zeroize_inst (
        .clk                  (clk),
        .rst                  (rst),
        .tamper               (tamper),
        .zeroize_clear        (rst),
        .ram_rdata            (ram_dout),
        .tamper_fault_inject  (tamper_fault_inject[0]),
        .zeroize_fault_inject (zeroize_fault_inject),
        .zeroize_we           (zero_we),
        .zeroize_addr         (zero_addr),
        .zeroize_din          (zero_din),
        .zeroize_busy         (zero_busy),
        .zeroize_done         (zero_done),
        .zeroize_fail         (zero_fail),
        .zeroize_counter_fault(zero_counter_fault)
    );

endmodule
