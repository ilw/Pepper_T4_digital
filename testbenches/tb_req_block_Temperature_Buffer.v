`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for Temperature_Buffer
//
// Verifies requirements:
// DIG-44: Temperature capture
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_Temperature_Buffer();

    reg ENMONTSENSE_sync;
    reg DONE;
    reg NRST_sync;
    reg SAMPLE_CLK;
    reg [15:0] RESULT;
    wire [15:0] TEMPVAL;
    
    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_Temperature_Buffer.vcd");
        $dumpvars(0, tb_req_block_Temperature_Buffer);
    end
`endif
    
    Temperature_Buffer dut (
        .ENMONTSENSE_sync(ENMONTSENSE_sync),
        .DONE(DONE),
        .NRST_sync(NRST_sync),
        .SAMPLE_CLK(SAMPLE_CLK),
        .RESULT(RESULT),
        .TEMPVAL(TEMPVAL)
    );
    
    initial begin
        SAMPLE_CLK = 0;
        forever #50 SAMPLE_CLK = ~SAMPLE_CLK;
    end
    
    initial begin
        ENMONTSENSE_sync = 0;
        DONE = 0;
        NRST_sync = 0;
        RESULT = 0;
        
        #200;
        NRST_sync = 1;
        // Drive ENMONTSENSE_sync transitions aligned away from SAMPLE_CLK posedges
        // to avoid race with DUT sampling.
        @(negedge SAMPLE_CLK);
        ENMONTSENSE_sync = 1;
        
        // Test 1: One-shot capture on first DONE after rising edge
        RESULT = 16'hAAAA;
        // Pulse DONE with stable setup/hold around posedge SAMPLE_CLK
        @(negedge SAMPLE_CLK);
        DONE = 1;
        @(posedge SAMPLE_CLK);
        @(negedge SAMPLE_CLK);
        DONE = 0;
        
        if (TEMPVAL == 16'hAAAA) $display("Pass: Temp captured");
        else $display("ERROR: Fail: Temp not captured");

        // Test 2: Value should not be overwritten while ENMONTSENSE_sync remains high
        RESULT = 16'h5555;
        @(negedge SAMPLE_CLK);
        DONE = 1;
        @(posedge SAMPLE_CLK);
        @(negedge SAMPLE_CLK);
        DONE = 0;

        if (TEMPVAL == 16'hAAAA) $display("Pass: Temp held (no overwrite)");
        else $display("ERROR: Fail: Temp overwritten unexpectedly");

        // Test 3: Drop ENMONTSENSE_sync and re-assert to re-arm one-shot
        @(negedge SAMPLE_CLK);
        ENMONTSENSE_sync = 0;
        repeat (3) @(posedge SAMPLE_CLK);
        @(negedge SAMPLE_CLK);
        ENMONTSENSE_sync = 1;

        RESULT = 16'h5555;
        @(negedge SAMPLE_CLK);
        DONE = 1;
        @(posedge SAMPLE_CLK);
        @(negedge SAMPLE_CLK);
        DONE = 0;

        if (TEMPVAL == 16'h5555) $display("Pass: Temp captured after re-arm");
        else $display("ERROR: Fail: Temp not captured after re-arm");
        
        $stop;
    end

endmodule
