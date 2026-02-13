`timescale 1ns / 1ps

module FIFO #(
    parameter FRAME_DEPTH = 16  // Number of 128-bit frames (must be power of 2)
)(
    input wire [15:0] RESULT,
    input wire DONE,
    input wire SAMPLE_CLK,
    input wire NRST_sync,
    input wire [7:0] ATMCHSEL,
    input wire LASTWORD,
    input wire FIFO_POP,
    input wire [4:0] FIFOWATERMARK,
    input wire SCK,
    input wire ENSAMP_sync,

    output wire DATA_RDY,
    output wire FIFO_OVERFLOW,
    output reg [127:0] ADC_data,
    output wire FIFO_UNDERFLOW
);

    localparam ADDR_WIDTH = $clog2(FRAME_DEPTH);
    // Use an extra pointer bit so full vs empty is distinguishable after wrap.
    localparam PTR_WIDTH  = ADDR_WIDTH + 1;
    
    // Frame memory
    reg [127:0] mem [0:FRAME_DEPTH-1];
    
    // Write domain (SAMPLE_CLK)
    reg [PTR_WIDTH-1:0] write_ptr;
    reg [PTR_WIDTH-1:0] write_ptr_gray;
    reg [PTR_WIDTH-1:0] read_ptr_sync;
    reg [PTR_WIDTH-1:0] read_ptr_sync_bin;
    reg [ADDR_WIDTH-1:0] read_ptr_sync_prev_idx;
    
    // Read domain (SCK)
    reg [PTR_WIDTH-1:0] read_ptr;
    reg [PTR_WIDTH-1:0] read_ptr_gray;
    reg [PTR_WIDTH-1:0] write_ptr_sync;
    reg [PTR_WIDTH-1:0] write_ptr_sync_bin;
    
    // Frame count and flags
    reg [PTR_WIDTH:0] frame_count;
    reg frames_available;
    
    // Frame pop edge detection
    reg frame_pop_sync1, frame_pop_sync2, frame_pop_prev;
    wire frame_pop_edge;
    
    // Clean disable/reset in SCK domain when ENSAMP_sync drops:
    // Assert reset asynchronously on ENSAMP_sync deassert; release synchronously to SCK.
    reg [1:0] ensamp_rst_ff;
    wire ensamp_rstn_sck;

    integer i;
    
    //========================================================================
    // GRAY CODE CONVERSION
    //========================================================================
    
    function [PTR_WIDTH-1:0] bin_to_gray;
        input [PTR_WIDTH-1:0] bin;
        begin
            bin_to_gray = bin ^ (bin >> 1);
        end
    endfunction
    
    function [PTR_WIDTH-1:0] gray_to_bin;
        input [PTR_WIDTH-1:0] gray;
        integer j;
        begin
            gray_to_bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (j = PTR_WIDTH-2; j >= 0; j = j - 1) begin
                gray_to_bin[j] = gray_to_bin[j+1] ^ gray[j];
            end
        end
    endfunction
    
    //========================================================================
    // WRITE DOMAIN (SAMPLE_CLK)
    //========================================================================
    
    // Synchronize read pointer to write domain
    reg [PTR_WIDTH-1:0] read_ptr_gray_sync1;
    always @(posedge SAMPLE_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            read_ptr_gray_sync1   <= {PTR_WIDTH{1'b0}};
            read_ptr_sync         <= {PTR_WIDTH{1'b0}};
            read_ptr_sync_prev_idx<= {ADDR_WIDTH{1'b0}};
        end else if (!ENSAMP_sync) begin
            // When disabled, reset sync state to a clean baseline
            read_ptr_gray_sync1   <= {PTR_WIDTH{1'b0}};
            read_ptr_sync         <= {PTR_WIDTH{1'b0}};
            read_ptr_sync_prev_idx<= {ADDR_WIDTH{1'b0}};
        end else begin
            read_ptr_gray_sync1 <= read_ptr_gray;
            read_ptr_sync       <= read_ptr_gray_sync1;
            read_ptr_sync_prev_idx <= read_ptr_sync_bin[ADDR_WIDTH-1:0];
        end
    end
    
    always @(*) begin
        read_ptr_sync_bin = gray_to_bin(read_ptr_sync);
    end
    
    // Synchronize frame_pop for edge detection
    always @(posedge SAMPLE_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            frame_pop_sync1 <= 1'b0;
            frame_pop_sync2 <= 1'b0;
            frame_pop_prev  <= 1'b0;
        end else if (!ENSAMP_sync) begin
            frame_pop_sync1 <= 1'b0;
            frame_pop_sync2 <= 1'b0;
            frame_pop_prev  <= 1'b0;
        end else begin
            frame_pop_sync1 <= FIFO_POP;
            frame_pop_sync2 <= frame_pop_sync1;
            frame_pop_prev  <= frame_pop_sync2;
        end
    end
    assign frame_pop_edge = frame_pop_sync2 && !frame_pop_prev;
    
    // Calculate frame count
    always @(*) begin
        frame_count = {1'b0, write_ptr} - {1'b0, read_ptr_sync_bin};
    end
    
    // Watermark flag (DATA_RDY)
    assign DATA_RDY = (frame_count >= {1'b0, FIFOWATERMARK}) && ENSAMP_sync;
    
    // Overflow/underflow event toggles for robust CDC into HF_CLK.
    // These outputs are synchronized and edge-decoded in CDC_sync.
    reg fifo_overflow_evt_tgl;
    reg fifo_underflow_evt_tgl;
    assign FIFO_OVERFLOW  = fifo_overflow_evt_tgl;
    assign FIFO_UNDERFLOW = fifo_underflow_evt_tgl;
    
    // Precompute next write pointer (for frame clearing on advance)
    wire [PTR_WIDTH-1:0] write_ptr_next = write_ptr + 1'b1;

    // Write logic
    always @(posedge SAMPLE_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            write_ptr      <= {PTR_WIDTH{1'b0}};
            write_ptr_gray <= {PTR_WIDTH{1'b0}};
            fifo_overflow_evt_tgl <= 1'b0;
            
            for (i = 0; i < FRAME_DEPTH; i = i + 1) begin
                mem[i] <= 128'h0;
            end
        end else if (!ENSAMP_sync) begin
            // When disabled, reset pointers and clear memory
            write_ptr      <= {PTR_WIDTH{1'b0}};
            write_ptr_gray <= {PTR_WIDTH{1'b0}};
            
            for (i = 0; i < FRAME_DEPTH; i = i + 1) begin
                mem[i] <= 128'h0;
            end
        end else begin
            // Write data when DONE and ENSAMP_sync active
            if (DONE) begin
                // Write to specific word based on one-hot ATMCHSEL[7:0]
                case (1'b1)
                    ATMCHSEL[0]: mem[write_ptr[ADDR_WIDTH-1:0]][15:0]    <= RESULT;
                    ATMCHSEL[1]: mem[write_ptr[ADDR_WIDTH-1:0]][31:16]   <= RESULT;
                    ATMCHSEL[2]: mem[write_ptr[ADDR_WIDTH-1:0]][47:32]   <= RESULT;
                    ATMCHSEL[3]: mem[write_ptr[ADDR_WIDTH-1:0]][63:48]   <= RESULT;
                    ATMCHSEL[4]: mem[write_ptr[ADDR_WIDTH-1:0]][79:64]   <= RESULT;
                    ATMCHSEL[5]: mem[write_ptr[ADDR_WIDTH-1:0]][95:80]   <= RESULT;
                    ATMCHSEL[6]: mem[write_ptr[ADDR_WIDTH-1:0]][111:96]  <= RESULT;
                    ATMCHSEL[7]: mem[write_ptr[ADDR_WIDTH-1:0]][127:112] <= RESULT;
                endcase
                
                // Advance to next frame on last word
                if (LASTWORD) begin
                    // Toggle overflow event when attempting to push while full.
                    if (frame_count == FRAME_DEPTH) begin
                        fifo_overflow_evt_tgl <= ~fifo_overflow_evt_tgl;
                    end else begin
                        // Clear the next frame so disabled channels read as 0 and stale
                        // data from prior uses of this slot cannot leak through.
                        mem[write_ptr_next[ADDR_WIDTH-1:0]] <= 128'h0;
                        write_ptr      <= write_ptr + 1'b1;
                        write_ptr_gray <= bin_to_gray(write_ptr + 1'b1);
                    end
                end
            end
            
            // Zero out frame after it's been read
            if (frame_pop_edge) begin
                mem[read_ptr_sync_prev_idx] <= 128'h0;
            end
        end
    end
    
    //========================================================================
    // READ DOMAIN (SCK)
    //========================================================================
    
    // Synchronize ENSAMP_sync into SCK domain (for DATA_RDY gating etc.)
    reg [1:0] ensamp_sck_ff;
    wire ensamp_sck;
    assign ensamp_sck = ensamp_sck_ff[1];
    
    // Synchronize write pointer to read domain
    reg [PTR_WIDTH-1:0] write_ptr_gray_sync1;
    always @(posedge SCK or negedge NRST_sync or negedge ensamp_rstn_sck) begin
        if (!NRST_sync || !ensamp_rstn_sck) begin
            write_ptr_gray_sync1 <= {PTR_WIDTH{1'b0}};
            write_ptr_sync       <= {PTR_WIDTH{1'b0}};
            ensamp_sck_ff        <= 2'b00;
        end else begin
            ensamp_sck_ff <= {ensamp_sck_ff[0], ENSAMP_sync};
            write_ptr_gray_sync1 <= write_ptr_gray;
            write_ptr_sync       <= write_ptr_gray_sync1;
        end
    end

    // Reset synchronizer for SCK domain: assert async on ENSAMP_sync low,
    // deassert synchronously after two SCK cycles.
    always @(posedge SCK or negedge NRST_sync or negedge ENSAMP_sync) begin
        if (!NRST_sync || !ENSAMP_sync) begin
            ensamp_rst_ff <= 2'b00;
        end else begin
            ensamp_rst_ff <= {ensamp_rst_ff[0], 1'b1};
        end
    end
    assign ensamp_rstn_sck = ensamp_rst_ff[1];
    
    always @(*) begin
        write_ptr_sync_bin = gray_to_bin(write_ptr_sync);
    end
    
    always @(*) begin
        frames_available = (write_ptr_sync_bin != read_ptr);
    end
    
    // Read logic
    always @(posedge SCK or negedge NRST_sync or negedge ensamp_rstn_sck) begin
        if (!NRST_sync) begin
            // When disabled (or global reset), reset and output zeros
            read_ptr       <= {PTR_WIDTH{1'b0}};
            read_ptr_gray  <= {PTR_WIDTH{1'b0}};
            ADC_data       <= 128'h0;
            fifo_underflow_evt_tgl <= 1'b0;
        end else if (!ensamp_rstn_sck) begin
            // Clear read-side state on ENSAMP disable; keep event toggle stable
            // so CDC does not see a false edge from a forced reset.
            read_ptr       <= {PTR_WIDTH{1'b0}};
            read_ptr_gray  <= {PTR_WIDTH{1'b0}};
            ADC_data       <= 128'h0;
        end else begin
            if (FIFO_POP && !frames_available) begin
                // Toggle underflow event when popping empty FIFO.
                fifo_underflow_evt_tgl <= ~fifo_underflow_evt_tgl;
            end
            // Look-ahead read: always output valid data if available
            if (frames_available) begin
                ADC_data <= mem[read_ptr[ADDR_WIDTH-1:0]];
            end else begin
                ADC_data <= 128'h0;
            end

            // POP only advances the pointer
            if (FIFO_POP && frames_available) begin
                read_ptr      <= read_ptr + 1'b1;
                read_ptr_gray <= bin_to_gray(read_ptr + 1'b1);
            end
        end
    end

endmodule
