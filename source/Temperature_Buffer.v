`timescale 1ns / 1ps

module Temperature_Buffer (
    input wire ENMONTSENSE_sync,
    input wire DONE,
    input wire NRST_sync,
    input wire SAMPLE_CLK,
    input wire [15:0] RESULT,
    output wire [15:0] TEMPVAL
);

    reg [15:0] temp_reg;
    reg enmontsense_prev;
    reg armed;

    always @(posedge SAMPLE_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            temp_reg <= 16'b0;
            enmontsense_prev <= 1'b0;
            armed <= 1'b0;
        end else begin
            // One-shot arm on rising edge of ENMONTSENSE_sync
            enmontsense_prev <= ENMONTSENSE_sync;

            if (ENMONTSENSE_sync && !enmontsense_prev) begin
                armed <= 1'b1;
            end else if (!ENMONTSENSE_sync) begin
                armed <= 1'b0;
            end

            // Capture only once per ENMONTSENSE_sync assertion
            if (ENMONTSENSE_sync && armed && DONE) begin
                temp_reg <= RESULT;
                armed <= 1'b0;
            end
        end
    end

    assign TEMPVAL = temp_reg;

endmodule
