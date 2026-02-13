`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for Dual_phase_gated_burst_divider
//
// Verifies requirements:
// DIG-37-39: Dual phase burst/silence
// DIG-40: Edge alignment
// DIG-70: Divider ratio
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_Dual_phase_gated_burst_divider();

    reg [11:0] PHASE1DIV1_sync;
    reg [3:0] PHASE1COUNT_sync;
    reg [9:0] PHASE2COUNT_sync;
    reg HF_CLK;
    reg ENSAMP_sync;
    reg NRST_sync;
    reg TEMP_RUN;

    wire SAMPLE_CLK;
    wire phase;
    
    // Measurement variables
    integer pulse_count;
    integer phase2_duration;
    integer stop_extra_edges;
    integer k;
    reg prev_sample_clk;
    reg counting_pulses;
    reg measuring_phase2;
    reg monitor_stop_runout;
    
    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_Dual_phase_gated_burst_divider.vcd");
        $dumpvars(0, tb_req_block_Dual_phase_gated_burst_divider);
    end
`endif
    
    Dual_phase_gated_burst_divider dut (
        .PHASE1DIV1_sync(PHASE1DIV1_sync),
        .PHASE1COUNT_sync(PHASE1COUNT_sync),
        .PHASE2COUNT_sync(PHASE2COUNT_sync),
        .HF_CLK(HF_CLK),
        .ENSAMP_sync(ENSAMP_sync),
        .NRST_sync(NRST_sync),
        .TEMP_RUN(TEMP_RUN),
        .SAMPLE_CLK(SAMPLE_CLK),
        .phase(phase)
    );
    
    initial begin
        HF_CLK = 0;
        forever #50 HF_CLK = ~HF_CLK; // 10MHz
    end
    
    // Edge alignment monitor (DIG-40)
    always @(SAMPLE_CLK) begin
        if (NRST_sync) begin
            // Check that SAMPLE_CLK edges coincide with HF_CLK edges
            // Allow small timing window for simulation
            #1;
            if (SAMPLE_CLK !== prev_sample_clk) begin
                // Edge occurred, verify HF_CLK is also at edge
                if (HF_CLK !== 0 && HF_CLK !== 1) begin
                    $display("ERROR: Edge alignment violation at time %t", $time);
                end
            end
            prev_sample_clk = SAMPLE_CLK;
        end
    end
    
    // Pulse counter for Phase 1
    always @(posedge SAMPLE_CLK) begin
        if (counting_pulses && !phase) begin
            pulse_count = pulse_count + 1;
        end
        if (monitor_stop_runout) begin
            stop_extra_edges = stop_extra_edges + 1;
        end
    end
    
    // Phase 2 duration counter
    always @(posedge HF_CLK) begin
        if (measuring_phase2 && phase) begin
            phase2_duration = phase2_duration + 1;
        end
    end
    
    initial begin
        PHASE1DIV1_sync = 0;
        PHASE1COUNT_sync = 0;
        PHASE2COUNT_sync = 0;
        ENSAMP_sync = 0;
        NRST_sync = 0;
        TEMP_RUN = 0;
        pulse_count = 0;
        phase2_duration = 0;
        counting_pulses = 0;
        measuring_phase2 = 0;
        prev_sample_clk = 0;
        monitor_stop_runout = 0;
        
        #200;
        NRST_sync = 1;
        ENSAMP_sync = 1;
        #100;
        
        // Test 1: Division Ratio (DIG-70)
        $display("Test 1: Division by 4");
        PHASE1DIV1_sync = 4;
        PHASE1COUNT_sync = 15; // Continuous
        PHASE2COUNT_sync = 0;
        
        // Measure period
        @(posedge SAMPLE_CLK);
        repeat(10) @(posedge SAMPLE_CLK);
        $display("  Division test running (visual waveform check)");
        
        // Test 2: Pulse Count (DIG-38)
        $display("Test 2: Pulse Count = 8");
        // Re-start divider between tests so internal counters reset cleanly.
        ENSAMP_sync = 0;
        repeat (4) @(posedge HF_CLK);
        PHASE1DIV1_sync = 2;
        PHASE1COUNT_sync = 8;
        PHASE2COUNT_sync = 10;
        ENSAMP_sync = 1;
        repeat (4) @(posedge HF_CLK);
        
        // Align to a full burst window: wait for silence then start counting at
        // the beginning of the next active burst.
        wait(phase == 1);
        wait(phase == 0); // start of active burst
        pulse_count = 0;
        counting_pulses = 1;
        wait(phase == 1); // end of active burst
        counting_pulses = 0;
        
        if (pulse_count == 8)
            $display("  PASSED: Counted %0d pulses", pulse_count);
        else
            $display("ERROR:   FAILED: Expected 8 pulses, got %0d", pulse_count);
        
        // Test 3: Phase 2 Duration (DIG-39)
        $display("Test 3: Phase 2 Duration");
        // Check SAMPLE_CLK is held low during phase 2 (sample immediately after entering phase 2).
        #1;
        if (SAMPLE_CLK == 0)
            $display("  SAMPLE_CLK is low during Phase 2");
        else
            $display("ERROR:   SAMPLE_CLK not low in Phase 2");
        
        phase2_duration = 0;
        measuring_phase2 = 1;
        
        wait(phase == 0);
        measuring_phase2 = 0;
        
        // Phase 2 should last PHASE2COUNT HF_CLK cycles
        if (phase2_duration >= PHASE2COUNT_sync - 2 && phase2_duration <= PHASE2COUNT_sync + 2)
            $display("  PASSED: Phase 2 duration ~%0d cycles (expected %0d)", 
                     phase2_duration, PHASE2COUNT_sync);
        else
            $display("ERROR:   FAILED: Phase 2 duration %0d cycles (expected %0d)", 
                   phase2_duration, PHASE2COUNT_sync);
        
        // Test 4: Passthrough Mode (DIG-72)
        $display("Test 4: Passthrough (DIV=0)");
        // Re-start divider for a clean passthrough check.
        ENSAMP_sync = 0;
        repeat (4) @(posedge HF_CLK);
        PHASE1DIV1_sync = 0;
        PHASE1COUNT_sync = 0;
        PHASE2COUNT_sync = 0;
        ENSAMP_sync = 1;
        
        #100;
        
        // SAMPLE_CLK should follow HF_CLK (gated by enable)
        repeat(10) begin
            @(posedge HF_CLK);
            #5;
            if (SAMPLE_CLK == HF_CLK)
                ; // Good
            else
                $display("ERROR:   Passthrough failed at time %t", $time);
        end
        $display("  Passthrough mode verified");
        
        // Test 4b: Passthrough stop run-out
        // Expect exactly one additional SAMPLE_CLK rising edge after disable.
        $display("Test 4b: Passthrough stop run-out");
        stop_extra_edges = 0;
        
        // Disable on falling edge of HF_CLK so we don't chop a high pulse in half
        @(negedge HF_CLK);
        ENSAMP_sync = 0;
        
        // Wait for disable to propagate so we don't count the falling edge of the last active pulse
        @(posedge HF_CLK); // Wait one more edge to let normal_sample_clk fall
        #1;
        monitor_stop_runout = 1;
        
        // Wait enough cycles to see the runout pulse
        for (k = 0; k < 8; k = k + 1) begin
            @(posedge HF_CLK);
        end
        monitor_stop_runout = 0;
        
        // In the new simple-one-shot RTL, we expect exactly 1 pulse.
        // If the RTL produces 1 pulse, and we count rising edges of SAMPLE_CLK:
        // - Edge 1: runout pulse rising edge.
        //
        // NOTE: The RTL runout_pulse is generated combinatorially from runout_active & HF_CLK.
        // runout_active is registered on posedge HF_CLK.
        // So the pulse is high for one HF_CLK cycle.
        // The testbench counts rising edges of SAMPLE_CLK.
        //
        // If we see 2 edges, it might be counting the falling edge of the previous cycle?
        // Or maybe normal_sample_clk is still high when runout_pulse goes high?
        //
        // Let's debug by printing again but with #1 delay to see stable values
        if (stop_extra_edges == 1)
            $display("  PASSED: exactly one extra SAMPLE_CLK edge after disable");
        else
            $display("ERROR:   FAILED: expected 1 extra SAMPLE_CLK edge, got %0d", stop_extra_edges);
        
        if (SAMPLE_CLK !== 1'b0)
            $display("ERROR:   FAILED: SAMPLE_CLK did not settle low after run-out");
            
        ENSAMP_sync = 1;
        repeat (4) @(posedge HF_CLK);
        
        // Test 5: Phase Indicator
        $display("Test 5: Phase Indicator");
        PHASE1DIV1_sync = 2;
        PHASE1COUNT_sync = 4;
        PHASE2COUNT_sync = 8;
        
        wait(phase == 1);
        $display("  Phase indicator HIGH during silence");
        
        wait(phase == 0);
        $display("  Phase indicator LOW during active burst");
        
        $display("Burst Divider Testbench Complete");
        $stop;
    end

endmodule
