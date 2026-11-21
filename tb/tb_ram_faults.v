`timescale 1ns / 1ps
// =============================================================================
// File:        tb_ram_faults.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Testbench for RAM Fault Injection, Single & Double Error Correction,
//              In-Situ Write-Back Verification, and Triple-Error Detection.
// =============================================================================

module tb_ram_faults;

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
        .SCRUB_INTERVAL(1000) // High interval so background scrubber does not interfere
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

    // Tasks for Host Operations
    task write_mem;
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

    task read_mem;
        input  [7:0] addr;
        output [7:0] data_out;
        output       s_err;
        output       d_err;
        output       u_err;
        begin
            @(negedge clk);
            while (busy) @(negedge clk);
            req_rd    = 1'b1;
            host_addr = addr;
            @(negedge clk);
            req_rd    = 1'b0;
            s_err = 0;
            d_err = 0;
            u_err = 0;

            // Wait for rdata_valid or uncorrectable lock
            while (!rdata_valid && !uncorrectable_err_seen) begin
                if (single_err_seen) s_err = 1;
                if (double_err_seen) d_err = 1;
                @(negedge clk);
            end
            if (single_err_seen) s_err = 1;
            if (double_err_seen) d_err = 1;
            if (uncorrectable_err_seen) u_err = 1;
            data_out = host_rdata;
            @(negedge clk);
        end
    endtask

    task inject_fault;
        input [7:0]   addr;
        input [CW-1:0] mask;
        begin
            @(negedge clk);
            inject_en   = 1'b1;
            inject_addr = addr;
            inject_mask = mask;
            @(negedge clk);
            inject_en   = 1'b0;
            inject_mask = {CW{1'b0}};
            @(negedge clk);
        end
    endtask

    reg [7:0] rdata;
    reg       s_err, d_err, u_err;

    initial begin
        $dumpfile("tb_ram_faults.vcd");
        $dumpvars(0, tb_ram_faults);

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
        $display("   STARTING TESTBENCH: tb_ram_faults (DEC-TED RAM Fault Tolerance)");
        $display("==================================================================");

        // Apply reset
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------------
        // Test 1: Clean Write and Read
        // ---------------------------------------------------------------------
        $display("\n--- Test 1: Clean Write and Read at Address 8'h10 ---");
        write_mem(8'h10, 8'h42);
        read_mem(8'h10, rdata, s_err, d_err, u_err);

        if (rdata === 8'h42 && s_err === 1'b0 && d_err === 1'b0 && u_err === 1'b0) begin
            $display("[PASS] Clean Read: Data 8'h%02x verified with no error flags.", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Clean Read failed: Data=8'h%02x (expected 8'h42) s_err=%b d_err=%b u_err=%b", rdata, s_err, d_err, u_err);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 2: Single-Bit Fault Injection & Autonomous Correction
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: Inject Single-Bit SEU (bit 3) at Address 8'h10 ---");
        inject_fault(8'h10, ({{(CW-1){1'b0}}, 1'b1} << 3));
        read_mem(8'h10, rdata, s_err, d_err, u_err);

        if (rdata === 8'h42 && s_err === 1'b1 && d_err === 1'b0 && u_err === 1'b0) begin
            $display("[PASS] Single-Bit SEU successfully repaired: Data=8'h%02x, single_err_seen asserted.", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Single-Bit repair failed: Data=8'h%02x s_err=%b d_err=%b u_err=%b", rdata, s_err, d_err, u_err);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 3: Verify In-Situ Write-Back Repaired the Physical RAM
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: Re-read Address 8'h10 to Confirm Write-Back Healing ---");
        read_mem(8'h10, rdata, s_err, d_err, u_err);

        if (rdata === 8'h42 && s_err === 1'b0 && d_err === 1'b0 && u_err === 1'b0) begin
            $display("[PASS] Memory in-situ write-back verified: Address 8'h10 now reads clean with zero errors.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Memory write-back failed: Address 8'h10 still has s_err=%b or wrong data=8'h%02x", s_err, rdata);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 4: Double-Bit Fault Injection & Autonomous DEC Repair
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: Inject Double-Bit SEU (bits 1 & 3) at Address 8'h20 ---");
        write_mem(8'h20, 8'h99);
        inject_fault(8'h20, ({{(CW-1){1'b0}}, 1'b1} << 1) | ({{(CW-1){1'b0}}, 1'b1} << 3));
        read_mem(8'h20, rdata, s_err, d_err, u_err);

        if (rdata === 8'h99 && d_err === 1'b1 && u_err === 1'b0) begin
            $display("[PASS] Double-bit SEU successfully repaired by DEC: Data=8'h%02x, double_err_seen asserted.", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Double-bit repair failed: Data=8'h%02x d_err=%b u_err=%b", rdata, d_err, u_err);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 5: Re-read Address 8'h20 to Confirm Double-Bit Write-Back Healing
        // ---------------------------------------------------------------------
        $display("\n--- Test 5: Re-read Address 8'h20 to Confirm Double-Bit Write-Back Healing ---");
        read_mem(8'h20, rdata, s_err, d_err, u_err);

        if (rdata === 8'h99 && s_err === 1'b0 && d_err === 1'b0 && u_err === 1'b0) begin
            $display("[PASS] Double-bit write-back healing verified: Address 8'h20 now reads clean!");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Double-bit write-back failed: Address 8'h20 error flags not cleared.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 6: Triple-Bit Fault Injection (TED Uncorrectable Detection)
        // ---------------------------------------------------------------------
        $display("\n--- Test 6: Inject Triple-Bit SEU (bits 1, 3, 5) at Address 8'h30 ---");
        write_mem(8'h30, 8'h55);
        inject_fault(8'h30, ({{(CW-1){1'b0}}, 1'b1} << 1) |
                            ({{(CW-1){1'b0}}, 1'b1} << 3) |
                            ({{(CW-1){1'b0}}, 1'b1} << 5));
        read_mem(8'h30, rdata, s_err, d_err, u_err);

        if (u_err === 1'b1) begin
            $display("[PASS] Triple-bit error flagged as uncorrectable anomaly (uncorrectable_err_seen asserted).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Triple-bit error failed: u_err=%b", u_err);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 7: Verify Telemetry Counters
        // ---------------------------------------------------------------------
        $display("\n--- Test 7: Telemetry Counters Verification ---");
        if (corrected_count >= 16'd2 && uncorrectable_count >= 16'd1) begin
            $display("[PASS] Telemetry Counters: corrected_count=%0d (1-bit & 2-bit), uncorrectable_count=%0d",
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
            $display("   >>> ALL TESTS PASSED! DEC-TED RAM FAULT TOLERANCE VERIFIED. <<<");
        end else begin
            $display("   >>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<                ");
        end
        $display("==================================================================");

        #50;
        $finish;
    end

endmodule
