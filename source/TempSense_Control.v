`timescale 1ns / 1ps

// TempSense_Control
// - Arms on rising edge of ENMONTSENSE_sync (HF_CLK domain)
// - Asserts temp_run to enable SAMPLE_CLK and ADC (nARST) while conversion is pending
// - Drops temp_run after first DONE (one-shot), even if ENMONTSENSE_sync stays high
// - Re-arms only after ENMONTSENSE_sync goes low then high again
module TempSense_Control (
    input  wire HF_CLK,
    input  wire NRST_sync,
    input  wire ENMONTSENSE_sync,
    input  wire DONE,

    output wire temp_run
);

    reg en_prev;
    reg run_reg;
    reg [1:0] done_ff;

    always @(posedge HF_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            en_prev <= 1'b0;
            run_reg <= 1'b0;
            done_ff <= 2'b00;
        end else begin
            en_prev <= ENMONTSENSE_sync;
            done_ff <= {done_ff[0], DONE};

            // Default: if ENMONTSENSE is low, ensure not running.
            if (!ENMONTSENSE_sync) begin
                run_reg <= 1'b0;
                done_ff <= 2'b00; // clear stale DONE history while idle
            end else begin
                // Rising edge arms a new one-shot conversion window.
                if (ENMONTSENSE_sync && !en_prev) begin
                    run_reg <= 1'b1;
                    done_ff <= 2'b00; // ignore any stale DONE history at start
                end

                // When running, stop after first DONE (one-shot).
                if (run_reg && done_ff[1]) begin
                    run_reg <= 1'b0;
                end
            end
        end
    end

    assign temp_run = run_reg;

endmodule

