`timescale 1ns / 1ps
// =============================================================================
// File:        tb_ram_faults.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Testbench for RAM Fault Injection, Single-Bit Correction,
//              In-Situ Write-Back Verification, and Double-Bit Error Detection.
// =============================================================================

module tb_ram_faults;

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

    // Instantiate Top Module
    rhbd_mem_top #(
        .DW_DATA       (8),
        .AW            (8),
        .DW            (13),
        .SCRUB_INTERVAL(1000) // High interval so background scrubber does not interfere with manual test
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

    // Tasks for Host Operations
    task write_mem;
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

    task read_mem;
        input  [7:0] addr;
        output [7:0] data_out;
        output       s_err;
        output       d_err;
        begin
            @(posedge clk);
            while (busy) @(posedge clk);
            req_rd    <= 1'b1;
            host_addr <= addr;
            @(posedge clk);
            req_rd    <= 1'b0;
            s_err = 0;
            d_err = 0;

            // Wait for rdata_valid
            while (!rdata_valid && !double_err_seen) begin
                if (single_err_seen) s_err = 1;
                @(posedge clk);
            end
            if (single_err_seen) s_err = 1;
            if (double_err_seen) d_err = 1;
            data_out = host_rdata;
            @(posedge clk);
        end
    endtask

    task inject_fault;
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
    reg       s_err, d_err;

    initial begin
        $dumpfile("tb_ram_faults.vcd");
        $dumpvars(0, tb_ram_faults);

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
        $display("   STARTING TESTBENCH: tb_ram_faults                              ");
        $display("==================================================================");

        // Apply reset
        #20;
        @(posedge clk);
        rst <= 0;
        @(posedge clk);
        #10;

        // ---------------------------------------------------------------------
        // Test 1: Clean Write and Read
        // ---------------------------------------------------------------------
        $display("\n--- Test 1: Clean Write and Read at Address 8'h10 ---");
        write_mem(8'h10, 8'h42);
        read_mem(8'h10, rdata, s_err, d_err);

        if (rdata === 8'h42 && s_err === 1'b0 && d_err === 1'b0) begin
            $display("[PASS] Clean Read: Data 8'h%02x verified with no error flags.", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Clean Read failed: Data=8'h%02x (expected 8'h42) s_err=%b d_err=%b", rdata, s_err, d_err);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 2: Single-Bit Fault Injection & Autonomous Correction
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: Inject Single-Bit SEU (bit 3) at Address 8'h10 ---");
        inject_fault(8'h10, 13'h0008); // Flip bit 3 (d[0])
        read_mem(8'h10, rdata, s_err, d_err);

        if (rdata === 8'h42 && s_err === 1'b1 && d_err === 1'b0) begin
            $display("[PASS] Single-Bit SEU successfully repaired: Data=8'h%02x, single_err_seen asserted.", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Single-Bit repair failed: Data=8'h%02x s_err=%b d_err=%b", rdata, s_err, d_err);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 3: Verify In-Situ Write-Back Repaired the Physical RAM
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: Re-read Address 8'h10 to Confirm Write-Back Healing ---");
        // Read without any new fault injection: RAM should now be clean!
        read_mem(8'h10, rdata, s_err, d_err);

        if (rdata === 8'h42 && s_err === 1'b0 && d_err === 1'b0) begin
            $display("[PASS] Memory in-situ write-back verified: Address 8'h10 now reads clean with zero errors.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Memory write-back failed: Address 8'h10 still has s_err=%b or wrong data=8'h%02x", s_err, rdata);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 4: Double-Bit Fault Injection (Uncorrectable Error Detection)
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: Inject Double-Bit SEU (bits 1 & 3) at Address 8'h20 ---");
        write_mem(8'h20, 8'h99);
        inject_fault(8'h20, 13'h000A); // Flip bits 1 and 3 (p1 and d[0])
        read_mem(8'h20, rdata, s_err, d_err);

        if (d_err === 1'b1) begin
            $display("[PASS] Double-bit SEU accurately flagged as uncorrectable (double_err_seen asserted).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Double-bit SEU failed: d_err=%b s_err=%b", d_err, s_err);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 5: Verify Error Counters
        // ---------------------------------------------------------------------
        $display("\n--- Test 5: Telemetry Counters Verification ---");
        if (corrected_count >= 16'd1 && uncorrectable_count >= 16'd1) begin
            $display("[PASS] Telemetry Counters: corrected_count=%0d, uncorrectable_count=%0d",
                     corrected_count, uncorrectable_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Telemetry Counters wrong: corrected=%0d, uncorrectable=%0d",
                     corrected_count, uncorrectable_count);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   TEST SUMMARY: tb_ram_faults                                    ");
        $display("   TOTAL CHECKS PASSED: %0d", pass_count);
        $display("   TOTAL CHECKS FAILED: %0d", fail_count);
        if (fail_count == 0) begin
            $display("   >>> ALL TESTS PASSED! RAM FAULT TOLERANCE VERIFIED. <<<        ");
        end else begin
            $display("   >>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<                ");
        end
        $display("==================================================================");

        #50;
        $finish;
    end

endmodule

