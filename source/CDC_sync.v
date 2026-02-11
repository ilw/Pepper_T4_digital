`timescale 1ns / 1ps

module CDC_sync (
    input wire NRST,
    input wire ENSAMP,
    input wire CFG_CHNGE,
    input wire [7:0] AFERSTCH,
    input wire FIFO_OVERFLOW,
    input wire FIFO_UNDERFLOW,
    input wire [7:0] SATDETECT,
    input wire ADCOVERFLOW,
    input wire [11:0] PHASE1DIV1,
    input wire [3:0] PHASE1COUNT,
    input wire [9:0] PHASE2COUNT,
    input wire [7:0] CHEN,
    input wire ENLOWPWR,
    input wire ENMONTSENSE,
    input wire [3:0] ADCOSR,
    input wire HF_CLK,
    
    output wire NRST_sync,
    output wire ENSAMP_sync,
    output wire CFG_CHNGE_sync,
    output wire [7:0] AFERSTCH_sync,
    output wire FIFO_OVERFLOW_sync,
    output wire FIFO_UNDERFLOW_sync,
    output wire [7:0] SATDETECT_sync,
    output wire ADCOVERFLOW_sync,
    output wire [11:0] PHASE1DIV1_sync,
    output wire [3:0] PHASE1COUNT_sync,
    output wire [9:0] PHASE2COUNT_sync,
    output wire [7:0] CHEN_sync,
    output wire ENLOWPWR_sync,
    output wire ENMONTSENSE_sync,
    output wire [3:0] ADCOSR_sync
);

    // 1. Reset synchronization (Asynchronous assert, Synchronous deassert)
    // When NRST (async) goes low, reset goes low immediately.
    // When NRST goes high, it's synchronized to HF_CLK before releasing reset.
    reg nrst_meta, nrst_sync_reg;
    always @(posedge HF_CLK or negedge NRST) begin
        if (!NRST) begin
            nrst_meta <= 1'b0;
            nrst_sync_reg <= 1'b0;
        end else begin
            nrst_meta <= 1'b1;
            nrst_sync_reg <= nrst_meta;
        end
    end
    assign NRST_sync = nrst_sync_reg;

    // 2. Control Signal Synchronization (2-stage Flip-Flop)
    reg [1:0] ensamp_ff;
    reg [1:0] enlowpwr_ff;
    reg [1:0] enmontsense_ff;
    reg [1:0] adcoverflow_ff;
    
    // Buses (quasi-static or from stable domains)
    reg [7:0]  aferstch_ff1, aferstch_ff2;
    reg        fifo_overflow_ff1, fifo_overflow_ff2;
    reg        fifo_underflow_ff1, fifo_underflow_ff2;
    reg [7:0]  satdetect_ff1, satdetect_ff2;

    always @(posedge HF_CLK or negedge NRST) begin
        if (!NRST) begin
            ensamp_ff <= 2'b00;
            enlowpwr_ff <= 2'b00;
            enmontsense_ff <= 2'b00;
            adcoverflow_ff <= 2'b00;
            
            aferstch_ff1 <= 8'b0;       aferstch_ff2 <= 8'b0;
            fifo_overflow_ff1 <= 0;     fifo_overflow_ff2 <= 0;
            fifo_underflow_ff1 <= 0;    fifo_underflow_ff2 <= 0;
            satdetect_ff1 <= 8'b0;      satdetect_ff2 <= 8'b0;
        end else begin
            // Single bit synchronizers
            ensamp_ff <= {ensamp_ff[0], ENSAMP};
            enlowpwr_ff <= {enlowpwr_ff[0], ENLOWPWR};
            enmontsense_ff <= {enmontsense_ff[0], ENMONTSENSE};
            adcoverflow_ff <= {adcoverflow_ff[0], ADCOVERFLOW};
            
            // Bus/Signal synchronizers (Stage 1)
            aferstch_ff1 <= AFERSTCH;
            fifo_overflow_ff1 <= FIFO_OVERFLOW;
            fifo_underflow_ff1 <= FIFO_UNDERFLOW;
            satdetect_ff1 <= SATDETECT;
            
            // Stage 2
            aferstch_ff2 <= aferstch_ff1;
            fifo_overflow_ff2 <= fifo_overflow_ff1;
            fifo_underflow_ff2 <= fifo_underflow_ff1;
            satdetect_ff2 <= satdetect_ff1;
        end
    end

    // Assign Outputs
    assign ENSAMP_sync        = ensamp_ff[1];
    assign ENLOWPWR_sync      = enlowpwr_ff[1];
    assign ENMONTSENSE_sync   = enmontsense_ff[1];
    assign ADCOVERFLOW_sync   = adcoverflow_ff[1];
    
    assign AFERSTCH_sync       = aferstch_ff2;
    assign FIFO_OVERFLOW_sync  = fifo_overflow_ff2;
    assign FIFO_UNDERFLOW_sync = fifo_underflow_ff2;
    assign SATDETECT_sync      = satdetect_ff2;
    
    // Area reduction: these configuration buses are no longer synchronized.
    // They are passed through directly.
    //
    // System-level requirement:
    // - Only update PHASE1DIV1/PHASE1COUNT/PHASE2COUNT/CHEN/ADCOSR when the
    //   sampling path is disabled (ENSAMP low) to avoid multi-bit CDC hazards.
    // - AFERSTCH remains fully synchronized (2-stage) and can be modified even
    //   when ENSAMP is high.
    assign PHASE1DIV1_sync     = PHASE1DIV1;
    assign PHASE1COUNT_sync    = PHASE1COUNT;
    assign PHASE2COUNT_sync    = PHASE2COUNT;
    assign CHEN_sync           = CHEN;
    assign ADCOSR_sync         = ADCOSR;
    
    // CFG_CHNGE_sync logic removed as requested/unused
    assign CFG_CHNGE_sync = 1'b0; // Output tied low

endmodule
