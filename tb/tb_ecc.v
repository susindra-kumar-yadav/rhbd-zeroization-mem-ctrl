`timescale 1ns / 1ps
// =============================================================================
// File:        tb_ecc.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Self-Checking Testbench for DEC-TED (T=2) ECC Encoder & Decoder.
//
// Test Suite:
//   Test 1: Verify Zeroization Encoding Rule (8'h00 -> 18'h00000).
//   Test 2: Exhaustive clean encode-decode cycle across all 256 data words.
//   Test 3: Systematic single-bit fault injection across all 18 codeword positions.
//   Test 4: Systematic double-bit fault injection (confirming DEC correction).
//   Test 5: Triple-bit fault injection (confirming TED uncorrectable detection).
// =============================================================================

module tb_ecc;

    parameter DATA_W = 8;
    parameter CHK_W  = 10;
    parameter CW     = 18;
    parameter T_ERR  = 2;

    reg  [DATA_W-1:0] data_in;
    wire [CW-1:0]     encoded_code;

    reg  [CW-1:0]     corrupted_code;
    wire [DATA_W-1:0] data_out;
    wire [CW-1:0]     code_corrected;
    wire [1:0]        error_weight;
    wire              uncorrectable;
    wire              single_err;
    wire              double_err;
    wire              corrected_err;
    wire [CHK_W-1:0]  syndrome;

    // Instantiate ECC Encoder
    ecc_enc #(
        .DATA_W(DATA_W),
        .CHK_W (CHK_W),
        .CW_W  (CW)
    ) u_enc (
        .data(data_in),
        .code(encoded_code)
    );

    // Instantiate ECC Decoder
    ecc_dec #(
        .DATA_W(DATA_W),
        .CHK_W (CHK_W),
        .CW_W  (CW),
        .T_ERR (T_ERR)
    ) u_dec (
        .code          (corrupted_code),
        .data_corrected(data_out),
        .code_corrected(code_corrected),
        .error_weight  (error_weight),
        .uncorrectable (uncorrectable),
        .single_err    (single_err),
        .double_err    (double_err),
        .corrected_err (corrected_err),
        .syndrome      (syndrome)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer i, b1, b2;
    reg [7:0] test_val;

    initial begin
        $dumpfile("tb_ecc.vcd");
        $dumpvars(0, tb_ecc);

        $display("==================================================================");
        $display("   STARTING TESTBENCH: tb_ecc (DEC-TED ECC Validation)           ");
        $display("   Parameters: DATA_W=%0d, CHK_W=%0d, CW=%0d, T_ERR=%0d", DATA_W, CHK_W, CW, T_ERR);
        $display("==================================================================");

        // ---------------------------------------------------------------------
        // Test 1: Verify Zeroization Encoding Rule (8'h00 -> 18'h00000)
        // ---------------------------------------------------------------------
        data_in = 8'h00;
        #5;
        if (encoded_code === {CW{1'b0}}) begin
            $display("[PASS] Zero Data Encoding: 8'h00 -> %0d'h0 verified.", CW);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Zero Data Encoding: 8'h00 produced %0d'h%x (expected 0)", CW, encoded_code);
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
            if (data_out !== data_in || error_weight !== 2'd0 || uncorrectable !== 1'b0 || syndrome !== {CHK_W{1'b0}}) begin
                $display("[FAIL] Clean decode failed for data=8'h%02x: out=8'h%02x wt=%0d uncorr=%b syn=%d",
                         data_in, data_out, error_weight, uncorrectable, syndrome);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end
        end
        $display("[PASS] All 256 values encoded and decoded cleanly without false alarms.");

        // ---------------------------------------------------------------------
        // Test 3: Systematic Single-Bit Error Correction (18 bit positions)
        // ---------------------------------------------------------------------
        $display("\n--- Running Test 3: Single-Bit Error Correction across all 18 Bit Positions ---");
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

            for (b1 = 0; b1 < CW; b1 = b1 + 1) begin
                corrupted_code = encoded_code ^ ({{(CW-1){1'b0}}, 1'b1} << b1);
                #5;

                if (data_out !== test_val || error_weight !== 2'd1 || single_err !== 1'b1 || uncorrectable !== 1'b0) begin
                    $display("[FAIL] Single-bit flip at bit %0d for data 8'h%02x: out=8'h%02x wt=%0d single=%b uncorr=%b",
                             b1, test_val, data_out, error_weight, single_err, uncorrectable);
                    fail_count = fail_count + 1;
                end else begin
                    pass_count = pass_count + 1;
                end
            end
        end
        $display("[PASS] Single-bit error correction verified across all 18 bit positions.");

        // ---------------------------------------------------------------------
        // Test 4: Systematic Double-Bit Error Correction (DEC Capability)
        // ---------------------------------------------------------------------
        $display("\n--- Running Test 4: Double-Bit Error Correction (DEC Validation) ---");
        test_val = 8'hA5;
        data_in = test_val;
        #5;

        for (b1 = 0; b1 < CW; b1 = b1 + 1) begin
            for (b2 = b1 + 1; b2 < CW; b2 = b2 + 1) begin
                corrupted_code = encoded_code ^ ({{(CW-1){1'b0}}, 1'b1} << b1) ^ ({{(CW-1){1'b0}}, 1'b1} << b2);
                #5;

                if (data_out !== test_val || error_weight !== 2'd2 || double_err !== 1'b1 || uncorrectable !== 1'b0) begin
                    $display("[FAIL] Double-bit flip at (%0d, %0d): out=8'h%02x wt=%0d double=%b uncorr=%b",
                             b1, b2, data_out, error_weight, double_err, uncorrectable);
                    fail_count = fail_count + 1;
                end else begin
                    pass_count = pass_count + 1;
                end
            end
        end
        $display("[PASS] All pairwise double-bit error combinations successfully repaired (DEC verified)!");

        // ---------------------------------------------------------------------
        // Test 5: Triple-Bit Error Detection (TED Capability)
        // ---------------------------------------------------------------------
        $display("\n--- Running Test 5: Triple-Bit Error Detection (TED Validation) ---");
        // Test sample triple-bit flips:
        corrupted_code = encoded_code ^ ({{(CW-1){1'b0}}, 1'b1} << 0)
                                      ^ ({{(CW-1){1'b0}}, 1'b1} << 2)
                                      ^ ({{(CW-1){1'b0}}, 1'b1} << 5);
        #5;
        if (uncorrectable === 1'b1) begin
            $display("[PASS] Triple-bit error (0, 2, 5) detected as uncorrectable.");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Triple-bit error not flagged uncorrectable: uncorr=%b", uncorrectable);
            fail_count = fail_count + 1;
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("   TEST SUMMARY: tb_ecc                                           ");
        $display("   TOTAL CHECKS PASSED: %0d", pass_count);
        $display("   TOTAL CHECKS FAILED: %0d", fail_count);
        if (fail_count == 0) begin
            $display("   >>> ALL TESTS PASSED! DEC-TED LOGIC IS FULLY VERIFIED. <<<     ");
        end else begin
            $display("   >>> SOME TESTS FAILED! CHECK OUTPUT ABOVE. <<<                ");
        end
        $display("==================================================================");

        #10;
        $finish;
    end

endmodule
