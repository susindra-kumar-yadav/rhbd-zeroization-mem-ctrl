`timescale 1ns / 1ps
// =============================================================================
// File:        tmr_voter.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Parameterized Triple Modular Redundancy (TMR) Majority Voter.
//
// Operation:
//   - Computes bitwise majority vote across three redundant inputs: a, b, and c.
//   - If any single input differs from the others due to a radiation-induced
//     Single Event Upset (SEU), the majority output `y` filters out the fault.
//   - Generates an active-high `mismatch` status signal whenever the three
//     inputs are not all identical, triggering the system's fault-logging
//     and self-healing feedback mechanisms.
// =============================================================================

module tmr_voter #(
    parameter WIDTH = 1
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire [WIDTH-1:0] c,
    output wire [WIDTH-1:0] y,
    output wire             mismatch
);

    // Bitwise majority function: (a AND b) OR (b AND c) OR (a AND c)
    assign y = (a & b) | (b & c) | (a & c);

    // Mismatch detection: high if a != b or b != c (which covers a != c by transitivity)
    assign mismatch = (a != b) || (b != c);

endmodule

