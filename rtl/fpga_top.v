`timescale 1ns / 1ps
// =============================================================================
// File:        fpga_top.v
// Project:     Radiation-Hardened-by-Design (RHBD) Memory Controller
// Target:      Xilinx Artix-7 FPGA (Vivado 2026.2) / Icarus Verilog
// Standards:   Verilog-2001
// Description: Physical FPGA Hardware Board Wrapper with Enhanced TMR & Fault Status LEDs.
//
// Features & Enhancements (Phase 2):
//   - Buttons (Debounced + Single-Pulse):
//       * btn_rst        : Synchronous Master Reset
//       * btn_wr         : Host Write Strobe (writes sw_data to sw_addr)
//       * btn_rd         : Host Read Strobe (reads sw_addr)
//       * btn_inj_1bit   : Injects 1-bit SEU at sw_addr
//       * btn_inj_2bit   : Injects 2-bit SEU at sw_addr
//       * btn_inj_fsm    : Injects SEU into FSM State Copy 0
//       * btn_tamper     : Triggers Military Secure Zeroization
//       * btn_lock_clear : Clears locked error state, returning controller to IDLE
//   - Switches:
//       * sw_addr [7:0]  : Memory Address (0..255)
//       * sw_data [7:0]  : Write Data (0..255)
//   - Status LEDs:
//       * led_single_err       : 1-bit SEU error repaired (pulse-stretched)
//       * led_double_err       : 2-bit SEU error repaired (pulse-stretched)
//       * led_tmr_mismatch     : FSM TMR mismatch detected (pulse-stretched)
//       * led_fsm_locked       : High when FSM is held in LOCKED_ERR state
//       * led_fsm_degraded     : High when FSM operates in degraded mode (2 copies bad)
//       * led_no_majority      : High when FSM copies all disagree
//       * led_illegal_state    : High when an unmapped Gray state is detected
//       * led_bad_transition   : High when an unauthorized state transition is caught
//       * led_watchdog_timeout : High when autonomous watchdog timer fires
//       * led_counter_fault    : High when zeroize dual counter invariant fails
//       * led_zeroize_busy     : Active during zeroization wipe & verify
//       * led_zeroize_done     : Active once secure zeroize successfully completes
//       * led_zeroize_fail     : Active if post-wipe zeroize verification fails
//       * led_busy             : Controller busy indicator
//   - Data Readout:
//       * led_rdata [7:0]      : Direct binary LEDs displaying host_rdata
//       * Seven-Segment Display (4 digits): Address on Digits 3..2, Read Data on 1..0
// =============================================================================

module fpga_top #(
    parameter DATA_W    = 8,
    parameter CHK_W     = 10,
    parameter CW        = 18,
    parameter AW        = 8,
    parameter T_STATE   = 2,
    parameter CHK_STATE = (T_STATE == 1) ? 4 : 8,
    parameter CW_STATE  = 3 + CHK_STATE
)(
    input  wire        clk_100mhz,

    // Push Buttons
    input  wire        btn_rst,
    input  wire        btn_wr,
    input  wire        btn_rd,
    input  wire        btn_inj_1bit,
    input  wire        btn_inj_2bit,
    input  wire        btn_inj_fsm,
    input  wire        btn_tamper,
    input  wire        btn_lock_clear,

    // Slide Switches
    input  wire [7:0]  sw_addr,
    input  wire [7:0]  sw_data,

    // Status LEDs
    output wire        led_single_err,
    output wire        led_double_err,
    output wire        led_tmr_mismatch,
    output wire        led_fsm_locked,
    output wire        led_fsm_degraded,
    output wire        led_no_majority,
    output wire        led_illegal_state,
    output wire        led_bad_transition,
    output wire        led_watchdog_timeout,
    output wire        led_counter_fault,
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

    // 7 Channels of Debouncing + One-Pulse Generation
    reg [2:0] sync_wr, sync_rd, sync_1bit, sync_2bit, sync_fsm, sync_tamp, sync_clr;
    reg       clean_wr, clean_rd, clean_1bit, clean_2bit, clean_fsm, clean_tamp, clean_clr;
    reg       wr_d, rd_d, b1_d, b2_d, fsm_d, tamp_d, clr_d;

    always @(posedge clk_100mhz) begin
        if (btn_rst) begin
            sync_wr    <= 3'b0;
            sync_rd    <= 3'b0;
            sync_1bit  <= 3'b0;
            sync_2bit  <= 3'b0;
            sync_fsm   <= 3'b0;
            sync_tamp  <= 3'b0;
            sync_clr   <= 3'b0;
            clean_wr   <= 1'b0;
            clean_rd   <= 1'b0;
            clean_1bit <= 1'b0;
            clean_2bit <= 1'b0;
            clean_fsm  <= 1'b0;
            clean_tamp <= 1'b0;
            clean_clr  <= 1'b0;
            wr_d       <= 1'b0;
            rd_d       <= 1'b0;
            b1_d       <= 1'b0;
            b2_d       <= 1'b0;
            fsm_d      <= 1'b0;
            tamp_d     <= 1'b0;
            clr_d      <= 1'b0;
        end else begin
            if (sample_tick) begin
                sync_wr   <= {sync_wr[1:0],   btn_wr};
                sync_rd   <= {sync_rd[1:0],   btn_rd};
                sync_1bit <= {sync_1bit[1:0], btn_inj_1bit};
                sync_2bit <= {sync_2bit[1:0], btn_inj_2bit};
                sync_fsm  <= {sync_fsm[1:0],  btn_inj_fsm};
                sync_tamp <= {sync_tamp[1:0], btn_tamper};
                sync_clr  <= {sync_clr[1:0],  btn_lock_clear};

                if (sync_wr == 3'b111)   clean_wr   <= 1'b1; else if (sync_wr == 3'b000)   clean_wr   <= 1'b0;
                if (sync_rd == 3'b111)   clean_rd   <= 1'b1; else if (sync_rd == 3'b000)   clean_rd   <= 1'b0;
                if (sync_1bit == 3'b111) clean_1bit <= 1'b1; else if (sync_1bit == 3'b000) clean_1bit <= 1'b0;
                if (sync_2bit == 3'b111) clean_2bit <= 1'b1; else if (sync_2bit == 3'b000) clean_2bit <= 1'b0;
                if (sync_fsm == 3'b111)  clean_fsm  <= 1'b1; else if (sync_fsm == 3'b000)  clean_fsm  <= 1'b0;
                if (sync_tamp == 3'b111) clean_tamp <= 1'b1; else if (sync_tamp == 3'b000) clean_tamp <= 1'b0;
                if (sync_clr == 3'b111)  clean_clr  <= 1'b1; else if (sync_clr == 3'b000)  clean_clr  <= 1'b0;
            end

            wr_d   <= clean_wr;
            rd_d   <= clean_rd;
            b1_d   <= clean_1bit;
            b2_d   <= clean_2bit;
            fsm_d  <= clean_fsm;
            tamp_d <= clean_tamp;
            clr_d  <= clean_clr;
        end
    end

    // Positive edge pulse generators (1 clock cycle duration)
    wire pulse_wr         = clean_wr   && !wr_d;
    wire pulse_rd         = clean_rd   && !rd_d;
    wire pulse_inj_1bit   = clean_1bit && !b1_d;
    wire pulse_inj_2bit   = clean_2bit && !b2_d;
    wire pulse_inj_fsm    = clean_fsm  && !fsm_d;
    wire pulse_tamper     = clean_tamp && !tamp_d;
    wire pulse_lock_clear = clean_clr  && !clr_d;

    // -------------------------------------------------------------------------
    // 2. Hardware Fault Injection Configuration
    // -------------------------------------------------------------------------
    wire [CW-1:0] fault_mask = pulse_inj_2bit ? ((18'd1 << 1) | (18'd1 << 3)) :
                               pulse_inj_1bit ? (18'd1 << 3) : {CW{1'b0}};
    wire fault_en = pulse_inj_1bit || pulse_inj_2bit;

    // -------------------------------------------------------------------------
    // 3. Instantiate Core RHBD Memory Controller Top
    // -------------------------------------------------------------------------
    wire [DATA_W-1:0] core_rdata;
    wire              core_rdata_valid;
    wire              core_busy;
    wire              single_err_wire;
    wire              double_err_wire;
    wire              tmr_mismatch_wire;
    wire              no_maj_wire;
    wire              ill_state_wire;
    wire              bad_trans_wire;
    wire              fsm_deg_wire;
    wire              fsm_lock_wire;
    wire              wdog_wire;
    wire              cntr_flt_wire;
    wire              z_busy_wire;
    wire              z_done_wire;
    wire              z_fail_wire;
    wire [15:0]       corr_count_wire;
    wire [15:0]       uncorr_count_wire;

    rhbd_mem_top #(
        .DW_DATA       (DATA_W),
        .AW            (AW),
        .CHK_W         (CHK_W),
        .CW            (CW),
        .DW            (CW),
        .SCRUB_INTERVAL(50_000_000), // 0.5 sec patrol interval in hardware
        .PASSES        (3),
        .T_ERR         (2),
        .T_STATE       (T_STATE)
    ) u_rhbd_top (
        .clk                   (clk_100mhz),
        .rst                   (btn_rst),
        .req_wr                (pulse_wr),
        .req_rd                (pulse_rd),
        .host_addr             (sw_addr),
        .host_wdata            (sw_data),
        .host_rdata            (core_rdata),
        .rdata_valid           (core_rdata_valid),
        .busy                  (core_busy),
        .tamper                (pulse_tamper),
        .lock_clear            (pulse_lock_clear),
        .inject_en             (fault_en),
        .inject_addr           (sw_addr),
        .inject_mask           (fault_mask),
        .fsm_fault_inject      ({2'b0, pulse_inj_fsm}),
        .fsm_code_inject0      ({CW_STATE{1'b0}}),
        .fsm_code_inject1      ({CW_STATE{1'b0}}),
        .fsm_code_inject2      ({CW_STATE{1'b0}}),
        .voter_fault_inject    (3'b0),
        .tamper_fault_inject   (3'b0),
        .zeroize_fault_inject  (1'b0),
        .corrected_err_seen    (),
        .uncorrectable_err_seen(),
        .single_err_seen       (single_err_wire),
        .double_err_seen       (double_err_wire),
        .tmr_mismatch          (tmr_mismatch_wire),
        .tmr_no_majority       (no_maj_wire),
        .tmr_illegal_state     (ill_state_wire),
        .tmr_bad_transition    (bad_trans_wire),
        .fsm_degraded          (fsm_deg_wire),
        .fsm_locked            (fsm_lock_wire),
        .watchdog_timeout      (wdog_wire),
        .zeroize_counter_fault (cntr_flt_wire),
        .zeroize_busy          (z_busy_wire),
        .zeroize_done          (z_done_wire),
        .zeroize_fail          (z_fail_wire),
        .corrected_count       (corr_count_wire),
        .uncorrectable_count   (uncorr_count_wire)
    );

    // Register host read data when valid pulse fires
    reg [DATA_W-1:0] rdata_display_reg;
    always @(posedge clk_100mhz) begin
        if (btn_rst) begin
            rdata_display_reg <= {DATA_W{1'b0}};
        end else if (core_rdata_valid) begin
            rdata_display_reg <= core_rdata;
        end
    end

    assign led_rdata = rdata_display_reg;

    // -------------------------------------------------------------------------
    // 4. LED Pulse Stretchers (~200ms visibility pulse at 100MHz)
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

    assign led_single_err       = (stretch_single > 0);
    assign led_double_err       = (stretch_double > 0);
    assign led_tmr_mismatch     = (stretch_tmr > 0);
    assign led_fsm_locked       = fsm_lock_wire;
    assign led_fsm_degraded     = fsm_deg_wire;
    assign led_no_majority      = no_maj_wire;
    assign led_illegal_state    = ill_state_wire;
    assign led_bad_transition   = bad_trans_wire;
    assign led_watchdog_timeout = wdog_wire;
    assign led_counter_fault    = cntr_flt_wire;
    assign led_zeroize_busy     = z_busy_wire;
    assign led_zeroize_done     = z_done_wire;
    assign led_zeroize_fail     = z_fail_wire;
    assign led_busy             = core_busy;

    // -------------------------------------------------------------------------
    // 5. Four-Digit Seven-Segment Multiplexed Hex Display
    // -------------------------------------------------------------------------
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
