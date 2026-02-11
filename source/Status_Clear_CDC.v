`timescale 1ns / 1ps

module Status_Clear_CDC (
    // Destination clock domain (always running)
    input wire HF_CLK,
    input wire NRST_sync,

    // Source domain signals (SCK domain, held stable while request inflight)
    input wire status_clr_req_tgl_sck,
    input wire [7:0] status_clr_lo_sck,
    input wire [5:0] status_clr_hi_sck,

    // Ack toggle back to SCK domain (will be synchronized there)
    output wire status_clr_ack_tgl_hf,

    // Clear pulse + mask in HF_CLK domain
    output wire status_clr_pulse,
    output wire [13:0] status_clr_mask
);

    // Synchronize toggle request into HF_CLK domain
    reg [1:0] req_ff;
    reg req_prev;

    // Synchronize mask bits into HF_CLK domain (mask is static during inflight)
    reg [7:0] lo_ff1, lo_ff2;
    reg [5:0] hi_ff1, hi_ff2;

    reg ack_tgl_reg;
    reg pulse_reg;
    reg pending;
    reg [1:0] pending_cnt;

    wire req_edge;
    assign req_edge = (req_ff[1] ^ req_prev);

    always @(posedge HF_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            req_ff <= 2'b00;
            req_prev <= 1'b0;
            lo_ff1 <= 8'h00;
            lo_ff2 <= 8'h00;
            hi_ff1 <= 6'h00;
            hi_ff2 <= 6'h00;
            ack_tgl_reg <= 1'b0;
            pulse_reg <= 1'b0;
            pending <= 1'b0;
            pending_cnt <= 2'b00;
        end else begin
            // Toggle sync
            req_ff <= {req_ff[0], status_clr_req_tgl_sck};

            // Mask sync
            lo_ff1 <= status_clr_lo_sck;
            lo_ff2 <= lo_ff1;
            hi_ff1 <= status_clr_hi_sck;
            hi_ff2 <= hi_ff1;

            // Edge detect
            req_prev <= req_ff[1];

            // Default: no pulse
            pulse_reg <= 1'b0;

            // When a request edge arrives, arm a pending clear.
            // We delay the clear pulse so the synchronized mask (hi_ff2/lo_ff2)
            // is guaranteed valid and stable when Status_Monitor samples it.
            if (req_edge) begin
                pending <= 1'b1;
                pending_cnt <= 2'b00;
            end else if (pending) begin
                pending_cnt <= pending_cnt + 1'b1;
                if (pending_cnt == 2'b10) begin
                    // Fire pulse + ack after ~2 HF_CLK cycles of mask syncing
                    pulse_reg <= 1'b1;
                    ack_tgl_reg <= ~ack_tgl_reg;
                    pending <= 1'b0;
                end
            end
        end
    end

    assign status_clr_ack_tgl_hf = ack_tgl_reg;
    assign status_clr_pulse = pulse_reg;
    assign status_clr_mask = {hi_ff2, lo_ff2};

endmodule
