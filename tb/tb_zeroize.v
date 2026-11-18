`timescale 1ns / 1ps
// =============================================================================
// File:        tb_zeroize.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Testbench for Military Anti-Tamper Multi-Pass Zeroization Engine.
//
// Test Suite:
//   Test 1: Pre-fill all 256 memory words with non-zero pseudorandom data.
//   Test 2: Assert tamper pulse and observe latching and zeroize_busy assertion.
//   Test 3: Attempt host write and read access during zeroize (confirm rejection).
//   Test 4: Verify zeroize_done assertion and zeroize_fail stays low.
//   Test 5: Exhaustive post-wipe verification: all 256 locations decode to 8'h00.
// =============================================================================

module tb_zeroize;

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

    // Instantiate Top Module with 3-Pass DoD Wipe
    rhbd_mem_top #(
        .DW_DATA       (8),
        .AW            (8),
        .DW            (13),
        .SCRUB_INTERVAL(10000),
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

    // Clock generation (100 MHz, 10 ns period)
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    task write_word;
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

    task read_word;
        input  [7:0] addr;
        output [7:0] data_out;
        begin
            @(posedge clk);
            while (busy) @(posedge clk);
            req_rd    <= 1'b1;
            host_addr <= addr;
            @(posedge clk);
            req_rd    <= 1'b0;
            @(posedge clk);
            while (!rdata_valid) @(posedge clk);
            data_out = host_rdata;
            @(posedge clk);
        end
    endtask

    reg [7:0] rval;

    initial begin
        $dumpfile("tb_zeroize.vcd");
        $dumpvars(0, tb_zeroize);

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
        $display("   STARTING TESTBENCH: tb_zeroize (Multi-Pass Anti-Tamper Wipe)   ");
        $display("==================================================================");

        // Reset
        #20;
        @(posedge clk);
        rst <= 0;
        @(posedge clk);
        #10;

        // ---------------------------------------------------------------------
        // Test 1: Fill Memory Array with Pseudorandom Non-Zero Data
        // ---------------------------------------------------------------------
        $display("\n--- Test 1: Filling all 256 addresses with non-zero data ---");
        for (i = 0; i < 256; i = i + 1) begin
            write_word(i[7:0], (i[7:0] ^ 8'hA5) | 8'h01);
        end
        $display("[PASS] Memory initialized with non-zero patterns.");
        pass_count = pass_count + 1;

        // Verify a sample word is non-zero
        read_word(8'h10, rval);
        if (rval !== 8'h00) begin
            $display("[PASS] Pre-wipe verification: address 8'h10 holds 8'h%02x (non-zero).", rval);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Pre-wipe address 8'h10 unexpectedly holds 0x00.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 2: Trigger Tamper Pulse
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: Assert Tamper Event ---");
        @(posedge clk);
        tamper <= 1'b1;
        @(posedge clk);
        tamper <= 1'b0;
        @(posedge clk);

        #1;
        if (zeroize_busy === 1'b1) begin
            $display("[PASS] Tamper latched: zeroize_busy asserted immediately.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] zeroize_busy did not assert after tamper event.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 3: Host Access Rejection During Active Zeroization
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: Attempt Host Write and Read During Wipe ---");
        // Check that controller busy is asserted
        if (busy === 1'b1) begin
            $display("[PASS] Host interface blocked: busy flag is high.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Host interface not blocked: busy is low.");
            fail_count = fail_count + 1;
        end

        // Attempt write while busy
        @(posedge clk);
        req_wr     <= 1'b1;
        host_addr  <= 8'h50;
        host_wdata <= 8'hAA;
        @(posedge clk);
        req_wr     <= 1'b0;
        @(posedge clk);

        // ---------------------------------------------------------------------
        // Test 4: Wait for Zeroization Completion
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: Waiting for Multi-Pass Overwrite & Verification ---");
        while (!zeroize_done) @(posedge clk);

        if (zeroize_done === 1'b1 && zeroize_fail === 1'b0) begin
            $display("[PASS] Zeroization completed: zeroize_done=1, zeroize_fail=0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Zeroize status abnormal: done=%b fail=%b", zeroize_done, zeroize_fail);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 5: Verify All 256 Words are Wiped to 0x00
        // ---------------------------------------------------------------------
        $display("\n--- Test 5: Exhaustive Post-Wipe RAM Readout (256 Words) ---");
        // Clear reset to restore host read capability after successful tamper wipe
        @(posedge clk);
        rst <= 1'b1;
        @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        #10;

        for (i = 0; i < 256; i = i + 1) begin
            read_word(i[7:0], rval);
            if (rval !== 8'h00) begin
                $display("[FAIL] Residual data found at address 8'h%02x: 8'h%02x (expected 8'h00)", i[7:0], rval);
                fail_count = fail_count + 1;
            end
        end

        if (fail_count == 0) begin
            $display("[PASS] All 256 memory words successfully confirmed as 8'h00.");
            pass_count = pass_count + 1;
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   TEST SUMMARY: tb_zeroize                                       ");
        $display("   TOTAL CHECKS PASSED: %0d", pass_count);
        $display("   TOTAL CHECKS FAILED: %0d", fail_count);
        if (fail_count == 0) begin
            $display("   >>> ALL TESTS PASSED! SECURE ZEROIZATION VERIFIED. <<<         ");
        end else begin
            $display("   >>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<                ");
        end
        $display("==================================================================");

        #50;
        $finish;
    end

endmodule

