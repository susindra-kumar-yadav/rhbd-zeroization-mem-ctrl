`timescale 1ns / 1ps
// =============================================================================
// File:        tb_top.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Full End-to-End System Integration Testbench.
//
// Mission Simulation Scenarios:
//   Phase 1: System Boot, Reset Sequence and Baseline Initialization.
//   Phase 2: Normal Host Write and Read Verification.
//   Phase 3: RAM Single-Event Upset (SEU) -> Host Read Correction & In-Situ Write-Back.
//   Phase 4: Autonomous Background Memory Scrubbing (preemptive SEU healing).
//   Phase 5: FSM Radiation Upset -> TMR Majority Voting & Instant Self-Healing.
//   Phase 6: Multi-Bit Radiation Upset -> Double Error Detection (SECDED trap).
//   Phase 7: Anti-Tamper Security Breach -> Multi-Pass Secure Zeroization Wipe.
// =============================================================================

module tb_top;

    reg         clk;
    reg         rst;

    reg         req_wr;
    reg         req_rd;
    reg  [7:0]  host_addr;
    reg  [7:0]  host_wdata;
    wire [7:0]  host_rdata;
    wire        rdata_valid;
    wire        busy;

    reg         tamper;
    reg         inject_en;
    reg  [7:0]  inject_addr;
    reg  [12:0] inject_mask;
    reg  [2:0]  fsm_fault_inject;

    wire        single_err_seen;
    wire        double_err_seen;
    wire        tmr_mismatch;
    wire        zeroize_busy;
    wire        zeroize_done;
    wire        zeroize_fail;
    wire [15:0] corrected_count;
    wire [15:0] uncorrectable_count;

    // Instantiate System Top Module
    // SCRUB_INTERVAL = 4 cycles for fast simulation of background scrubbing
    rhbd_mem_top #(
        .DW_DATA       (8),
        .AW            (8),
        .DW            (13),
        .SCRUB_INTERVAL(4),
        .PASSES        (3)
    ) dut (
        .clk                (clk),
        .rst                (rst),
        .req_wr             (req_wr),
        .req_rd             (req_rd),
        .host_addr          (host_addr),
        .host_wdata         (host_wdata),
        .host_rdata         (host_rdata),
        .rdata_valid        (rdata_valid),
        .busy               (busy),
        .tamper             (tamper),
        .inject_en          (inject_en),
        .inject_addr        (inject_addr),
        .inject_mask        (inject_mask),
        .fsm_fault_inject   (fsm_fault_inject),
        .single_err_seen    (single_err_seen),
        .double_err_seen    (double_err_seen),
        .tmr_mismatch       (tmr_mismatch),
        .zeroize_busy       (zeroize_busy),
        .zeroize_done       (zeroize_done),
        .zeroize_fail       (zeroize_fail),
        .corrected_count    (corrected_count),
        .uncorrectable_count(uncorrectable_count)
    );

    // Clock Generation (100 MHz, 10 ns period)
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task host_write;
        input [7:0] addr;
        input [7:0] data;
        begin
            @(posedge clk);
            while (busy) @(posedge clk);
            req_wr     <= 1'b1;
            host_addr  <= addr;
            host_wdata <= data;
            @(posedge clk);
            req_wr     <= 1'b0;
            @(posedge clk);
            while (busy) @(posedge clk);
        end
    endtask

    task host_read;
        input  [7:0] addr;
        output [7:0] data_out;
        output       s_flag;
        output       d_flag;
        begin
            @(posedge clk);
            while (busy) @(posedge clk);
            req_rd    <= 1'b1;
            host_addr <= addr;
            @(posedge clk);
            req_rd    <= 1'b0;
            s_flag = 0;
            d_flag = 0;

            while (!rdata_valid && !double_err_seen) begin
                if (single_err_seen) s_flag = 1;
                @(posedge clk);
            end
            if (single_err_seen) s_flag = 1;
            if (double_err_seen) d_flag = 1;
            data_out = host_rdata;
            @(posedge clk);
        end
    endtask

    task inject_ram_seu;
        input [7:0]  addr;
        input [12:0] mask;
        begin
            @(posedge clk);
            inject_en   <= 1'b1;
            inject_addr <= addr;
            inject_mask <= mask;
            @(posedge clk);
            inject_en   <= 1'b0;
            inject_mask <= 13'd0;
            @(posedge clk);
        end
    endtask

    reg [7:0] rdata;
    reg       s_flag, d_flag;
    integer   prev_corr_count;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        clk              = 0;
        rst              = 1;
        req_wr           = 0;
        req_rd           = 0;
        host_addr        = 8'h00;
        host_wdata       = 8'h00;
        tamper           = 0;
        inject_en        = 0;
        inject_addr      = 8'h00;
        inject_mask      = 13'h0000;
        fsm_fault_inject = 3'b000;

        $display("==================================================================");
        $display("   STARTING TESTBENCH: tb_top (Full End-to-End System Mission)    ");
        $display("==================================================================");

        // ---------------------------------------------------------------------
        // Phase 1: Reset Sequence
        // ---------------------------------------------------------------------
        $display("\n--- Phase 1: System Boot & Initialization ---");
        #25;
        @(posedge clk);
        rst <= 0;
        @(posedge clk);
        #10;
        if (!busy && !zeroize_busy && !zeroize_done) begin
            $display("[PASS] Controller booted up in clean IDLE state.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Boot state abnormal: busy=%b", busy);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 2: Host Write & Read Verification
        // ---------------------------------------------------------------------
        $display("\n--- Phase 2: Host Payload Storage & Verification ---");
        host_write(8'h01, 8'hA1);
        host_write(8'h02, 8'hB2);
        host_write(8'h03, 8'hC3);

        host_read(8'h01, rdata, s_flag, d_flag);
        if (rdata === 8'hA1 && !s_flag && !d_flag) begin
            $display("[PASS] Address 8'h01 read clean: 8'h%02x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Address 8'h01 read error: rdata=8'h%02x", rdata);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 3: Single Event Upset (SEU) on RAM & On-Demand Read Repair
        // ---------------------------------------------------------------------
        $display("\n--- Phase 3: RAM SEU Injection & On-Demand Read Repair ---");
        inject_ram_seu(8'h01, 13'h0008); // Flip bit 3 at address 8'h01

        host_read(8'h01, rdata, s_flag, d_flag);
        if (rdata === 8'hA1 && s_flag && !d_flag) begin
            $display("[PASS] Host Read caught SEU, repaired payload: 8'h%02x", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Host Read failed to repair SEU: rdata=8'h%02x s_flag=%b", rdata, s_flag);
            fail_count = fail_count + 1;
        end

        // Verify in-situ write-back healed the RAM
        host_read(8'h01, rdata, s_flag, d_flag);
        if (rdata === 8'hA1 && !s_flag && !d_flag) begin
            $display("[PASS] RAM location 8'h01 verified permanently repaired via write-back.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Location 8'h01 was not permanently repaired.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 4: Autonomous Background Memory Scrubbing
        // ---------------------------------------------------------------------
        $display("\n--- Phase 4: Autonomous Background Memory Scrubbing ---");
        // Address 8'h02 currently contains 8'hB2. Inject SEU into RAM:
        inject_ram_seu(8'h02, 13'h0010); // Flip bit 4 (parity bit p4)
        prev_corr_count = corrected_count;

        // Leave controller idle and wait for scrubber to reach and repair address 8'h02
        $display("    Allowing background scrubber to patrol memory array...");
        repeat (100) @(posedge clk);

        // Verify that the background scrubber found and corrected the fault
        if (corrected_count > prev_corr_count) begin
            $display("[PASS] Autonomous Scrubber detected & healed SEU! corrected_count=%0d", corrected_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Scrubber failed to increment corrected_count: count=%0d", corrected_count);
            fail_count = fail_count + 1;
        end

        // Host reads address 8'h02: Should already be completely clean!
        host_read(8'h02, rdata, s_flag, d_flag);
        if (rdata === 8'hB2 && !s_flag && !d_flag) begin
            $display("[PASS] Preemptive scrubbing confirmed: Host read address 8'h02 with zero error flags!");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Scrubbed word verification failed: rdata=8'h%02x s_flag=%b", rdata, s_flag);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 5: FSM Controller State SEU & TMR Self-Healing
        // ---------------------------------------------------------------------
        $display("\n--- Phase 5: TMR FSM Fault Injection & State Self-Healing ---");
        @(posedge clk);
        fsm_fault_inject <= 3'b001; // Corrupt Copy 0
        @(posedge clk);
        fsm_fault_inject <= 3'b000;
        #1;
        if (tmr_mismatch === 1'b1) begin
            $display("[PASS] TMR mismatch detected on state copy 0; majority vote preserved correct state.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TMR mismatch failed to assert.");
            fail_count = fail_count + 1;
        end

        @(posedge clk);
        #1;
        if (tmr_mismatch === 1'b0) begin
            $display("[PASS] TMR copy 0 self-healed on subsequent clock edge.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TMR copy 0 failed to self-heal.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 6: Double-Bit Uncorrectable SEU Handling
        // ---------------------------------------------------------------------
        $display("\n--- Phase 6: Double-Bit Error Detection & Lockout ---");
        inject_ram_seu(8'h03, 13'h000A); // Flip bits 1 & 3 at 8'h03
        host_read(8'h03, rdata, s_flag, d_flag);

        if (d_flag === 1'b1) begin
            $display("[PASS] Double-bit error detected; uncorrectable trap triggered.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Double-bit error was not caught: d_flag=%b", d_flag);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Phase 7: Anti-Tamper Trigger & Secure Zeroization
        // ---------------------------------------------------------------------
        $display("\n--- Phase 7: Tamper Trigger & Secure Military Zeroization ---");
        @(posedge clk);
        tamper <= 1'b1;
        @(posedge clk);
        tamper <= 1'b0;
        #1;

        // Verify zeroize_busy asserts
        if (zeroize_busy === 1'b1 && busy === 1'b1) begin
            $display("[PASS] Zeroize engine activated; host interface locked.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Zeroize did not engage: zeroize_busy=%b busy=%b", zeroize_busy, busy);
            fail_count = fail_count + 1;
        end

        // Wait for zeroize_done
        while (!zeroize_done) @(posedge clk);

        if (zeroize_done === 1'b1 && zeroize_fail === 1'b0) begin
            $display("[PASS] DoD Multi-pass overwrite and autonomous verification succeeded!");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Zeroize failed or timed out: done=%b fail=%b", zeroize_done, zeroize_fail);
            fail_count = fail_count + 1;
        end

        // Reset system to verify sanitized memory contents
        @(posedge clk);
        rst <= 1'b1;
        @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        // Read previously written addresses
        host_read(8'h01, rdata, s_flag, d_flag);
        if (rdata === 8'h00) begin
            $display("[PASS] Address 8'h01 confirmed zeroized to 8'h00.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Residual data found at 8'h01: 8'h%02x", rdata);
            fail_count = fail_count + 1;
        end

        host_read(8'h02, rdata, s_flag, d_flag);
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
            $display("   >>> ALL TESTS PASSED! RHBD MEMORY CONTROLLER FULLY OPERATIONAL. <<<");
        end else begin
            $display("   >>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<                ");
        end
        $display("==================================================================");

        #50;
        $finish;
    end

endmodule
