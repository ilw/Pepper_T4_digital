`timescale 1ns/1ps

`ifdef LEGACY_TB

module tb_fifo_validate_improved();
    reg         sample_clk, read_clk, reset_n, done, last_word, frame_pop;
    reg [15:0]  data_in;
    reg [2:0]   atmchsel;
    reg [3:0]   threshold;
    wire [127:0] f_out;
    wire         fifo_ready;

    integer w, errors;
    reg [127:0] expected_data;

    // Clock Gen (sample_clk faster than read_clk)
    initial begin sample_clk = 0; forever #5 sample_clk = ~sample_clk; end   // 100 MHz
    initial begin read_clk = 0; forever #13 read_clk = ~read_clk; end        // ~38.5 MHz

    // DUT instantiation with parameter
    dual_clock_fifo #(
        .FRAME_DEPTH(16)
    ) uut (
        .sample_clk      (sample_clk),
        .reset_n         (reset_n),
        .data_in         (data_in),
        .done            (done),
        .last_word       (last_word),
        .atmchsel        (atmchsel),
        .threshold       (threshold),
        .fifo_ready      (fifo_ready),
        .read_clk        (read_clk),
        .frame_pop       (frame_pop),
        .frame_data_out  (f_out)
    );

    initial begin
        $dumpfile("waveform.vcd"); 
        $dumpvars(0, tb_fifo_validate_improved);
        
        // Initialize
        reset_n = 0; 
        done = 0; 
        last_word = 0; 
        threshold = 4'd1; 
        frame_pop = 0; 
        errors = 0;
        data_in = 16'h0;
        atmchsel = 3'd0;
        
        // Reset
        #50 reset_n = 1;
        #20;
        
        $display("\n=== TEST 1: Write Frame 0 (Full Frame with 0xFFFF) ===");
        // Write a complete frame to frame 0
        for (w = 0; w < 8; w = w + 1) begin
            write_word(w[2:0], 16'hFFFF, (w==7));
        end
        $display("Frame 0 written with 8 words of 0xFFFF");
        @(posedge sample_clk);
        $display("DEBUG: mem[0] = %h", uut.mem[0]);
        
        $display("\n=== TEST 2: Write Frame 1 (Partial Frame) ===");
        // Write partial frame to frame 1 (only positions 2 and 5)
        write_word(3'd2, 16'hAAAA, 0);
        write_word(3'd5, 16'hBBBB, 1);  // last_word=1, advances to frame 2
        $display("Frame 1 written with partial data: pos[2]=0xAAAA, pos[5]=0xBBBB");
        @(posedge sample_clk);
        $display("DEBUG: mem[1] = %h", uut.mem[1]);
        
        $display("\n=== TEST 3: Write Frame 2 (Different Pattern) ===");
        // Write another frame with different pattern
        write_word(3'd0, 16'h1111, 0);
        write_word(3'd3, 16'h3333, 0);
        write_word(3'd7, 16'h7777, 1);  // last_word=1, advances to frame 3
        $display("Frame 2 written with: pos[0]=0x1111, pos[3]=0x3333, pos[7]=0x7777");
        @(posedge sample_clk);
        $display("DEBUG: mem[2] = %h", uut.mem[2]);
        
        // Wait for frames to be available
        wait(fifo_ready);
        $display("\n=== FIFO Ready - Frames Available ===");
        
        // Allow CDC synchronizers to settle
        repeat(10) @(posedge read_clk);
        
        //===================================================================
        // READ AND VALIDATE FRAME 0
        //===================================================================
        $display("\n=== TEST 4: Read Frame 0 ===");
        
        // Assert frame_pop to request the frame
        @(posedge read_clk); 
        frame_pop = 1; 
        @(posedge read_clk); 
        frame_pop = 0;
        
        // Wait one more clock for output to be registered
        @(posedge read_clk);
        #2;  // Small delay for output to settle
        
        expected_data = {16'hFFFF, 16'hFFFF, 16'hFFFF, 16'hFFFF, 
                        16'hFFFF, 16'hFFFF, 16'hFFFF, 16'hFFFF};
        
        $display("Frame 0 output: %h", f_out);
        $display("Expected:       %h", expected_data);
        
        if (f_out === expected_data) begin
            $display("✓ Frame 0 PASSED");
        end else begin
            $display("✗ Frame 0 FAILED");
            errors = errors + 1;
        end
        
        // Wait for CDC synchronizers to process the previous pop
        repeat(10) @(posedge read_clk);
        
        //===================================================================
        // READ AND VALIDATE FRAME 1
        //===================================================================
        $display("\n=== TEST 5: Read Frame 1 (Partial, Should be Pre-zeroed) ===");
        
        // Assert frame_pop to request Frame 1
        @(posedge read_clk); 
        frame_pop = 1; 
        @(posedge read_clk); 
        frame_pop = 0;
        
        // Wait for output to be registered
        @(posedge read_clk);
        #2;
        
        expected_data = {16'h0000, 16'h0000, 16'hBBBB, 16'h0000, 
                        16'h0000, 16'hAAAA, 16'h0000, 16'h0000};
        
        $display("Frame 1 output: %h", f_out);
        $display("Expected:       %h", expected_data);
        
        if (f_out === expected_data) begin
            $display("✓ Frame 1 PASSED - Pre-zeroing works!");
        end else begin
            $display("✗ Frame 1 FAILED - Pre-zeroing issue");
            errors = errors + 1;
        end
        
        // Wait for CDC synchronizers
        repeat(10) @(posedge read_clk);
        
        //===================================================================
        // READ AND VALIDATE FRAME 2
        //===================================================================
        $display("\n=== TEST 6: Read Frame 2 ===");
        
        // Assert frame_pop to request Frame 2
        @(posedge read_clk); 
        frame_pop = 1; 
        @(posedge read_clk); 
        frame_pop = 0;
        
        // Wait for output to be registered
        @(posedge read_clk);
        #2;
        
        expected_data = {16'h7777, 16'h0000, 16'h0000, 16'h0000, 
                        16'h3333, 16'h0000, 16'h0000, 16'h1111};
        
        $display("Frame 2 output: %h", f_out);
        $display("Expected:       %h", expected_data);
        
        if (f_out === expected_data) begin
            $display("✓ Frame 2 PASSED");
        end else begin
            $display("✗ Frame 2 FAILED");
            errors = errors + 1;
        end
        
        //===================================================================
        // TEST CONTINUOUS WRITING (Back-to-back frames)
        //===================================================================
        $display("\n=== TEST 7: Continuous Write Test ===");
        
        // Write multiple frames back-to-back
        fork
            begin
                // Write 3 frames rapidly
                repeat(3) begin
                    for (w = 0; w < 4; w = w + 1) begin
                        write_word(w[2:0], w[15:0] + 16'h1000, (w==3));
                    end
                end
            end
            begin
                // Read them as they become available
                repeat(3) begin
                    wait(fifo_ready);
                    repeat(5) @(posedge read_clk);
                    @(posedge read_clk); frame_pop = 1; 
                    @(posedge read_clk); frame_pop = 0;
                end
            end
        join
        
        $display("✓ Continuous write/read test completed");
        
        //===================================================================
        // FINAL RESULTS
        //===================================================================
        #100;
        
        if (errors == 0) begin
            $display("\n╔════════════════════════════════════╗");
            $display("║   ✓ ALL TESTS PASSED ✓             ║");
            $display("╚════════════════════════════════════╝\n");
        end else begin
            $display("\n╔════════════════════════════════════╗");
            $display("║   ✗ TESTS FAILED: %0d errors        ║", errors);
            $display("╚════════════════════════════════════╝\n");
        end
        
        $finish;
    end

    // Task to write a single word
    task write_word(input [2:0] addr, input [15:0] data, input last);
        begin
            @(posedge sample_clk);
            done      = 1;
            atmchsel  = addr;
            data_in   = data;
            last_word = last;
            @(posedge sample_clk);
            done      = 0;
            last_word = 0;
        end
    endtask
    
    // Monitor for debugging
    always @(posedge sample_clk) begin
        if (done) begin
            $display("WRITE: Time=%0t | Ptr=%0d | atmchsel=%0d | data=%h | last=%b", 
                     $time, uut.write_ptr, atmchsel, data_in, last_word);
        end
        if (uut.last_word && uut.done) begin
            $display("FRAME ADVANCE: write_ptr %0d -> %0d", uut.write_ptr, uut.write_ptr + 1);
        end
    end
    
    always @(posedge read_clk) begin
        if (frame_pop && fifo_ready) begin
            $display("READ: Time=%0t | Ptr=%0d | data=%h", $time, uut.read_ptr, f_out);
        end
    end

endmodule	

`endif