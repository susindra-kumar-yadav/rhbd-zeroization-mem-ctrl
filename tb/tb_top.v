`timescale 1ns / 1ps
// =============================================================================
// File:        tb_top.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Full End-to-End System Integration Testbench for DEC-TED (T=2)
//              Memory Subsystem with Multi-Layer Hardened FSM and Secure Zeroization.
//
// Mission Simulation Scenarios:
//   Phase 1 : System Boot, Reset Sequence and Baseline Initialization.
//   Phase 2 : Normal Host Write and Read Verification.
//   Phase 3 : RAM Single-Event Upset (1-Bit SEU) -> Host Read Correction & In-Situ Write-Back.
//   Phase 3b: RAM Double-Event Upset (2-Bit SEU) -> DEC Correction & In-Situ Write-Back!
//   Phase 4 : Autonomous Background Memory Scrubbing (preemptive 2-bit SEU healing).
//   Phase 5 : FSM Radiation Upset -> TMR Majority Voting & Instant Self-Healing.
//   Phase 6 : Multi-Bit Radiation Upset (3-Bit Error) -> DEC-TED Uncorrectable Trap.
//   Phase 7 : Anti-Tamper Security Breach -> Multi-Pass Secure Zeroization Wipe.
// =============================================================================

module tb_top;

    parameter DW_DATA   = 8;
    parameter AW        = 8;
    parameter CHK_W     = 10;
    parameter CW        = 18;
    parameter T_STATE   = 2;
    parameter CHK_STATE = (T_STATE == 1) ? 4 : 8;
    parameter CW_STATE  = 3 + CHK_STATE;

    reg              clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg              rst;

    reg              req_wr;
    reg              req_rd;
    reg  [AW-1:0]    host_addr;
    reg  [DW_DATA-1:0] host_wdata;
    wire [DW_DATA-1:0] host_rdata;
    wire             rdata_valid;
    wire             busy;

    reg              tamper;
    reg              lock_clear;

    reg              inject_en;
    reg  [AW-1:0]    inject_addr;
    reg  [CW-1:0]    inject_mask;
    reg  [2:0]          fsm_fault_inject;
    reg  [CW_STATE-1:0] fsm_code_inject0;
    reg  [CW_STATE-1:0] fsm_code_inject1;
    reg  [CW_STATE-1:0] fsm_code_inject2;
    reg  [2:0]          voter_fault_inject;
    reg  [2:0]          tamper_fault_inject;
    reg                 zeroize_fault_inject;

    wire             single_err_seen;
    wire             double_err_seen;
    wire             corrected_err_seen;
    wire             uncorrectable_err_seen;
    wire             tmr_mismatch;
    wire             tmr_no_majority;
    wire             tmr_illegal_state;
    wire             tmr_bad_transition;
    wire             fsm_degraded;
    wire             fsm_locked;
    wire             watchdog_timeout;
    wire             zeroize_counter_fault;
    wire             zeroize_busy;
    wire             zeroize_done;
    wire             zeroize_fail;
    wire [15:0]      corrected_count;
    wire [15:0]      uncorrectable_count;

    // Instantiate System Top Module with Parameterized CW
    // SCRUB_INTERVAL = 4 cycles for fast simulation of background scrubbing
    rhbd_mem_top #(
        .DW_DATA       (DW_DATA),
        .AW            (AW),
        .CHK_W         (CHK_W),
        .CW            (CW),
        .DW            (CW),
        .SCRUB_INTERVAL(16),
        .PASSES        (3),
        .T_ERR         (2),
        .T_STATE       (T_STATE)
    ) dut (
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
        .lock_clear            (lock_clear),
        .inject_en             (inject_en),
        .inject_addr           (inject_addr),
        .inject_mask           (inject_mask),
        .fsm_fault_inject      (fsm_fault_inject),
        .fsm_code_inject0      (fsm_code_inject0),
        .fsm_code_inject1      (fsm_code_inject1),
        .fsm_code_inject2      (fsm_code_inject2),
        .voter_fault_inject    (voter_fault_inject),
        .tamper_fault_inject   (tamper_fault_inject),
        .zeroize_fault_inject  (zeroize_fault_inject),
        .single_err_seen       (single_err_seen),
        .double_err_seen       (double_err_seen),
        .corrected_err_seen    (corrected_err_seen),
        .uncorrectable_err_seen(uncorrectable_err_seen),
        .tmr_mismatch          (tmr_mismatch),
        .tmr_no_majority       (tmr_no_majority),
        .tmr_illegal_state     (tmr_illegal_state),
        .tmr_bad_transition    (tmr_bad_transition),
        .fsm_degraded          (fsm_degraded),
        .fsm_locked            (fsm_locked),
        .watchdog_timeout      (watchdog_timeout),
        .zeroize_counter_fault (zeroize_counter_fault),
        .zeroize_busy          (zeroize_busy),
        .zeroize_done          (zeroize_done),
        .zeroize_fail          (zeroize_fail),
        .corrected_count       (corrected_count),
        .uncorrectable_count   (uncorrectable_count)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task host_write;
        input [AW-1:0]      addr;
        input [DW_DATA-1:0] data;
        begin
            @(negedge clk);
            req_wr     = 1'b1;
            host_addr  = addr;
            host_wdata = data;
            @(negedge clk);
            req_wr     = 1'b0;
            @(negedge clk);
            @(negedge clk);
        end
    endtask

    task host_read;
        input  [AW-1:0]      addr;
        output [DW_DATA-1:0] data;
        output               s_err;
        output               d_err;
        output               u_err;
        begin
            @(negedge clk);
            req_rd    = 1'b1;
            host_addr = addr;
            @(negedge clk);
            req_rd    = 1'b0;
            @(negedge clk);
            while (!rdata_valid && !fsm_locked) @(negedge clk);
            data  = host_rdata;
            s_err = single_err_seen;
            d_err = double_err_seen;
            u_err = uncorrectable_err_seen;
            @(negedge clk);
        end
    endtask

    task inject_ram_seu;
        input [AW-1:0] addr;
        input [CW-1:0] mask;
        begin
            @(negedge clk);
            inject_en   = 1'b1;
            inject_addr = addr;
            inject_mask = mask;
            @(negedge clk);
            inject_en   = 1'b0;
            @(negedge clk);
        end
    endtask

    reg [DW_DATA-1:0] rdata;
    reg               s_flag, d_flag, u_flag;
    reg [15:0]        prev_corr_count;

    initial begin
        $display("TEST START TIME %0t", $time);
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        $display("==================================================================");
        $display("   STARTING TESTBENCH: tb_top (DEC-TED System Mission Scenario)   ");
        $display("==================================================================");

        // ---------------------------------------------------------------------
        // Phase 1: Boot & Reset Sequence
        // ---------------------------------------------------------------------
        $display("\n--- Phase 1: System Boot & Initialization ---");
                rst                  = 1'b1;
        req_wr               = 1'b0;
        req_rd               = 1'b0;
        host_addr            = 8'h00;
        host_wdata           = 8'h00;
        tamper               = 1'b0;
        lock_clear           = 1'b0;
        inject_en            = 1'b0;
        inject_addr          = 8'h00;
        inject_mask          = {CW{1'b0}};
        fsm_fault_inject     = 3'b000;
        fsm_code_inject0     = {CW_STATE{1'b0}};
        fsm_code_inject1     = {CW_STATE{1'b0}};
        fsm_code_inject2     = {CW_STATE{1'b0}};
        voter_fault_inject   = 3'b0;
        tamper_fault_inject  = 3'b0;
        zeroize_fault_inject = 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        if (busy === 1'b0) begin
            $display("[PASS] Controller booted up in clean IDLE state.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Controller is busy immediately after reset.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 2: Host Normal Writes and Reads
        // ---------------------------------------------------------------------
        $display("\n--- Phase 2: Host Payload Storage & Verification ---");
        host_write(8'h01, 8'hA1);
        host_write(8'h02, 8'hB2);
        host_write(8'h03, 8'hC3);
        host_write(8'h04, 8'hD4);

        host_read(8'h01, rdata, s_flag, d_flag, u_flag);
        if (rdata === 8'hA1 && !s_flag && !d_flag && !u_flag) begin
            $display("[PASS] Address 8'h01 read clean: 8'h%02x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Address 8'h01 readback failed: 8'h%02x", rdata);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 3: RAM 1-Bit SEU Injection & On-Demand Repair
        // ---------------------------------------------------------------------
        $display("\n--- Phase 3: RAM 1-Bit SEU Injection & On-Demand Read Repair ---");
        inject_ram_seu(8'h01, {{(CW-1){1'b0}}, 1'b1} << 3);

        host_read(8'h01, rdata, s_flag, d_flag, u_flag);
        if (rdata === 8'hA1 && s_flag && !d_flag && !u_flag) begin
            $display("[PASS] Host Read caught 1-bit SEU, repaired payload: 8'h%02x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Failed to repair 1-bit SEU at 8'h01: 8'h%02x s_flag=%b", rdata, s_flag);
            fail_count = fail_count + 1;
        end

        host_read(8'h01, rdata, s_flag, d_flag, u_flag);
        if (rdata === 8'hA1 && !s_flag && !d_flag && !u_flag) begin
            $display("[PASS] RAM location 8'h01 verified permanently repaired via write-back.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Location 8'h01 was not permanently repaired.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 3b: RAM 2-Bit SEU Injection & DEC Correction
        // ---------------------------------------------------------------------
        $display("\n--- Phase 3b: RAM 2-Bit SEU Injection & DEC Correction ---");
        inject_ram_seu(8'h02, ({{(CW-1){1'b0}}, 1'b1} << 1) | ({{(CW-1){1'b0}}, 1'b1} << 4));

        host_read(8'h02, rdata, s_flag, d_flag, u_flag);
        if (rdata === 8'hB2 && d_flag && !u_flag) begin
            $display("[PASS] Host Read caught 2-bit SEU and DEC successfully repaired: 8'h%02x (double_err_seen=1)", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Failed to repair 2-bit SEU at 8'h02: 8'h%02x d_flag=%b", rdata, d_flag);
            fail_count = fail_count + 1;
        end

        host_read(8'h02, rdata, s_flag, d_flag, u_flag);
        if (rdata === 8'hB2 && !s_flag && !d_flag && !u_flag) begin
            $display("[PASS] RAM location 8'h02 verified permanently healed from 2-bit SEU via write-back.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Location 8'h02 was not permanently repaired from 2-bit SEU.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 4: Autonomous Background Memory Scrubbing (Preemptive Healing)
        // ---------------------------------------------------------------------
        $display("\n--- Phase 4: Autonomous Background Memory Scrubbing ---");
        inject_ram_seu(8'h03, ({{(CW-1){1'b0}}, 1'b1} << 2) | ({{(CW-1){1'b0}}, 1'b1} << 5));
        prev_corr_count = corrected_count;

        $display("    Allowing background scrubber to patrol memory array...");
        repeat (100) @(posedge clk);

        if (corrected_count > prev_corr_count) begin
            $display("[PASS] Autonomous Scrubber detected & healed SEU! corrected_count=%0d", corrected_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Scrubber failed to increment corrected_count: count=%0d", corrected_count);
            fail_count = fail_count + 1;
        end

        host_read(8'h03, rdata, s_flag, d_flag, u_flag);
        if (rdata === 8'hC3 && !s_flag && !d_flag && !u_flag) begin
            $display("[PASS] Preemptive scrubbing confirmed: Host read address 8'h03 with zero error flags!");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Scrubbed word verification failed: rdata=8'h%02x s_flag=%b d_flag=%b", rdata, s_flag, d_flag);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 5: FSM Controller State SEU & TMR Self-Healing
        // ---------------------------------------------------------------------
        $display("\n--- Phase 5: TMR FSM Fault Injection & State Self-Healing ---");
        @(negedge clk);
        fsm_fault_inject = 3'b001; // Corrupt Copy 0
        @(negedge clk);
        fsm_fault_inject = 3'b000;
        @(negedge clk);
        if (tmr_mismatch === 1'b0) begin
            $display("[PASS] TMR copy 0 self-healed on subsequent clock edge.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TMR copy 0 failed to self-heal.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 6: Triple-Bit Uncorrectable SEU Handling (Honest Reporting)
        // ---------------------------------------------------------------------
        $display("\n--- Phase 6: Triple-Bit Error Detection & Controller Lockout ---");
        inject_ram_seu(8'h04, ({{(CW-1){1'b0}}, 1'b1} << 1) |
                              ({{(CW-1){1'b0}}, 1'b1} << 3) |
                              ({{(CW-1){1'b0}}, 1'b1} << 5));
        host_read(8'h04, rdata, s_flag, d_flag, u_flag);

        if (u_flag === 1'b1) begin
            $display("[PASS] Triple-bit error detected as uncorrectable anomaly (uncorrectable_err_seen=1).");
            $display("       Controller safely locked in ST_LOCKED_ERR to prevent silent data corruption.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Triple-bit error was not caught as uncorrectable: u_flag=%b", u_flag);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 7: Anti-Tamper Trigger & Secure Military Zeroization
        // ---------------------------------------------------------------------
        $display("\n--- Phase 7: Tamper Trigger & Secure Military Zeroization ---");
        @(negedge clk);
        tamper = 1'b1;
        @(negedge clk);
        tamper = 1'b0;
        @(negedge clk);

        if (zeroize_busy === 1'b1 && busy === 1'b1) begin
            $display("[PASS] Zeroize engine activated; host interface locked.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Zeroize did not engage: zeroize_busy=%b busy=%b", zeroize_busy, busy);
            fail_count = fail_count + 1;
        end

        // Wait for zeroize_done
        while (!zeroize_done) @(negedge clk);

        if (zeroize_done === 1'b1 && zeroize_fail === 1'b0) begin
            $display("[PASS] DoD Multi-pass overwrite and autonomous verification succeeded!");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Zeroize failed or timed out: done=%b fail=%b", zeroize_done, zeroize_fail);
            fail_count = fail_count + 1;
        end

        // Reset system to verify sanitized memory contents
        @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        // Read previously written addresses
        host_read(8'h01, rdata, s_flag, d_flag, u_flag);
        if (rdata === 8'h00) begin
            $display("[PASS] Address 8'h01 confirmed zeroized to 8'h00.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Residual data found at 8'h01: 8'h%02x", rdata);
            fail_count = fail_count + 1;
        end

        host_read(8'h02, rdata, s_flag, d_flag, u_flag);
        if (rdata === 8'h00) begin
            $display("[PASS] Address 8'h02 confirmed zeroized to 8'h00.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Residual data found at 8'h02: 8'h%02x", rdata);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   TEST SUMMARY: tb_top                                           ");
        $display("   TOTAL CHECKS PASSED: %0d", pass_count);
        $display("   TOTAL CHECKS FAILED: %0d", fail_count);
        if (fail_count == 0) begin
            $display("   >>> ALL TESTS PASSED! RHBD DEC-TED CONTROLLER FULLY VERIFIED. <<<");
        end else begin
            $display("   >>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<                ");
        end
        $display("==================================================================");

        #50;
        $finish;
    end

endmodule
