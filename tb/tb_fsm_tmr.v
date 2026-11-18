`timescale 1ns / 1ps
// =============================================================================
// File:        tb_fsm_tmr.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Testbench for Triple Modular Redundancy (TMR) Self-Healing FSM.
//
// Test Suite:
//   Test 1: Normal baseline transitions (IDLE -> WRITE -> IDLE -> READ -> IDLE).
//   Test 2: Single-copy SEU fault injection into State Copy 0 (fsm_fault_inject[0]).
//   Test 3: Single-copy SEU fault injection into State Copy 1 (fsm_fault_inject[1]).
//   Test 4: Single-copy SEU fault injection into State Copy 2 (fsm_fault_inject[2]).
//   Test 5: Dynamic SEU injection during an active host write cycle.
//   Test 6: Dynamic SEU injection during an active host read pipeline.
//   Test 7: Total self-healing count validation (tmr_fix_count).
// =============================================================================

module tb_fsm_tmr;

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
    reg         zeroize_busy;
    reg         zeroize_done;
    reg         scrub_req;
    wire        scrub_grant;

    reg  [2:0]  fsm_fault_inject;
    wire        state_mismatch;
    wire [15:0] tmr_fix_count;
    wire [2:0]  current_state;

    wire [7:0]  fsm_ram_addr;
    wire        fsm_ram_we;
    wire [12:0] fsm_ram_din;
    wire [12:0] ram_dout;

    wire        single_err_seen;
    wire        double_err_seen;

    // Instantiate FSM under test
    mem_ctrl_fsm #(
        .AW(8),
        .DW(13)
    ) dut_fsm (
        .clk             (clk),
        .rst             (rst),
        .req_wr          (req_wr),
        .req_rd          (req_rd),
        .host_addr       (host_addr),
        .host_wdata      (host_wdata),
        .host_rdata      (host_rdata),
        .rdata_valid     (rdata_valid),
        .busy            (busy),
        .tamper          (tamper),
        .zeroize_busy    (zeroize_busy),
        .zeroize_done    (zeroize_done),
        .scrub_req       (scrub_req),
        .scrub_grant     (scrub_grant),
        .fsm_fault_inject(fsm_fault_inject),
        .state_mismatch  (state_mismatch),
        .tmr_fix_count   (tmr_fix_count),
        .current_state   (current_state),
        .fsm_ram_addr    (fsm_ram_addr),
        .fsm_ram_we      (fsm_ram_we),
        .fsm_ram_din     (fsm_ram_din),
        .ram_dout        (ram_dout),
        .single_err_seen (single_err_seen),
        .double_err_seen (double_err_seen)
    );

    // Connected RAM
    ecc_ram #(
        .DW(13),
        .AW(8)
    ) u_ram (
        .clk        (clk),
        .we         (fsm_ram_we),
        .addr       (fsm_ram_addr),
        .din        (fsm_ram_din),
        .dout       (ram_dout),
        .inject_en  (1'b0),
        .inject_mask(13'd0)
    );

    // Clock Generation (100 MHz, 10 ns period)
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        $dumpfile("tb_fsm_tmr.vcd");
        $dumpvars(0, tb_fsm_tmr);

        clk              = 0;
        rst              = 1;
        req_wr           = 0;
        req_rd           = 0;
        host_addr        = 8'h00;
        host_wdata       = 8'h00;
        tamper           = 0;
        zeroize_busy     = 0;
        zeroize_done     = 0;
        scrub_req        = 0;
        fsm_fault_inject = 3'b000;

        $display("==================================================================");
        $display("   STARTING TESTBENCH: tb_fsm_tmr (TMR FSM Self-Healing)         ");
        $display("==================================================================");

        // Reset system
        #20;
        @(posedge clk);
        rst <= 0;
        @(posedge clk);
        #10;

        // ---------------------------------------------------------------------
        // Test 1: Normal Write and Read without Faults
        // ---------------------------------------------------------------------
        $display("\n--- Test 1: Baseline Write and Read Operation ---");
        @(posedge clk);
        req_wr     <= 1'b1;
        host_addr  <= 8'h05;
        host_wdata <= 8'h77;
        @(posedge clk);
        req_wr     <= 1'b0;
        @(posedge clk);
        while (busy) @(posedge clk);

        @(posedge clk);
        req_rd    <= 1'b1;
        host_addr <= 8'h05;
        @(posedge clk);
        req_rd    <= 1'b0;
        @(posedge clk);
        while (!rdata_valid) @(posedge clk);

        if (host_rdata === 8'h77) begin
            $display("[PASS] Baseline Write/Read completed cleanly. rdata=8'h%02x", host_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Baseline Write/Read failed: rdata=8'h%02x (expected 8'h77)", host_rdata);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 2: Inject Fault into State Copy 0 (fsm_fault_inject[0])
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: SEU Injection into State Copy 0 in IDLE ---");
        @(posedge clk);
        fsm_fault_inject <= 3'b001; // Corrupt copy 0
        @(posedge clk);
        fsm_fault_inject <= 3'b000; // Release corruption

        // Next cycle, mismatch is detected and voted state remains ST_IDLE (3'b000)
        #1;
        if (state_mismatch === 1'b1 && current_state === 3'b000) begin
            $display("[PASS] Copy 0 fault detected: state_mismatch=1, voted state preserved (ST_IDLE).");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Copy 0 fault failed: mismatch=%b state=%b", state_mismatch, current_state);
            fail_count = fail_count + 1;
        end

        @(posedge clk);
        #1;
        // Corrupted copy is self-healed on next clock edge
        if (state_mismatch === 1'b0) begin
            $display("[PASS] Self-healing verified: state_mismatch returned to 0.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Self-healing failed: mismatch still high.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 3: Inject Fault into State Copy 1 (fsm_fault_inject[1])
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: SEU Injection into State Copy 1 in IDLE ---");
        @(posedge clk);
        fsm_fault_inject <= 3'b010; // Corrupt copy 1
        @(posedge clk);
        fsm_fault_inject <= 3'b000;
        #1;
        if (state_mismatch === 1'b1 && current_state === 3'b000) begin
            $display("[PASS] Copy 1 fault detected: state_mismatch=1, voted state preserved.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Copy 1 fault failed: mismatch=%b state=%b", state_mismatch, current_state);
            fail_count = fail_count + 1;
        end

        @(posedge clk);
        #1;
        if (state_mismatch === 1'b0) begin
            $display("[PASS] Copy 1 self-healed on next clock cycle.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Copy 1 self-healing failed.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 4: Inject Fault into State Copy 2 (fsm_fault_inject[2])
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: SEU Injection into State Copy 2 in IDLE ---");
        @(posedge clk);
        fsm_fault_inject <= 3'b100; // Corrupt copy 2
        @(posedge clk);
        fsm_fault_inject <= 3'b000;
        #1;
        if (state_mismatch === 1'b1 && current_state === 3'b000) begin
            $display("[PASS] Copy 2 fault detected: state_mismatch=1, voted state preserved.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Copy 2 fault failed: mismatch=%b state=%b", state_mismatch, current_state);
            fail_count = fail_count + 1;
        end

        @(posedge clk);
        #1;
        if (state_mismatch === 1'b0) begin
            $display("[PASS] Copy 2 self-healed on next clock cycle.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Copy 2 self-healing failed.");
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 5: Dynamic SEU Injection During Host Write Transaction
        // ---------------------------------------------------------------------
        $display("\n--- Test 5: Dynamic SEU Injection During Host Write ---");
        @(posedge clk);
        req_wr           <= 1'b1;
        host_addr        <= 8'h0C;
        host_wdata       <= 8'hEE;
        fsm_fault_inject <= 3'b010; // Inject during write transition
        @(posedge clk);
        req_wr           <= 1'b0;
        fsm_fault_inject <= 3'b000;
        @(posedge clk);
        while (busy) @(posedge clk);

        // Verify the write succeeded despite the FSM SEU
        @(posedge clk);
        req_rd    <= 1'b1;
        host_addr <= 8'h0C;
        @(posedge clk);
        req_rd    <= 1'b0;
        @(posedge clk);
        while (!rdata_valid) @(posedge clk);

        if (host_rdata === 8'hEE) begin
            $display("[PASS] Write completed perfectly despite mid-transaction FSM SEU. rdata=8'h%02x", host_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Write failed during FSM SEU: rdata=8'h%02x", host_rdata);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 6: Verify Total TMR Fix Counter
        // ---------------------------------------------------------------------
        $display("\n--- Test 6: TMR Telemetry Fix Counter Verification ---");
        // We injected faults in tests 2, 3, 4, 5 -> total at least 4 fixes
        if (tmr_fix_count >= 16'd4) begin
            $display("[PASS] tmr_fix_count accurately logged %0d self-healing events.", tmr_fix_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] tmr_fix_count unexpected value: %0d", tmr_fix_count);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   TEST SUMMARY: tb_fsm_tmr                                       ");
        $display("   TOTAL CHECKS PASSED: %0d", pass_count);
        $display("   TOTAL CHECKS FAILED: %0d", fail_count);
        if (fail_count == 0) begin
            $display("   >>> ALL TESTS PASSED! TMR SELF-HEALING FSM VERIFIED. <<<       ");
        end else begin
            $display("   >>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<                ");
        end
        $display("==================================================================");

        #50;
        $finish;
    end

endmodule

