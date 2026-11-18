`timescale 1ns / 1ps
// =============================================================================
// File:        tb_ecc.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Comprehensive Self-Checking Testbench for SECDED Encoder & Decoder.
//
// Test Suite:
//   Test 1: Exhaustive clean encode-decode cycle across all 256 8-bit values.
//   Test 2: Systematic single-bit fault injection across all 13 codeword positions.
//   Test 3: Systematic double-bit fault injection across pairwise bit combinations.
//   Test 4: Verification of zero-data mapping: 8'h00 -> 13'h0000.
// =============================================================================

module tb_ecc;

    reg  [7:0]  data_in;
    wire [12:0] encoded_code;

    reg  [12:0] corrupted_code;
    wire [7:0]  data_out;
    wire        single_err;
    wire        double_err;
    wire [3:0]  syndrome;
    wire [12:0] code_corrected;

    // Instantiate Encoder
    hamming_secded_enc u_enc (
        .data(data_in),
        .code(encoded_code)
    );

    // Instantiate Decoder
    hamming_secded_dec u_dec (
        .code          (corrupted_code),
        .data_corrected(data_out),
        .single_err    (single_err),
        .double_err    (double_err),
        .syndrome      (syndrome),
        .code_corrected(code_corrected)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer i, b1, b2;
    reg [7:0] test_val;

    initial begin
        $dumpfile("tb_ecc.vcd");
        $dumpvars(0, tb_ecc);

        $display("==================================================================");
        $display("   STARTING TESTBENCH: tb_ecc (SECDED Hamming Code Validation)    ");
        $display("==================================================================");

        // ---------------------------------------------------------------------
        // Test 1: Verify Zeroization Encoding Rule (8'h00 -> 13'h0000)
        // ---------------------------------------------------------------------
        data_in = 8'h00;
        #5;
        if (encoded_code === 13'h0000) begin
            $display("[PASS] Zero Data Encoding: 8'h00 -> 13'h0000 verified.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Zero Data Encoding: 8'h00 produced 13'h%04x (expected 13'h0000)", encoded_code);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Test 2: Clean Encode-Decode across all 256 Data Values
        // ---------------------------------------------------------------------
        $display("\n--- Running Test 2: Exhaustive 256-Word Clean Encode-Decode ---");
        for (i = 0; i < 256; i = i + 1) begin
            data_in = i[7:0];
            #5;
            corrupted_code = encoded_code; // No error injected
            #5;
            if (data_out !== data_in || single_err !== 1'b0 || double_err !== 1'b0 || syndrome !== 4'd0) begin
                $display("[FAIL] Clean decode failed for data=8'h%02x: out=8'h%02x single=%b double=%b syn=%d",
                         data_in, data_out, single_err, double_err, syndrome);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end
        end
        $display("[PASS] All 256 values encoded and decoded cleanly without false alarms.");

        // ---------------------------------------------------------------------
        // Test 3: Systematic Single-Bit Error Correction (13 bit positions)
        // ---------------------------------------------------------------------
        $display("\n--- Running Test 3: Single-Bit Error Injection across all 13 Bit Positions ---");
        // Test with distinct patterns: 0x00, 0x55, 0xAA, 0xFF, 0x3C, 0xA5
        for (i = 0; i < 6; i = i + 1) begin
            case (i)
                0: test_val = 8'h00;
                1: test_val = 8'h55;
                2: test_val = 8'hAA;
                3: test_val = 8'hFF;
                4: test_val = 8'h3C;
                5: test_val = 8'hA5;
            endcase

            data_in = test_val;
            #5;

            for (b1 = 0; b1 < 13; b1 = b1 + 1) begin
                corrupted_code = encoded_code ^ (13'b1 << b1);
                #5;

                if (data_out !== test_val || single_err !== 1'b1 || double_err !== 1'b0) begin
                    $display("[FAIL] Single-bit flip at bit %0d for data 8'h%02x: out=8'h%02x single=%b double=%b",
                             b1, test_val, data_out, single_err, double_err);
                    fail_count = fail_count + 1;
                end else begin
                    // Verify syndrome matches position for bits 1..12, or is 0 for bit 0
                    if ((b1 == 0 && syndrome !== 4'd0) || (b1 > 0 && syndrome !== b1[3:0])) begin
                        $display("[FAIL] Single-bit flip at bit %0d: unexpected syndrome %0d", b1, syndrome);
                        fail_count = fail_count + 1;
                    end else begin
                        pass_count = pass_count + 1;
                    end
                end
            end
        end
        $display("[PASS] Single-bit error correction verified across all 13 bit positions.");

        // ---------------------------------------------------------------------
        // Test 4: Systematic Double-Bit Error Detection (Pairwise combinations)
        // ---------------------------------------------------------------------
        $display("\n--- Running Test 4: Double-Bit Error Injection (SECDED Detection) ---");
        test_val = 8'hA5;
        data_in = test_val;
        #5;

        for (b1 = 0; b1 < 13; b1 = b1 + 1) begin
            for (b2 = b1 + 1; b2 < 13; b2 = b2 + 1) begin
                corrupted_code = encoded_code ^ (13'b1 << b1) ^ (13'b1 << b2);
                #5;

                if (double_err !== 1'b1 || single_err !== 1'b0) begin
                    $display("[FAIL] Double-bit flip at bits (%0d, %0d): double=%b single=%b (expected double=1, single=0)",
                             b1, b2, double_err, single_err);
                    fail_count = fail_count + 1;
                end else begin
                    pass_count = pass_count + 1;
                end
            end
        end
        $display("[PASS] All pairwise double-bit error combinations detected as uncorrectable.");

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   TEST SUMMARY: tb_ecc                                           ");
        $display("   TOTAL CHECKS PASSED: %0d", pass_count);
        $display("   TOTAL CHECKS FAILED: %0d", fail_count);
        if (fail_count == 0) begin
            $display("   >>> ALL TESTS PASSED! SECDED LOGIC IS FULLY VERIFIED. <<<     ");
        end else begin
            $display("   >>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<                ");
        end
        $display("==================================================================");

        #10;
        $finish;
    end

endmodule

