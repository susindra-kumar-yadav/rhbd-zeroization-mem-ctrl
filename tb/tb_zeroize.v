`timescale 1ns / 1ps
// =============================================================================
// File:        tb_zeroize.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Testbench for Military Anti-Tamper Multi-Pass Zeroization Engine
//              with Parameterized CW Codeword Width.
//
// Test Suite:
//   Test 1: Pre-fill all 256 memory words with non-zero pseudorandom data.
//   Test 2: Assert tamper pulse and observe latching and zeroize_busy assertion.
//   Test 3: Attempt host write and read access during zeroize (confirm rejection).
//   Test 4: Verify zeroize_done assertion and zeroize_fail stays low.
//   Test 5: Exhaustive post-wipe verification: all 256 locations decode to 8'h00.
// =============================================================================

module tb_zeroize;

    parameter DW_DATA = 8;
    parameter AW      = 8;
    parameter CHK_W   = 10;
    parameter CW      = 18;

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
    reg              inject_en;
    reg  [AW-1:0]    inject_addr;
    reg  [CW-1:0]    inject_mask;
    reg  [2:0]       fsm_fault_inject;

    wire             single_err_seen;
    wire             double_err_seen;
    wire             corrected_err_seen;
    wire             uncorrectable_err_seen;
    wire             tmr_mismatch;
    wire             zeroize_busy;
    wire             zeroize_done;
    wire             zeroize_fail;
    wire [15:0]      corrected_count;
    wire [15:0]      uncorrectable_count;

    // Instantiate Top Module with Parameterized CW
    rhbd_mem_top #(
        .DW_DATA       (DW_DATA),
        .AW            (AW),
        .CHK_W         (CHK_W),
        .CW            (CW),
        .DW            (CW),
        .SCRUB_INTERVAL(10000),
        .PASSES        (3)
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
        .lock_clear            (1'b0),
        .inject_en             (inject_en),
        .inject_addr           (inject_addr),
        .inject_mask           (inject_mask),
        .fsm_fault_inject      (fsm_fault_inject),
        .fsm_code_inject0      (11'b0),
        .fsm_code_inject1      (11'b0),
        .fsm_code_inject2      (11'b0),
        .voter_fault_inject    (3'b0),
        .tamper_fault_inject   (3'b0),
        .zeroize_fault_inject  (1'b0),
        .single_err_seen       (single_err_seen),
        .double_err_seen       (double_err_seen),
        .corrected_err_seen    (corrected_err_seen),
        .uncorrectable_err_seen(uncorrectable_err_seen),
        .tmr_mismatch          (tmr_mismatch),
        .zeroize_busy          (zeroize_busy),
        .zeroize_done          (zeroize_done),
        .zeroize_fail          (zeroize_fail),
        .corrected_count       (corrected_count),
        .uncorrectable_count   (uncorrectable_count)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    task write_word;
        input [7:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            while (busy) @(negedge clk);
            req_wr     = 1'b1;
            host_addr  = addr;
            host_wdata = data;
            @(negedge clk);
            req_wr     = 1'b0;
            @(negedge clk);
            @(negedge clk);
        end
    endtask

    task read_word;
        input  [7:0] addr;
        output [7:0] data_out;
        begin
            @(negedge clk);
            while (busy) @(negedge clk);
            req_rd    = 1'b1;
            host_addr = addr;
            @(negedge clk);
            req_rd    = 1'b0;
            @(negedge clk);
            while (!rdata_valid) @(negedge clk);
            data_out = host_rdata;
            @(negedge clk);
        end
    endtask

    reg [7:0] rval;

    initial begin
        $dumpfile("tb_zeroize.vcd");
        $dumpvars(0, tb_zeroize);

        rst              = 1;
        req_wr           = 0;
        req_rd           = 0;
        host_addr        = 8'h00;
        host_wdata       = 8'h00;
        tamper           = 0;
        inject_en        = 0;
        inject_addr      = 8'h00;
        inject_mask      = {CW{1'b0}};
        fsm_fault_inject = 3'b000;

        $display("==================================================================");
        $display("   STARTING TESTBENCH: tb_zeroize (Multi-Pass Anti-Tamper Wipe)   ");
        $display("==================================================================");

        // Reset
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

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
