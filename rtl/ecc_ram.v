`timescale 1ns / 1ps
// =============================================================================
// File:        ecc_ram.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Synchronous Block RAM with SECDED-width data words (13-bit)
//              and built-in SEU fault injection capability.
//
// Ports:
//   - clk         : System clock
//   - we          : Synchronous write enable
//   - addr        : AW-bit memory address
//   - din         : DW-bit codeword data input
//   - dout        : DW-bit registered codeword data output (1 cycle latency)
//   - inject_en   : Fault injection enable (active when we = 0)
//   - inject_mask : DW-bit XOR mask for flipping target bit(s) in memory
// =============================================================================

module ecc_ram #(
    parameter DW = 13,
    parameter AW = 8
)(
    input  wire          clk,
    input  wire          we,
    input  wire [AW-1:0] addr,
    input  wire [DW-1:0] din,
    output reg  [DW-1:0] dout,
    input  wire          inject_en,
    input  wire [DW-1:0] inject_mask
);

    // Memory array definition: 2^AW words of DW bits
    reg [DW-1:0] mem [(1<<AW)-1:0];

    // Initialize all memory locations and output to zero
    integer i;
    initial begin
        for (i = 0; i < (1<<AW); i = i + 1) begin
            mem[i] = {DW{1'b0}};
        end
        dout = {DW{1'b0}};
    end

    // Synchronous write / fault-injection / read process
    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;
        end else if (inject_en) begin
            mem[addr] <= mem[addr] ^ inject_mask;
        end
        dout <= mem[addr];
    end

endmodule

