module gated_burst_divider #(
    parameter DIV_WIDTH = 10,
    parameter REP_WIDTH = 4,
	parameter PHASE2_WIDTH = 10
)(
    input  wire                 clk,           // 1MHz Master Clock
    input  wire                 reset,         // Asynchronous Reset
    input  wire                 enable_async,  // Enable from different domain
    input  wire [DIV_WIDTH-1:0] m1_value,      // Half-period (0 = Passthrough)
    input  wire [PHASE2_WIDTH-1:0] m2_value,      // Duration of silence
    input  wire [REP_WIDTH-1:0] m1_repeat_limit, // Number of FULL pulses
    output wire                 clk_out,       // Final Output
    output wire                 phase_status   // 0 = Active, 1 = Silent
);

    // --- Synchronizer for Enable ---
    reg en_sync_0, en_sync_1;
    always @(posedge clk or posedge reset) begin
        if (reset) {en_sync_0, en_sync_1} <= 2'b00;
        else       {en_sync_0, en_sync_1} <= {enable_async, en_sync_0};
    end

    reg [DIV_WIDTH-1:0] div_counter;    
    reg [REP_WIDTH-1:0] repeat_counter; 
    reg                 is_phase_2;    
    reg                 div_clk_reg; 

    assign phase_status = is_phase_2;

    // --- Output Multiplexer ---
    // If m1 is 0: Passthrough raw clk. 
    // Otherwise: Use the divided/gated clock.
    // Both are gated by the synchronized enable.
    assign clk_out = (m1_value == 0) ? (clk & en_sync_1) : (div_clk_reg & en_sync_1);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            div_counter    <= 0;
            repeat_counter <= 0;
            is_phase_2     <= 1'b0;
            div_clk_reg    <= 1'b0;
        end else if (!en_sync_1) begin
            div_counter    <= 0;
            repeat_counter <= 0;
            is_phase_2     <= 1'b0;
            div_clk_reg    <= 1'b0;
        end else if (m1_value != 0) begin
            if (div_counter == 0) begin
                
                if (is_phase_2) begin
                    // Exit Phase 2 (Silence) and start a new burst
                    is_phase_2     <= 1'b0;
                    repeat_counter <= 0;
                    div_counter    <= m1_value - 1;
                    div_clk_reg    <= 1'b1; // Start with a rising edge
                end 
                else begin
                    // Currently in Phase 1 (Active Burst)
                    div_clk_reg <= ~div_clk_reg;
                    div_counter <= m1_value - 1;

                    // Increment pulse count only on the completion of a full cycle
                    // (When the signal transitions from High to Low)
                    if (div_clk_reg == 1'b1) begin
                        if (repeat_counter >= m1_repeat_limit - 1) begin
                            if (m2_value == 0) begin
                                // No silence: Immediate restart
                                repeat_counter <= 0;
                            end else begin
                                // Enter Phase 2 (Silence)
                                is_phase_2  <= 1'b1;
                                div_counter <= m2_value - 1;
                                div_clk_reg <= 1'b0; 
                            end
                        end else begin
                            repeat_counter <= repeat_counter + 1'b1;
                        end
                    end
                end

            end else begin
                div_counter <= div_counter - 1'b1;
            end
        end
    end
endmodule