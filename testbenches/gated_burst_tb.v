`timescale 1us/1ns

`ifdef LEGACY_TB

module tb_burst_divider();
    reg clk = 0;
    reg reset;
    reg enable_async;
    reg [9:0] m1, m2;
    reg [4:0] x;
    wire clk_out, status;

    gated_burst_divider #(10, 5, 10) uut (
        .clk(clk), .reset(reset), .enable_async(enable_async),
        .m1_value(m1), .m2_value(m2), .m1_repeat_limit(x),
        .clk_out(clk_out), .phase_status(status)
    );

    // 1MHz clock generation
    always #0.5 clk = ~clk;

    // Task to apply settings cleanly
    task apply_settings(input [9:0] new_m1, input [9:0] new_m2, input [7:0] new_x);
        begin
            enable_async = 0;   // Disable block
            #5;                 // Wait for synchronizer to clear (5us = 5 cycles)
            m1 = new_m1; 
            m2 = new_m2; 
            x = new_x;
            #2;                 // Setup time
            enable_async = 1;   // Re-enable
            $display("Applied: M1=%0d, M2=%0d, X=%0d", new_m1, new_m2, new_x);
        end
    endtask

    initial begin
        $dumpfile("gated_burst.vcd");
        $dumpvars(0, tb_burst_divider);

        // System Reset
        reset = 1; enable_async = 0; m1 = 0; m2 = 0; x = 0;
        #10 reset = 0;
        #5;

        // --- Scenario 1: Standard Burst ---
        apply_settings(2, 10, 4); #100;

        // --- Scenario 2: High Freq Burst ---
        apply_settings(1, 20, 8); #100;

        // --- Scenario 3: NO SILENT PHASE (Continuous) ---
        apply_settings(3, 0, 5); #100;

        // --- Scenario 4: Long Silence ---
        apply_settings(2, 100, 2); #250;

        // --- Scenario 5: Passthrough Mode (M1=0) ---
        apply_settings(0, 0, 0); #50;

        // --- Scenario 6: Large X Value ---
        apply_settings(1, 10, 16); #150;

        // --- Scenario 7: Minimal Pulse Width ---
        apply_settings(1, 5, 2); #50;

        // --- Scenario 8: Slow Pulse Width ---
        apply_settings(20, 40, 3); #400;

        // --- Scenario 9: High Density ---
        apply_settings(2, 2, 10); #150;

        // --- Scenario 10: Reset mid-stream test ---
        apply_settings(4, 10, 5); #20;
        enable_async = 0; #20; 
        enable_async = 1; #150;

        $display("Testbench Completed Successfully");
        $finish;
    end
endmodule

`endif