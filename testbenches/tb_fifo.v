`timescale 1ns/1ps

`ifdef LEGACY_TB

module tb_fifo_thorough();
    reg sample_clk = 0;
    reg read_clk = 0;
    reg reset_n = 0;
    reg [15:0] data_in = 0;
    reg done = 0;
    reg last_word = 0;
    reg [2:0] atmchsel = 0;
    reg [3:0] threshold = 4'd8;
    reg frame_pop = 0;
    
    wire [127:0] f_out;
    wire fifo_ready;

    // Helper for debugging in GTKWave
    wire [15:0] word0 = f_out[15:0];
    wire [15:0] word7 = f_out[127:112];

    integer f, w;

    // Clock Generation
    always #5 sample_clk = ~sample_clk; // 100MHz
    always #13 read_clk = ~read_clk;    // ~38.4MHz SPI

    dual_clock_fifo uut (
        .sample_clk(sample_clk), .reset_n(reset_n), .data_in(data_in),
        .done(done), .last_word(last_word), .atmchsel(atmchsel),
        .threshold(threshold), .fifo_ready(fifo_ready),
        .read_clk(read_clk), .frame_pop(frame_pop), .frame_data_out(f_out)
    );

    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_fifo_thorough);
        
        // --- TEST 1: Reset & Initial State ---
        reset_n = 0; #50; reset_n = 1;
        if (fifo_ready) $display("FAIL: Ready high after reset");

        // --- TEST 2: High Speed Back-to-Back (No Spare Cycles) ---
        // We will fill 4 frames with NO idle cycles between them.
        $display("Starting Test 2: Back-to-back writes...");
        for (f = 0; f < 4; f = f + 1) begin
            for (w = 0; w < 8; w = w + 1) begin
                @(posedge sample_clk);
                done <= 1;
                atmchsel <= w[2:0];
                data_in <= (f << 8) | w;
                last_word <= (w == 7);
            end
        end
        @(posedge sample_clk);
        done <= 0; last_word <= 0;

        // --- TEST 3: Edge Case - Partial Frame Write & Zeroing ---
        // We write only words 0 and 1. Word 7 should have been zeroed by our scrubber.
        $display("Starting Test 3: Partial frame write (Testing Zeroing)...");
        for (w = 0; w < 2; w = w + 1) begin
            @(posedge sample_clk);
            done <= 1;
            atmchsel <= w[2:0];
            data_in <= 16'h55AA;
            last_word <= (w == 1); // Trigger frame jump early
        end
        @(posedge sample_clk);
        done <= 0; last_word <= 0;

        // --- TEST 4: Threshold Configuration ---
        // Current frames in FIFO: 5. Let's set threshold to 5.
        threshold = 4'd5;
        #10;
        if (fifo_ready) $display("PASS: Threshold 5 triggered successfully");

        // --- TEST 5: Buffer Overflow Handling ---
        // Fill the remaining 11 frames (Total 16)
        for (f = 5; f < 17; f = f + 1) begin
            @(posedge sample_clk);
            done <= 1; atmchsel <= 0; data_in <= 16'hEEEE; last_word <= 1;
        end
        @(posedge sample_clk);
        done <= 0; last_word <= 0;
        $display("Buffer filled to capacity.");

        // --- TEST 6: Reading & Popping ---
        $display("Starting Test 6: Reading data...");
        while (fifo_ready) begin
            @(posedge read_clk);
            $display("Frame Out: %h", f_out);
            frame_pop <= 1;
            @(posedge read_clk);
            frame_pop <= 0;
            repeat(2) @(posedge read_clk); // Simulate SPI processing time
        end

        $display("All thorough tests complete.");
        #100;
        $finish;
    end
endmodule

`endif