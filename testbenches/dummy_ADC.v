`timescale 1ns / 1ps

// Simple behavioral ADC model for integration testing.
// - When START is high, it will periodically assert DONE and update RESULT
// - CHANNEL is treated as one-hot or binary depending on testbench usage; here we just hash it
module dummy_ADC #(
    parameter DATA_FILE = "",
    parameter CONVERSION_CYCLES = 5
)(
    input  wire        CLK,
    input  wire        NRST,
    input  wire        START,
    input  wire [7:0]  CHANNEL,
    output reg         DONE,
    output reg  [15:0] RESULT
);

    integer cnt;

    always @(posedge CLK or negedge NRST) begin
        if (!NRST) begin
            cnt <= 0;
            DONE <= 1'b0;
            RESULT <= 16'h0000;
        end else begin
            DONE <= 1'b0;

            if (START) begin
                if (cnt >= (CONVERSION_CYCLES-1)) begin
                    cnt <= 0;
                    DONE <= 1'b1;
                    // Deterministic pseudo-result for debugging
                    RESULT <= {8'hA5, CHANNEL};
                end else begin
                    cnt <= cnt + 1;
                end
            end else begin
                cnt <= 0;
            end
        end
    end

    // DATA_FILE intentionally unused in this simple model
    wire _unused_data_file = (DATA_FILE == "");

endmodule

