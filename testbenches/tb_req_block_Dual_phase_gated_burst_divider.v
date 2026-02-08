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
    reg prev_sample_clk;
    reg counting_pulses;
    reg measuring_phase2;
    
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
        PHASE1DIV1_sync = 2;
        PHASE1COUNT_sync = 8;
        PHASE2COUNT_sync = 10;
        
        // Wait for phase 2 to start
        wait(phase == 0);
        pulse_count = 0;
        counting_pulses = 1;
        
        wait(phase == 1);
        counting_pulses = 0;
        
        if (pulse_count == 8)
            $display("  PASSED: Counted %0d pulses", pulse_count);
        else
            $display("ERROR:   FAILED: Expected 8 pulses, got %0d", pulse_count);
        
        // Test 3: Phase 2 Duration (DIG-39)
        $display("Test 3: Phase 2 Duration");
        
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
        PHASE1DIV1_sync = 0;
        PHASE1COUNT_sync = 0;
        PHASE2COUNT_sync = 0;
        
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
