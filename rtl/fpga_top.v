`timescale 1ns / 1ps
// =============================================================================
// File:        fpga_top.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Physical FPGA Hardware Wrapper for Board Demonstration.
//
// Hardware Features & Human-Interface:
//   - Clock: 100 MHz system clock from board oscillator.
//   - Buttons (Debounced + Single-Pulse):
//       * btn_rst       : Synchronous Master Reset
//       * btn_wr        : Host Write Strobe (writes sw_data to sw_addr)
//       * btn_rd        : Host Read Strobe (reads sw_addr)
//       * btn_inj_1bit  : Injects 1-bit SEU at sw_addr (flips bit 3)
//       * btn_inj_2bit  : Injects 2-bit SEU at sw_addr (flips bits 1 & 3)
//       * btn_inj_fsm   : Injects SEU into FSM State Copy 0
//       * btn_tamper    : Triggers Military Secure Zeroization
//   - Switches:
//       * sw_addr [7:0] : Memory Address (0..255)
//       * sw_data [7:0] : Write Data (0..255)
//   - Status LEDs:
//       * led_single_err   : Pulse-stretched LED for SEU single error repaired
//       * led_double_err   : Pulse-stretched LED for uncorrectable multi-bit error
//       * led_tmr_mismatch : Pulse-stretched LED for FSM TMR mismatch detected
//       * led_zeroize_busy : LED active during zeroization wipe & verify
//       * led_zeroize_done : LED active once secure zeroize successfully completes
//       * led_zeroize_fail : LED active if post-wipe zeroize verification fails
//       * led_busy         : Controller busy indicator
//   - Data Readout:
//       * led_rdata [7:0]  : Direct binary LEDs displaying host_rdata
//       * Seven-Segment Display (4 digits):
//           Digits [3:2] display Address (sw_addr) in Hex
//           Digits [1:0] display Read Data (host_rdata) in Hex
// =============================================================================

module fpga_top (
    input  wire        clk_100mhz,

    // Push Buttons
    input  wire        btn_rst,
    input  wire        btn_wr,
    input  wire        btn_rd,
    input  wire        btn_inj_1bit,
    input  wire        btn_inj_2bit,
    input  wire        btn_inj_fsm,
    input  wire        btn_tamper,

    // Slide Switches
    input  wire [7:0]  sw_addr,
    input  wire [7:0]  sw_data,

    // Status LEDs
    output wire        led_single_err,
    output wire        led_double_err,
    output wire        led_tmr_mismatch,
    output wire        led_zeroize_busy,
    output wire        led_zeroize_done,
    output wire        led_zeroize_fail,
    output wire        led_busy,

    // Data Readout LEDs
    output wire [7:0]  led_rdata,

    // 4-Digit Seven-Segment Display
    output reg  [6:0]  seg,
    output reg  [3:0]  an
);

    // -------------------------------------------------------------------------
    // 1. Debounce and Edge Detection Logic (100 MHz -> ~1 kHz sample tick)
    // -------------------------------------------------------------------------
    // A 16-bit counter divides 100 MHz clock to provide sample ticks for debouncing
    reg [16:0] debounce_div;
    wire sample_tick = (debounce_div == 17'd100_000); // 1 ms tick

    always @(posedge clk_100mhz) begin
        if (btn_rst) begin
            debounce_div <= 17'd0;
        end else if (sample_tick) begin
            debounce_div <= 17'd0;
        end else begin
            debounce_div <= debounce_div + 1'b1;
        end
    end

    // Button synchronizers and edge detectors
    wire wr_pulse;
    wire rd_pulse;
    wire inj_1bit_pulse;
    wire inj_2bit_pulse;
    wire inj_fsm_pulse;
    wire tamper_pulse;


    // 6 Channels of Debouncing + One-Pulse Generation
    reg [2:0] sync_wr, sync_rd, sync_1bit, sync_2bit, sync_fsm, sync_tamp;
    reg       clean_wr, clean_rd, clean_1bit, clean_2bit, clean_fsm, clean_tamp;
    reg       wr_d, rd_d, b1_d, b2_d, fsm_d, tamp_d;

    always @(posedge clk_100mhz) begin
        if (btn_rst) begin
            sync_wr    <= 3'b0;
            sync_rd    <= 3'b0;
            sync_1bit  <= 3'b0;
            sync_2bit  <= 3'b0;
            sync_fsm   <= 3'b0;
            sync_tamp  <= 3'b0;
            clean_wr   <= 1'b0;
            clean_rd   <= 1'b0;
            clean_1bit <= 1'b0;
            clean_2bit <= 1'b0;
            clean_fsm  <= 1'b0;
            clean_tamp <= 1'b0;
            wr_d       <= 1'b0;
            rd_d       <= 1'b0;
            b1_d       <= 1'b0;
            b2_d       <= 1'b0;
            fsm_d      <= 1'b0;
            tamp_d     <= 1'b0;
        end else begin
            if (sample_tick) begin
                sync_wr   <= {sync_wr[1:0],   btn_wr};
                sync_rd   <= {sync_rd[1:0],   btn_rd};
                sync_1bit <= {sync_1bit[1:0], btn_inj_1bit};
                sync_2bit <= {sync_2bit[1:0], btn_inj_2bit};
                sync_fsm  <= {sync_fsm[1:0],  btn_inj_fsm};
                sync_tamp <= {sync_tamp[1:0], btn_tamper};

                if (sync_wr == 3'b111)   clean_wr   <= 1'b1; else if (sync_wr == 3'b000)   clean_wr   <= 1'b0;
                if (sync_rd == 3'b111)   clean_rd   <= 1'b1; else if (sync_rd == 3'b000)   clean_rd   <= 1'b0;
                if (sync_1bit == 3'b111) clean_1bit <= 1'b1; else if (sync_1bit == 3'b000) clean_1bit <= 1'b0;
                if (sync_2bit == 3'b111) clean_2bit <= 1'b1; else if (sync_2bit == 3'b000) clean_2bit <= 1'b0;
                if (sync_fsm == 3'b111)  clean_fsm  <= 1'b1; else if (sync_fsm == 3'b000)  clean_fsm  <= 1'b0;
                if (sync_tamp == 3'b111) clean_tamp <= 1'b1; else if (sync_tamp == 3'b000) clean_tamp <= 1'b0;
            end

            wr_d   <= clean_wr;
            rd_d   <= clean_rd;
            b1_d   <= clean_1bit;
            b2_d   <= clean_2bit;
            fsm_d  <= clean_fsm;
            tamp_d <= clean_tamp;
        end
    end

    assign wr_pulse       = clean_wr   & ~wr_d;
    assign rd_pulse       = clean_rd   & ~rd_d;
    assign inj_1bit_pulse = clean_1bit & ~b1_d;
    assign inj_2bit_pulse = clean_2bit & ~b2_d;
    assign inj_fsm_pulse  = clean_fsm  & ~fsm_d;
    assign tamper_pulse   = clean_tamp & ~tamp_d;

    // -------------------------------------------------------------------------
    // 2. Fault Injection Mask & Address Control
    // -------------------------------------------------------------------------
    wire        inject_en_wire   = inj_1bit_pulse | inj_2bit_pulse;
    // inj_1bit flips bit 3; inj_2bit flips bits 1 & 3
    wire [12:0] inject_mask_wire = (inj_2bit_pulse) ? 13'h000A : 13'h0008;
    wire [2:0]  fsm_fault_wire   = {2'b00, inj_fsm_pulse};

    // -------------------------------------------------------------------------
    // 3. Core RHBD Top Instance
    // -------------------------------------------------------------------------
    wire [7:0]  host_rdata_wire;
    wire        rdata_valid_wire;
    wire        busy_wire;
    wire        single_err_wire;
    wire        double_err_wire;
    wire        tmr_mismatch_wire;
    wire        zero_busy_wire;
    wire        zero_done_wire;
    wire        zero_fail_wire;
    wire [15:0] corr_cnt_wire;
    wire [15:0] uncorr_cnt_wire;

    rhbd_mem_top #(
        .DW_DATA       (8),
        .AW            (8),
        .DW            (13),
        .SCRUB_INTERVAL(100000), // Scaled for hardware demonstration
        .PASSES        (3)
    ) u_rhbd_top (
        .clk                (clk_100mhz),
        .rst                (btn_rst),
        .req_wr             (wr_pulse),
        .req_rd             (rd_pulse),
        .host_addr          (sw_addr),
        .host_wdata         (sw_data),
        .host_rdata         (host_rdata_wire),
        .rdata_valid        (rdata_valid_wire),
        .busy               (busy_wire),
        .tamper             (tamper_pulse),
        .inject_en          (inject_en_wire),
        .inject_addr        (sw_addr),
        .inject_mask        (inject_mask_wire),
        .fsm_fault_inject   (fsm_fault_wire),
        .single_err_seen    (single_err_wire),
        .double_err_seen    (double_err_wire),
        .tmr_mismatch       (tmr_mismatch_wire),
        .zeroize_busy       (zero_busy_wire),
        .zeroize_done       (zero_done_wire),
        .zeroize_fail       (zero_fail_wire),
        .corrected_count    (corr_cnt_wire),
        .uncorrectable_count(uncorr_cnt_wire)
    );

    // Latched read data for display
    reg [7:0] rdata_display_reg;
    always @(posedge clk_100mhz) begin
        if (btn_rst) begin
            rdata_display_reg <= 8'h00;
        end else if (rdata_valid_wire) begin
            rdata_display_reg <= host_rdata_wire;
        end
    end

    assign led_rdata        = rdata_display_reg;
    assign led_busy         = busy_wire;
    assign led_zeroize_busy = zero_busy_wire;
    assign led_zeroize_done = zero_done_wire;
    assign led_zeroize_fail = zero_fail_wire;

    // -------------------------------------------------------------------------
    // 4. Pulse Stretchers for Fast Single-Cycle Error Pulses (~0.2 sec visual flash)
    // -------------------------------------------------------------------------
    reg [24:0] stretch_single, stretch_double, stretch_tmr;

    always @(posedge clk_100mhz) begin
        if (btn_rst) begin
            stretch_single <= 25'd0;
            stretch_double <= 25'd0;
            stretch_tmr    <= 25'd0;
        end else begin
            if (single_err_wire)         stretch_single <= 25'd20_000_000;
            else if (stretch_single > 0) stretch_single <= stretch_single - 1'b1;

            if (double_err_wire)         stretch_double <= 25'd20_000_000;
            else if (stretch_double > 0) stretch_double <= stretch_double - 1'b1;

            if (tmr_mismatch_wire)       stretch_tmr    <= 25'd20_000_000;
            else if (stretch_tmr > 0)    stretch_tmr    <= stretch_tmr - 1'b1;
        end
    end

    assign led_single_err   = (stretch_single > 0);
    assign led_double_err   = (stretch_double > 0);
    assign led_tmr_mismatch = (stretch_tmr > 0);

    // -------------------------------------------------------------------------
    // 5. Four-Digit Seven-Segment Multiplexed Hex Display
    // -------------------------------------------------------------------------
    // Shows Address [sw_addr] on Digits 3..2, and Read Data [rdata_display_reg] on Digits 1..0
    reg [17:0] refresh_counter;
    wire [1:0] active_digit = refresh_counter[17:16];

    always @(posedge clk_100mhz) begin
        if (btn_rst) refresh_counter <= 18'd0;
        else refresh_counter <= refresh_counter + 1'b1;
    end

    reg [3:0] hex_nibble;
    always @(*) begin
        case (active_digit)
            2'b00: begin
                an = 4'b1110; // Digit 0 (lowest)
                hex_nibble = rdata_display_reg[3:0];
            end
            2'b01: begin
                an = 4'b1101; // Digit 1
                hex_nibble = rdata_display_reg[7:4];
            end
            2'b10: begin
                an = 4'b1011; // Digit 2
                hex_nibble = sw_addr[3:0];
            end
            2'b11: begin
                an = 4'b0111; // Digit 3 (highest)
                hex_nibble = sw_addr[7:4];
            end
        endcase
    end

    // Cathode segment decoder (active-low: 0 = segment on, 1 = segment off)
    // Segments: {g, f, e, d, c, b, a}
    always @(*) begin
        case (hex_nibble)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end

endmodule
