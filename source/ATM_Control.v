`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// ATM_Control — Predictive channel sequencer
//
// Instead of reacting to the ADC's DONE signal (which has a 1-cycle
// registration delay, causing an off-by-1 error), this block maintains
// its own conversion-length counter based on the OSR code.  The mux
// channel is switched at the same cycle as the ADC's internal trigger,
// so that the next channel is already stable when the new conversion
// window begins.
//
// Because the mux switches 1 cycle BEFORE DONE appears externally,
// a pipelined copy of the channel (ATMCHSEL_DATA) and frame-boundary
// flag (LASTWORD) are provided, aligned with DONE, for use by the FIFO.
//
// Conversion length:
//   SAR mode  (OSR=0): 1 SAMPLE_CLK cycle per conversion
//   NS  mode  (OSR>0): 4*OSR + 2 SAMPLE_CLK cycles per conversion
////////////////////////////////////////////////////////////////////////////////

module ATM_Control (
    input  wire        SAMPLE_CLK,
    input  wire        ENSAMP_sync,
    input  wire [7:0]  CHEN_sync,
    input  wire [3:0]  OSR_sync,        // ADC oversampling ratio (synced)
    input  wire        NRST_sync,
    input  wire        ENLOWPWR_sync,

    output wire [7:0]  ATMCHSEL,        // Mux select (switches at prediction time)
    output wire [7:0]  ATMCHSEL_DATA,   // Data channel (1-cycle delayed, aligned with DONE)
    output wire [7:0]  CHSEL,
    output wire        LASTWORD         // Frame-end flag (1-cycle delayed, aligned with DONE)
);

    // =================================================================
    // Conversion length calculation
    // =================================================================
    wire        sar_mode = (OSR_sync == 4'b0000);
    wire [5:0]  conv_len = sar_mode ? 6'd1 : ({OSR_sync, 2'b00} + 6'd2);
    wire [5:0]  terminal_count = conv_len - 6'd1;

    // =================================================================
    // Internal registers
    // =================================================================
    reg [7:0]  atmchsel_mux;       // Current mux selection (one-hot)
    reg [7:0]  atmchsel_data_reg;  // 1-cycle delayed copy for FIFO
    reg [2:0]  current_channel;    // 0-7 channel index
    reg        lastword_reg;       // Registered LASTWORD aligned with DONE
    reg [5:0]  cycle_count;        // Prediction counter

    // =================================================================
    // Output assignments
    // =================================================================
    assign ATMCHSEL      = atmchsel_mux;
    assign ATMCHSEL_DATA = atmchsel_data_reg;
    assign CHSEL         = ENLOWPWR_sync ? atmchsel_mux : CHEN_sync;
    assign LASTWORD      = lastword_reg;

    // =================================================================
    // Channel navigation helpers
    // =================================================================

    // Find next enabled channel (circular search from 'current')
    function [2:0] next_enabled_channel;
        input [2:0] current;
        input [7:0] enabled;
        integer i;
        reg [2:0] idx;
        reg       found;
        begin
            // Cadence-friendly implementation:
            // - no '%' operator
            // - no modification of loop variable to break
            next_enabled_channel = current;
            idx   = current;
            found = 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                // advance with wrap
                idx = (idx == 3'd7) ? 3'd0 : (idx + 3'd1);
                if (!found && enabled[idx]) begin
                    next_enabled_channel = idx;
                    found = 1'b1;
                end
            end
        end
    endfunction

    // Highest-index enabled channel (deterministic frame boundary)
    function [2:0] last_enabled_channel;
        input [7:0] enabled;
        begin
            if (enabled[7])      last_enabled_channel = 3'd7;
            else if (enabled[6]) last_enabled_channel = 3'd6;
            else if (enabled[5]) last_enabled_channel = 3'd5;
            else if (enabled[4]) last_enabled_channel = 3'd4;
            else if (enabled[3]) last_enabled_channel = 3'd3;
            else if (enabled[2]) last_enabled_channel = 3'd2;
            else if (enabled[1]) last_enabled_channel = 3'd1;
            else                 last_enabled_channel = 3'd0;
        end
    endfunction

    // One-hot encoding from channel index
    function [7:0] encode_one_hot;
        input [2:0] ch;
        begin
            case (ch)
                3'd0: encode_one_hot = 8'b00000001;
                3'd1: encode_one_hot = 8'b00000010;
                3'd2: encode_one_hot = 8'b00000100;
                3'd3: encode_one_hot = 8'b00001000;
                3'd4: encode_one_hot = 8'b00010000;
                3'd5: encode_one_hot = 8'b00100000;
                3'd6: encode_one_hot = 8'b01000000;
                3'd7: encode_one_hot = 8'b10000000;
            endcase
        end
    endfunction

    // =================================================================
    // Prediction counter & channel switch
    // =================================================================
    wire switch_now = (cycle_count == terminal_count);

    always @(posedge SAMPLE_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            cycle_count        <= 6'd0;
            current_channel    <= 3'd0;
            atmchsel_mux       <= 8'b0;
            atmchsel_data_reg  <= 8'b0;
            lastword_reg       <= 1'b0;
        end else if (ENSAMP_sync) begin
            // -----------------------------------------------------------
            // Pipeline: capture outgoing channel state for FIFO.
            // These appear 1 cycle after the mux switch, aligned with
            // the ADC's registered DONE output.
            // -----------------------------------------------------------
            atmchsel_data_reg <= atmchsel_mux;
            lastword_reg      <= (atmchsel_mux != 8'b0) &&
                                 (current_channel == last_enabled_channel(CHEN_sync));

            // -----------------------------------------------------------
            // Counter: counts 0 .. terminal_count then resets.
            // On init (mux==0) the counter also resets to 0 so the
            // first conversion window is the full conv_len cycles.
            // -----------------------------------------------------------
            if (switch_now || (atmchsel_mux == 8'b0))
                cycle_count <= 6'd0;
            else
                cycle_count <= cycle_count + 6'd1;

            // -----------------------------------------------------------
            // Channel switch: at terminal count or on first cycle
            // -----------------------------------------------------------
            if (switch_now || (atmchsel_mux == 8'b0)) begin
                if (atmchsel_mux == 8'b0) begin
                    // First channel after enable — start from lowest enabled
                    current_channel <= next_enabled_channel(3'd7, CHEN_sync);
                    atmchsel_mux    <= encode_one_hot(next_enabled_channel(3'd7, CHEN_sync));
                end else begin
                    // Advance to next enabled channel
                    current_channel <= next_enabled_channel(current_channel, CHEN_sync);
                    atmchsel_mux    <= encode_one_hot(next_enabled_channel(current_channel, CHEN_sync));
                end
            end
        end else begin
            // Not sampling — clear outputs
            atmchsel_mux       <= 8'b0;
            atmchsel_data_reg  <= 8'b0;
            lastword_reg       <= 1'b0;
            cycle_count        <= 6'd0;
        end
    end

endmodule
