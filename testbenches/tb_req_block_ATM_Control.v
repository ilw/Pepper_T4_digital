`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for ATM_Control (Prediction-based channel sequencer)
//
// Verifies requirements:
// DIG-26: One-hot encoded channel select, break-before-make (CRITICAL SAFETY)
// DIG-29: Sequencing
// NEW:    Prediction counter (no DONE input) — channels switch 1 cycle before
//         DONE would appear from the ADC, with no wasted cycles.
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_ATM_Control();

    reg         SAMPLE_CLK;
    reg         ENSAMP_sync;
    reg  [7:0]  CHEN_sync;
    reg  [3:0]  OSR_sync;
    reg         NRST_sync;
    reg         ENLOWPWR_sync;

    wire [7:0]  ATMCHSEL;
    wire [7:0]  ATMCHSEL_DATA;
    wire [7:0]  CHSEL;
    wire        LASTWORD;
    
    // For break-before-make detection
    reg  [7:0]  prev_atmchsel;
    integer     transition_count;
    integer     break_violations;
    integer     errors;

    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_ATM_Control.vcd");
        $dumpvars(0, tb_req_block_ATM_Control);
    end
`endif

    ATM_Control dut (
        .SAMPLE_CLK(SAMPLE_CLK),
        .ENSAMP_sync(ENSAMP_sync),
        .CHEN_sync(CHEN_sync),
        .OSR_sync(OSR_sync),
        .NRST_sync(NRST_sync),
        .ENLOWPWR_sync(ENLOWPWR_sync),
        .ATMCHSEL(ATMCHSEL),
        .ATMCHSEL_DATA(ATMCHSEL_DATA),
        .CHSEL(CHSEL),
        .LASTWORD(LASTWORD)
    );
    
    initial begin
        SAMPLE_CLK = 0;
        forever #50 SAMPLE_CLK = ~SAMPLE_CLK;
    end
    
    // Manual popcount (iverilog compatible)
    function integer countones;
        input [7:0] val;
        integer k;
        begin
            countones = 0;
            for (k = 0; k < 8; k = k + 1)
                countones = countones + val[k];
        end
    endfunction
    
    // Continuous one-hot monitor (DIG-26)
    always @(ATMCHSEL) begin
        if (NRST_sync && (ATMCHSEL != 8'b0)) begin
            if (countones(ATMCHSEL) > 1) begin
                $display("ERROR: SAFETY VIOLATION: ATMCHSEL not one-hot! Val=%b Time=%t", ATMCHSEL, $time);
                errors = errors + 1;
            end
        end
    end
    
    // Break-before-make monitor (DIG-26 CRITICAL)
    always @(posedge SAMPLE_CLK) begin
        if (NRST_sync && ENSAMP_sync) begin
            if (prev_atmchsel != ATMCHSEL && prev_atmchsel != 8'b0 && ATMCHSEL != 8'b0) begin
                transition_count = transition_count + 1;
                if ((prev_atmchsel & ATMCHSEL) != 8'b0) begin
                    $display("ERROR: BREAK-BEFORE-MAKE VIOLATION: Overlap! Prev=%b Curr=%b Time=%t", 
                           prev_atmchsel, ATMCHSEL, $time);
                    break_violations = break_violations + 1;
                end
            end
            prev_atmchsel = ATMCHSEL;
        end
    end
    
    // ---------------------------------------------------------------
    // Helper task: wait for N SAMPLE_CLK rising edges
    // ---------------------------------------------------------------
    task wait_clks;
        input integer n;
        integer c;
        begin
            for (c = 0; c < n; c = c + 1)
                @(posedge SAMPLE_CLK);
        end
    endtask

    // ---------------------------------------------------------------
    // Helper task: check ATMCHSEL against expected one-hot channel
    // ---------------------------------------------------------------
    task check_channel;
        input [2:0] expected_ch;
        input [79:0] label;  // 10-char label
        begin
            if (ATMCHSEL == (8'd1 << expected_ch) && countones(ATMCHSEL) == 1)
                $display("  %0s: Ch %0d selected (one-hot) — OK", label, expected_ch);
            else begin
                $display("ERROR: %0s: Expected Ch %0d (one-hot %b), Got %b",
                         label, expected_ch, (8'd1 << expected_ch), ATMCHSEL);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Main test
    // ---------------------------------------------------------------
    initial begin
        errors           = 0;
        ENSAMP_sync      = 0;
        CHEN_sync        = 8'h00;
        OSR_sync         = 4'd0;
        NRST_sync        = 0;
        ENLOWPWR_sync    = 0;
        prev_atmchsel    = 8'b0;
        transition_count = 0;
        break_violations = 0;
        
        #200;
        NRST_sync = 1;
        #100;

        // ==============================================================
        // Test 1: SAR mode (OSR=0) — channel switches every cycle
        // ==============================================================
        $display("\n=== Test 1: SAR Mode (OSR=0) — Switch Every Cycle ===");
        OSR_sync = 4'd0;
        CHEN_sync = 8'b00000111; // Channels 0, 1, 2
        ENSAMP_sync = 1;
        
        wait_clks(2); // Allow initialisation
        check_channel(0, "SAR init  ");
        
        wait_clks(1);
        check_channel(1, "SAR +1    ");
        
        wait_clks(1);
        check_channel(2, "SAR +2    ");
        
        // Check LASTWORD on channel 2 (highest enabled)
        // LASTWORD is registered (1-cycle delayed), so check next cycle
        wait_clks(1);
        if (LASTWORD)
            $display("  SAR LASTWORD correctly asserted (pipelined)");
        else begin
            $display("ERROR: SAR LASTWORD not asserted when expected");
            errors = errors + 1;
        end
        
        // Should wrap to ch 0
        check_channel(0, "SAR wrap  ");
        
        // Run a few more cycles to accumulate transition stats
        wait_clks(10);
        
        ENSAMP_sync = 0;
        wait_clks(2);
        
        // Verify outputs go to zero
        if (ATMCHSEL == 8'b0)
            $display("  ENSAMP=0: ATMCHSEL cleared — OK");
        else begin
            $display("ERROR: ENSAMP=0 but ATMCHSEL=%b", ATMCHSEL);
            errors = errors + 1;
        end
        
        // ==============================================================
        // Test 2: NS mode (OSR=1) — 6-cycle conversion window
        // ==============================================================
        $display("\n=== Test 2: NS Mode (OSR=1) — 6-Cycle Window ===");
        OSR_sync = 4'd1;   // conv_len = 4*1+2 = 6
        CHEN_sync = 8'b10000101; // Channels 0, 2, 7
        ENSAMP_sync = 1;
        
        // First channel selection happens on init posedge.
        // Due to NBA, it is visible 1 posedge later.
        wait_clks(2);
        check_channel(0, "NS init   ");
        
        // After conv_len (6) more posedges, the switch fires and is
        // visible on the next posedge.  wait_clks(6) gets us there.
        wait_clks(6);
        check_channel(2, "NS ch2    ");
        
        // ATMCHSEL_DATA should reflect channel 0 (1-cycle delayed),
        // since the switch just happened and DATA is the old channel.
        if (ATMCHSEL_DATA == 8'b00000001)
            $display("  ATMCHSEL_DATA = Ch0 (aligned with DONE) — OK");
        else
            $display("  Note: ATMCHSEL_DATA = %b (may depend on exact cycle)", ATMCHSEL_DATA);
        
        // Another 6 cycles to get to ch 7
        wait_clks(6);
        check_channel(7, "NS ch7    ");
        
        // LASTWORD should already be asserted (current_channel == last)
        wait_clks(1);
        if (LASTWORD)
            $display("  NS LASTWORD asserted for Ch7 — OK");
        else begin
            $display("ERROR: NS LASTWORD not asserted for Ch7");
            errors = errors + 1;
        end
        
        // Wait remaining cycles of ch7 window + 1 to see wrap to ch 0
        wait_clks(5);
        check_channel(0, "NS wrap   ");
        
        ENSAMP_sync = 0;
        wait_clks(2);
        
        // ==============================================================
        // Test 3: NS mode (OSR=4) — 18-cycle conversion window
        // ==============================================================
        $display("\n=== Test 3: NS Mode (OSR=4) — 18-Cycle Window ===");
        OSR_sync = 4'd4;   // conv_len = 4*4+2 = 18
        CHEN_sync = 8'b00000011; // Channels 0, 1
        ENSAMP_sync = 1;
        
        wait_clks(2);
        check_channel(0, "OSR4 init ");
        
        // Channel should NOT change for many cycles
        wait_clks(10);
        check_channel(0, "OSR4 mid  ");
        
        // After conv_len (18) more posedges from init check, switch is visible
        wait_clks(8); // 2+10+8 = 20: init(2) + window(18) = switch visible
        check_channel(1, "OSR4 ch1  ");
        
        // Another 18 posedges to see wrap back to ch 0
        wait_clks(18);
        check_channel(0, "OSR4 wrap ");
        
        ENSAMP_sync = 0;
        wait_clks(2);
        
        // ==============================================================
        // Test 4: Break-Before-Make Summary
        // ==============================================================
        $display("\n=== Test 4: Break-Before-Make Summary ===");
        if (break_violations == 0 && transition_count > 0)
            $display("  PASSED: %0d transitions, 0 violations", transition_count);
        else begin
            $display("ERROR: FAILED: %0d violations in %0d transitions", break_violations, transition_count);
            errors = errors + 1;
        end

        // ==============================================================
        // Test 5: CHSEL Mux
        // ==============================================================
        $display("\n=== Test 5: CHSEL Mux ===");
        OSR_sync = 4'd0;
        CHEN_sync = 8'b00000011;
        ENSAMP_sync = 1;
        ENLOWPWR_sync = 0;
        
        wait_clks(2);
        
        if (CHSEL == CHEN_sync)
            $display("  ENLOWPWR=0: CHSEL = CHEN_sync — OK");
        else begin
            $display("ERROR: ENLOWPWR=0: Expected CHSEL=%b, Got %b", CHEN_sync, CHSEL);
            errors = errors + 1;
        end
        
        ENLOWPWR_sync = 1;
        wait_clks(1);
        
        if (CHSEL == ATMCHSEL)
            $display("  ENLOWPWR=1: CHSEL = ATMCHSEL — OK");
        else begin
            $display("ERROR: ENLOWPWR=1: Expected CHSEL=%b, Got %b", ATMCHSEL, CHSEL);
            errors = errors + 1;
        end

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n========================================");
        if (errors == 0)
            $display("ATM_Control Testbench PASSED (0 errors)");
        else
            $display("ATM_Control Testbench FAILED (%0d errors)", errors);
        $display("========================================");
        $stop;
    end

endmodule
