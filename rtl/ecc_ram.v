`timescale 1ns / 1ps
// =============================================================================
// File:        ecc_ram.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Synchronous Block RAM with parameterized codeword width (CW)
//              and physical SEU fault injection capability.
//
// Parameters:
//   - CW          : Total codeword bit width (default 18 for DEC-TED ECC)
//   - DW          : Alias for CW to maintain compatibility with legacy parameter naming
//   - AW          : Memory address width (default 8 = 256 words)
//
// Ports:
//   - clk         : System clock
//   - we          : Synchronous write enable
//   - addr        : AW-bit memory address
//   - din         : CW-bit codeword data input
//   - dout        : CW-bit registered codeword data output (1 cycle latency)
//   - inject_en   : Fault injection enable (active when we = 0)
//   - inject_mask : CW-bit XOR mask for flipping target bit(s) in physical memory
// =============================================================================

module ecc_ram #(
    parameter CW = 18,
    parameter DW = CW,
    parameter AW = 8
)(
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] addr,
    input  wire [CW-1:0] din,
    output reg  [CW-1:0] dout,
    input  wire          inject_en,
    input  wire [CW-1:0] inject_mask
);

    // Physical memory array: 2^AW words of CW bits
    reg [CW-1:0] mem [(1<<AW)-1:0];

    // Initialize all memory locations and output register to all zeros
    integer i;
    initial begin
        for (i = 0; i < (1<<AW); i = i + 1) begin
            mem[i] = {CW{1'b0}};
        end
        dout = {CW{1'b0}};
    end

    // Synchronous write / registered read / physical SEU fault injection
    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;
        end else if (inject_en) begin
            mem[addr] <= mem[addr] ^ inject_mask;
        end
        dout <= mem[addr];
    end

endmodule
