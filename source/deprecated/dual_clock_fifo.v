module dual_clock_fifo #(
    parameter FRAME_DEPTH = 16  // Number of 128-bit frames (must be power of 2)
)(
    // Write domain (SAMPLE_CLK)
    input  wire                     sample_clk,
    input  wire                     reset_n,
    input  wire [15:0]              data_in,
    input  wire                     done,           // Write enable
    input  wire                     last_word,      // Advances to next frame
    input  wire [2:0]               atmchsel,       // Word position (0-7)
    input  wire [3:0]               threshold,      // Threshold for fifo_ready
    output wire                     fifo_ready,     // Indicates enough frames available
    
    // Read domain (READ_CLK)
    input  wire                     read_clk,
    input  wire                     frame_pop,      // Request to read next frame
    output reg  [127:0]             frame_data_out  // Output frame data
);

    // Calculate address width based on FRAME_DEPTH
    localparam ADDR_WIDTH = $clog2(FRAME_DEPTH);
    
    // Frame memory: FRAME_DEPTH frames of 128 bits each
    reg [127:0] mem [0:FRAME_DEPTH-1];
    
    // Write domain pointers and control
    reg [ADDR_WIDTH-1:0]   write_ptr;           // Binary write pointer
    reg [ADDR_WIDTH-1:0]   write_ptr_gray;      // Gray code write pointer
    reg [ADDR_WIDTH-1:0]   read_ptr_sync;       // Synchronized read pointer (Gray)
    reg [ADDR_WIDTH-1:0]   read_ptr_sync_bin;   // Converted to binary
    reg [ADDR_WIDTH-1:0]   read_ptr_sync_prev;  // Previous read pointer for zeroing
    
    // Read domain pointers and control
    reg [ADDR_WIDTH-1:0]   read_ptr;            // Binary read pointer
    reg [ADDR_WIDTH-1:0]   read_ptr_gray;       // Gray code read pointer
    reg [ADDR_WIDTH-1:0]   write_ptr_sync;      // Synchronized write pointer (Gray)
    reg [ADDR_WIDTH-1:0]   write_ptr_sync_bin;  // Converted to binary
    
    // Frame count in write domain
    reg [ADDR_WIDTH:0]     frame_count;         // Number of frames available
    
    // Frame available flag in read domain
    reg                    frames_available;
    
    // Frame pop synchronizer (read -> write domain)
    reg frame_pop_sync1, frame_pop_sync2, frame_pop_prev;
    wire frame_pop_edge;
    
    integer i;
    
    //========================================================================
    // GRAY CODE CONVERSION FUNCTIONS
    //========================================================================
    
    function [ADDR_WIDTH-1:0] bin_to_gray;
        input [ADDR_WIDTH-1:0] bin;
        begin
            bin_to_gray = bin ^ (bin >> 1);
        end
    endfunction
    
    function [ADDR_WIDTH-1:0] gray_to_bin;
        input [ADDR_WIDTH-1:0] gray;
        integer j;
        begin
            gray_to_bin[ADDR_WIDTH-1] = gray[ADDR_WIDTH-1];
            for (j = ADDR_WIDTH-2; j >= 0; j = j - 1) begin
                gray_to_bin[j] = gray_to_bin[j+1] ^ gray[j];
            end
        end
    endfunction
    
    //========================================================================
    // WRITE DOMAIN (SAMPLE_CLK)
    //========================================================================
    
    // Synchronize read pointer from read domain to write domain
    reg [ADDR_WIDTH-1:0] read_ptr_gray_sync1;
    always @(posedge sample_clk or negedge reset_n) begin
        if (!reset_n) begin
            read_ptr_gray_sync1 <= {ADDR_WIDTH{1'b0}};
            read_ptr_sync       <= {ADDR_WIDTH{1'b0}};
            read_ptr_sync_prev  <= {ADDR_WIDTH{1'b0}};
        end else begin
            read_ptr_gray_sync1 <= read_ptr_gray;       // First stage
            read_ptr_sync       <= read_ptr_gray_sync1; // Second stage
            read_ptr_sync_prev  <= read_ptr_sync_bin;   // Track previous value
        end
    end
    
    // Convert synchronized Gray code read pointer to binary
    always @(*) begin
        read_ptr_sync_bin = gray_to_bin(read_ptr_sync);
    end
    
    // Synchronize frame_pop signal (edge detect)
    always @(posedge sample_clk or negedge reset_n) begin
        if (!reset_n) begin
            frame_pop_sync1 <= 1'b0;
            frame_pop_sync2 <= 1'b0;
            frame_pop_prev  <= 1'b0;
        end else begin
            frame_pop_sync1 <= frame_pop;
            frame_pop_sync2 <= frame_pop_sync1;
            frame_pop_prev  <= frame_pop_sync2;
        end
    end
    assign frame_pop_edge = frame_pop_sync2 && !frame_pop_prev;
    
    // Calculate frame count
    always @(*) begin
        frame_count = {1'b0, write_ptr} - {1'b0, read_ptr_sync_bin};
    end
    
    // FIFO ready signal (enough frames available for threshold)
    assign fifo_ready = (frame_count >= {1'b0, threshold});
    
    // Write logic and frame management
    always @(posedge sample_clk or negedge reset_n) begin
        if (!reset_n) begin
            write_ptr      <= {ADDR_WIDTH{1'b0}};
            write_ptr_gray <= {ADDR_WIDTH{1'b0}};
            
            // Initialize all frames to zero
            for (i = 0; i < FRAME_DEPTH; i = i + 1) begin
                mem[i] <= 128'h0;
            end
        end else begin
            // Write data when done is asserted
            if (done) begin
                // Update specific 16-bit word based on atmchsel
                case (atmchsel)
                    3'd0: mem[write_ptr][15:0]    <= data_in;
                    3'd1: mem[write_ptr][31:16]   <= data_in;
                    3'd2: mem[write_ptr][47:32]   <= data_in;
                    3'd3: mem[write_ptr][63:48]   <= data_in;
                    3'd4: mem[write_ptr][79:64]   <= data_in;
                    3'd5: mem[write_ptr][95:80]   <= data_in;
                    3'd6: mem[write_ptr][111:96]  <= data_in;
                    3'd7: mem[write_ptr][127:112] <= data_in;
                endcase
                
                // Advance to next frame when last_word is asserted
                if (last_word) begin
                    write_ptr      <= write_ptr + 1'b1;
                    write_ptr_gray <= bin_to_gray(write_ptr + 1'b1);
                end
            end
            
            // Zero out frame when it's been read (detected via synchronized pop)
            // Use the PREVIOUS read pointer to zero the frame that was just read
            // This avoids race conditions with the incrementing read pointer
            if (frame_pop_edge) begin
                mem[read_ptr_sync_prev] <= 128'h0;
            end
        end
    end
    
    //========================================================================
    // READ DOMAIN (READ_CLK)
    //========================================================================
    
    // Synchronize write pointer from write domain to read domain
    reg [ADDR_WIDTH-1:0] write_ptr_gray_sync1;
    always @(posedge read_clk or negedge reset_n) begin
        if (!reset_n) begin
            write_ptr_gray_sync1 <= {ADDR_WIDTH{1'b0}};
            write_ptr_sync       <= {ADDR_WIDTH{1'b0}};
        end else begin
            write_ptr_gray_sync1 <= write_ptr_gray;       // First stage
            write_ptr_sync       <= write_ptr_gray_sync1; // Second stage
        end
    end
    
    // Convert synchronized Gray code write pointer to binary
    always @(*) begin
        write_ptr_sync_bin = gray_to_bin(write_ptr_sync);
    end
    
    // Determine if frames are available
    always @(*) begin
        frames_available = (write_ptr_sync_bin != read_ptr);
    end
    
    // Read logic
    always @(posedge read_clk or negedge reset_n) begin
        if (!reset_n) begin
            read_ptr      <= {ADDR_WIDTH{1'b0}};
            read_ptr_gray <= {ADDR_WIDTH{1'b0}};
            frame_data_out <= 128'h0;
        end else begin
            // Advance pointer on frame_pop if frames are available
            if (frame_pop && frames_available) begin
                // Output current frame BEFORE incrementing pointer
                frame_data_out <= mem[read_ptr];
                read_ptr       <= read_ptr + 1'b1;
                read_ptr_gray  <= bin_to_gray(read_ptr + 1'b1);
            end
        end
    end
    
endmodule