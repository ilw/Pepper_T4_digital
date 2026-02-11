`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Behavioral mock of the Pepper ns_sar_v2 noise-shaping SAR ADC.
//
// Port-compatible with the real ns_sar_v2 for use in digital-only simulations
// without requiring the TSMC standard-cell library.
//
// Timing model (matches real ADC netlist behavior):
//   SAR mode  (OSR=0): DONE is permanently high after reset release.
//                       RESULT updates every SAMPLE_CLK rising edge.
//   NS  mode  (OSR>0): **Startup**: DONE pulses high for 1 cycle on the very
//                       first posedge after nARST deasserts (matches the real
//                       ADC's decimator state[5] preset → immediate trigger_b).
//                       **Steady-state**: DONE pulses every (4*OSR+2) clocks.
//                       RESULT updates on the same posedge as DONE.
//                       (The 1-cycle visibility delay inherent in non-blocking
//                       assignments models the real ADC's registered CIC_DONE.)
//   Reset (nARST=0):   DONE is forced low; all state is cleared.
//
// The system-level DONE_QUAL in TLM.v discards the startup DONE so that
// downstream blocks (FIFO, Temperature_Buffer) only see valid conversions.
//
// Other simplifications:
//   - OVERFLOW is not modelled (always low).
//   - RESULT values are synthetic (incrementing counter + GAIN barrel shift),
//     not derived from analog inputs.
////////////////////////////////////////////////////////////////////////////////

module ns_sar_v2 (
    // ---- Digital control ----
    input  wire        SAMPLE_CLK,
    input  wire        nARST,
    input  wire [3:0]  OSR,
    input  wire [3:0]  GAIN,
    input  wire        ANALOG_ENABLE,
    input  wire        CHP_EN,
    input  wire        DWA_EN,
    input  wire        MES_EN,
    input  wire        EXT_CLK,
    input  wire        EXT_CLK_EN,
    input  wire        DONE_OVERRIDE,
    input  wire        DONE_OVERRIDE_VAL,
    input  wire        ANALOG_RESET_OVERRIDE,
    input  wire        ANALOG_RESET_OVERRIDE_VAL,
    input  wire [2:0]  DIGITAL_DEBUG_SELECT,
    input  wire [2:0]  ANALOG_TEST_SELECT,
    input  wire [7:0]  ADC_SPARE,

    // ---- Analog interface (unused in behavioral mock) ----
    input  wire        VIP,
    input  wire        VIN,
    input  wire        REFP,
    input  wire        REFN,
    input  wire        REFC,
    input  wire        IBIAS_500N_PTAT,

    // ---- Supply (unused in behavioral mock) ----
    input  wire        DVDD,
    input  wire        DGND,

    // ---- Digital outputs ----
    output wire [15:0] RESULT,
    output wire        DONE,
    output wire        OVERFLOW,
    output wire        ANALOG_TEST,
    output wire        DIGITAL_DEBUG
);

    // =================================================================
    // Conversion length: SAR mode = 1 cycle, NS mode = 4*OSR + 2 cycles
    // =================================================================
    wire        sar_mode = (OSR == 4'b0000);
    wire [5:0]  conv_len = sar_mode ? 6'd1 : ({OSR, 2'b00} + 6'd2);

    // =================================================================
    // Internal state
    // =================================================================
    reg [5:0]   cycle_count;    // Counts 0 .. conv_len-1
    // Keep NS-mode DONE state separate from SAR mode so that switching
    // OSR from 0->nonzero does not create a spurious DONE pulse.
    reg         done_reg_ns;    // DONE pulse for NS mode (registered, via NBA)
    reg [15:0]  result_reg;     // Holds output result
    reg         overflow_reg;

    // Deterministic result counter (10-bit, wraps)
    reg [9:0]   conversion_counter;

    // Startup flag: set by async reset, cleared on first active posedge.
    // Models the real ADC's state[5] preset behavior where the decimator
    // counter starts at 0 = terminal value, causing an immediate DONE on
    // the first clock edge after reset deasserts.
    reg         first_conv;

    // =================================================================
    // Gain barrel-shift model
    // =================================================================
    // Real ADC: 18-bit CIC output shifted right by (15-GAIN) into 16 bits.
    // Mock: place 10-bit counter into an 18-bit field and apply same shift.
    function [15:0] apply_gain;
        input [9:0]  raw_10b;
        input [3:0]  gain;
        reg   [17:0] wide;
        begin
            wide = {raw_10b, 8'h00};     // 10-bit value in bits [17:8]
            apply_gain = wide >> (4'd15 - gain);
        end
    endfunction

    // Ensure we never output 0x0000 (avoids "looks like no data" confusion).
    // This keeps the pattern deterministic but guarantees non-zero RESULT.
    function [15:0] force_nonzero;
        input [15:0] v;
        begin
            force_nonzero = (v == 16'h0000) ? 16'h0001 : v;
        end
    endfunction

    // =================================================================
    // Main conversion state machine
    //
    // Behavioral contract for digital integration:
    // - OSR=0 (SAR): DONE is high whenever enabled; RESULT updates every clk.
    // - OSR>0 (NS): Startup DONE on 1st active cycle, then DONE pulses once
    //               every conv_len clocks; RESULT updates on DONE edge.
    // =================================================================
    always @(posedge SAMPLE_CLK or negedge nARST) begin
        if (!nARST) begin
            cycle_count        <= 6'd0;
            done_reg_ns        <= 1'b0;
            first_conv         <= 1'b1;
            result_reg         <= 16'h0000;
            overflow_reg       <= 1'b0;
            conversion_counter <= 10'd0;
        end else begin
            if (sar_mode) begin
                // ---- SAR bypass: DONE permanently high, result every cycle ----
                // Also force NS-mode state back to a clean start, so that if OSR
                // later changes to a non-zero value while nARST stays high, the
                // NS conversion window restarts deterministically.
                cycle_count        <= 6'd0;
                done_reg_ns        <= 1'b0;
                first_conv         <= 1'b0;
                conversion_counter <= conversion_counter + 10'd1;
                // Use the *next* counter value so RESULT changes immediately
                // on the first cycle after reset deassert.
                result_reg         <= force_nonzero(apply_gain(conversion_counter + 10'd1, GAIN));
            end else begin
                // ---- NS mode: CIC decimation window ----
                done_reg_ns <= 1'b0;
                first_conv  <= 1'b0; // Clear startup flag after first active cycle

                if (cycle_count == conv_len - 6'd1) begin
                    // End of conversion window — DONE pulse and update RESULT
                    cycle_count        <= 6'd0;
                    conversion_counter <= conversion_counter + 10'd1;
                    done_reg_ns        <= 1'b1;
                    // Use next counter value so RESULT changes on DONE edge
                    result_reg         <= force_nonzero(apply_gain(conversion_counter + 10'd1, GAIN));
                end else begin
                    cycle_count <= cycle_count + 6'd1;
                end
            end
        end
    end

    // =================================================================
    // Output assignments
    // =================================================================
    // Startup DONE: combinational pulse on the first active posedge in NS mode.
    // This matches the real ADC where state[4:0]=0 after reset = terminal value,
    // so completion_flag is immediately true and CIC_DONE captures 1 at the
    // first clock edge.  The combinational nature ensures downstream processes
    // in the same active region (e.g. DONE_QUAL) see it before NBA clears it.
    wire startup_done = first_conv & ~sar_mode;

    // DONE must be low during reset, regardless of mode.
    assign DONE     = (!nARST) ? 1'b0 : (sar_mode ? 1'b1 : (done_reg_ns | startup_done));
    assign RESULT   = result_reg;
    assign OVERFLOW = overflow_reg;

    // Analog/debug outputs — tied inactive
    assign ANALOG_TEST  = 1'b0;
    assign DIGITAL_DEBUG = 1'b0;

    // Suppress "unused" warnings for analog/test/debug inputs
    wire _unused = &{VIP, VIN, REFP, REFN, REFC, IBIAS_500N_PTAT,
                     DVDD, DGND, ANALOG_ENABLE, CHP_EN, DWA_EN, MES_EN,
                     EXT_CLK, EXT_CLK_EN, DONE_OVERRIDE, DONE_OVERRIDE_VAL,
                     ANALOG_RESET_OVERRIDE, ANALOG_RESET_OVERRIDE_VAL,
                     DIGITAL_DEBUG_SELECT, ANALOG_TEST_SELECT, ADC_SPARE};

endmodule
