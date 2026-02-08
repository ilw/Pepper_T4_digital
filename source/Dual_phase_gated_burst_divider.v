`timescale 1ns / 1ps

module Dual_phase_gated_burst_divider (
    input wire [11:0] PHASE1DIV1_sync,
    input wire [3:0] PHASE1COUNT_sync,
    input wire [9:0] PHASE2COUNT_sync,
    input wire HF_CLK,
    input wire ENSAMP_sync,
    input wire NRST_sync,
    input wire TEMP_RUN,

    output wire SAMPLE_CLK,
    output wire phase
);

    // Internal registers
    reg [11:0] div_counter;
    reg [3:0] repeat_counter;
    reg is_phase_2;
    reg div_clk_reg;
    
    // Enable when either sampling or temperature monitoring is active
    wire enable;
    assign enable = ENSAMP_sync | TEMP_RUN;
    
    // Phase output: high during Phase 2 (silence)
    assign phase = is_phase_2;
    
    // Output logic
    // Passthrough mode when PHASE1DIV1_sync == 0, otherwise use divided clock
    // Gated by enable signal
    assign SAMPLE_CLK = (PHASE1DIV1_sync == 12'd0) ? (HF_CLK & enable) : (div_clk_reg & enable);
    
    // Main divider logic
    always @(posedge HF_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            div_counter <= 12'd0;
            repeat_counter <= 4'd0;
            is_phase_2 <= 1'b0;
            div_clk_reg <= 1'b0;
        end else if (!enable) begin
            // Reset when disabled
            div_counter <= 12'd0;
            repeat_counter <= 4'd0;
            is_phase_2 <= 1'b0;
            div_clk_reg <= 1'b0;
        end else if (PHASE1DIV1_sync != 12'd0) begin
            // Divider active (not in passthrough mode)
            if (div_counter == 12'd0) begin
                
                if (is_phase_2) begin
                    // Exit Phase 2 (silence) and start new burst
                    is_phase_2 <= 1'b0;
                    repeat_counter <= 4'd0;
                    div_counter <= PHASE1DIV1_sync - 1'b1;
                    div_clk_reg <= 1'b1; // Start with rising edge
                end else begin
                    // Phase 1 (active burst): toggle clock
                    div_clk_reg <= ~div_clk_reg;
                    div_counter <= PHASE1DIV1_sync - 1'b1;
                    
                    // Count full pulses (on falling edge)
                    if (div_clk_reg == 1'b1) begin
                        if (repeat_counter >= PHASE1COUNT_sync - 1'b1) begin
                            if (PHASE2COUNT_sync == 10'd0) begin
                                // Continuous mode: no silence, immediate restart
                                repeat_counter <= 4'd0;
                            end else begin
                                // Enter Phase 2 (silence)
                                is_phase_2 <= 1'b1;
                                div_counter <= PHASE2COUNT_sync - 1'b1;
                                div_clk_reg <= 1'b0;
                            end
                        end else begin
                            repeat_counter <= repeat_counter + 1'b1;
                        end
                    end
                end
                
            end else begin
                // Count down
                div_counter <= div_counter - 1'b1;
            end
        end
    end

endmodule
