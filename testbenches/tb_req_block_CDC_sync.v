`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for CDC_sync
//
// Verifies requirements:
// DIG-2/74: Async assert / Sync deassert for Reset
// DIG-82: 2-stage synchronization
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_CDC_sync();

    reg NRST;
    reg HF_CLK;
    reg ENSAMP;
    reg CFG_CHNGE;
    reg [7:0] AFERSTCH;
    reg FIFO_OVERFLOW;
    reg FIFO_UNDERFLOW;
    reg [7:0] SATDETECT;
    reg ADCOVERFLOW;
    reg [11:0] PHASE1DIV1;
    reg [3:0] PHASE1COUNT;
    reg [9:0] PHASE2COUNT;
    reg [7:0] CHEN;
    reg ENLOWPWR;
    reg ENMONTSENSE;
    reg [3:0] ADCOSR;
    
    wire NRST_sync;
    wire ENSAMP_sync;
    wire CFG_CHNGE_sync;
    wire [7:0] AFERSTCH_sync;
    wire FIFO_OVERFLOW_sync;
    wire FIFO_UNDERFLOW_sync;
    wire [7:0] SATDETECT_sync;
    wire ADCOVERFLOW_sync;
    wire [11:0] PHASE1DIV1_sync;
    wire [3:0] PHASE1COUNT_sync;
    wire [9:0] PHASE2COUNT_sync;
    wire [7:0] CHEN_sync;
    wire ENLOWPWR_sync;
    wire ENMONTSENSE_sync;
    wire [3:0] ADCOSR_sync;
    
    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_CDC_sync.vcd");
        $dumpvars(0, tb_req_block_CDC_sync);
    end
`endif
    
    CDC_sync dut (
        .NRST(NRST),
        .HF_CLK(HF_CLK),
        .ENSAMP(ENSAMP),
        .CFG_CHNGE(CFG_CHNGE),
        .AFERSTCH(AFERSTCH),
        .FIFO_OVERFLOW(FIFO_OVERFLOW),
        .FIFO_UNDERFLOW(FIFO_UNDERFLOW),
        .SATDETECT(SATDETECT),
        .ADCOVERFLOW(ADCOVERFLOW),
        .PHASE1DIV1(PHASE1DIV1),
        .PHASE1COUNT(PHASE1COUNT),
        .PHASE2COUNT(PHASE2COUNT),
        .CHEN(CHEN),
        .ENLOWPWR(ENLOWPWR),
        .ENMONTSENSE(ENMONTSENSE),
        .ADCOSR(ADCOSR),
        .NRST_sync(NRST_sync),
        .ENSAMP_sync(ENSAMP_sync),
        .CFG_CHNGE_sync(CFG_CHNGE_sync),
        .AFERSTCH_sync(AFERSTCH_sync),
        .FIFO_OVERFLOW_sync(FIFO_OVERFLOW_sync),
        .FIFO_UNDERFLOW_sync(FIFO_UNDERFLOW_sync),
        .SATDETECT_sync(SATDETECT_sync),
        .ADCOVERFLOW_sync(ADCOVERFLOW_sync),
        .PHASE1DIV1_sync(PHASE1DIV1_sync),
        .PHASE1COUNT_sync(PHASE1COUNT_sync),
        .PHASE2COUNT_sync(PHASE2COUNT_sync),
        .CHEN_sync(CHEN_sync),
        .ENLOWPWR_sync(ENLOWPWR_sync),
        .ENMONTSENSE_sync(ENMONTSENSE_sync),
        .ADCOSR_sync(ADCOSR_sync)
    );
    
    initial begin
        HF_CLK = 0;
        forever #50 HF_CLK = ~HF_CLK;
    end
    
    initial begin
        NRST = 1;
        ENSAMP = 0;
        CFG_CHNGE = 0;
        AFERSTCH = 0;
        FIFO_OVERFLOW = 0;
        FIFO_UNDERFLOW = 0;
        SATDETECT = 0;
        ADCOVERFLOW = 0;
        PHASE1DIV1 = 0;
        PHASE1COUNT = 0;
        PHASE2COUNT = 0;
        CHEN = 0;
        ENLOWPWR = 0;
        ENMONTSENSE = 0;
        ADCOSR = 0;
        
        #100;
        
        // Test 1: Async Reset Assert (DIG-74)
        $display("Test 1: Async Reset Assert");
        NRST = 0;
        #1; // Immediate async drop
        if (NRST_sync == 0) 
            $display("  PASSED: NRST_sync dropped immediately");
        else 
            $display("ERROR: FAILED: NRST_sync did not drop async");
        
        #200;
        
        // Test 1b: Sync Reset Release (DIG-74)
        $display("Test 1b: Sync Reset Release");
        @(negedge HF_CLK); // Change away from clock edge
        NRST = 1;
        
        // Should NOT release immediately
        #1;
        if (NRST_sync == 0)
            $display("  Good: NRST_sync still low (not released yet)");
        
        // Wait for synchronization (2 clocks)
        @(posedge HF_CLK);
        @(posedge HF_CLK);
        #10;
        
        if (NRST_sync == 1) 
            $display("  PASSED: NRST_sync released synchronously");
        else 
            $display("ERROR: FAILED: NRST_sync not released after 2 clocks");
        
        // Test 2: Signal Latency (DIG-82)
        $display("Test 2: 2-Stage Sync Latency");
        @(negedge HF_CLK);
        ENSAMP = 1;
        
        // Should take 2 clock cycles
        @(posedge HF_CLK);
        #1;
        if (ENSAMP_sync == 0)
            $display("  After 1 clock: still 0 (good)");
        
        @(posedge HF_CLK);
        #1;
        if (ENSAMP_sync == 1) 
            $display("  PASSED: Synchronized after 2 clocks");
        else 
            $display("ERROR: FAILED: Not synchronized after 2 clocks");
        
        // Test 3: Bus Synchronization
        $display("Test 3: Bus Synchronization");
        CHEN = 8'b10101010;
        
        @(posedge HF_CLK);
        @(posedge HF_CLK);
        #1;
        
        if (CHEN_sync == 8'b10101010)
            $display("  PASSED: Bus synchronized correctly");
        else
            $display("ERROR: FAILED: Expected 0xAA, got 0x%h", CHEN_sync);
        
        // Test 4: Multi-bit signals
        $display("Test 4: Multi-bit Config Signals");
        PHASE1DIV1 = 12'hABC;
        PHASE2COUNT = 10'h123;
        
        @(posedge HF_CLK);
        @(posedge HF_CLK);
        #1;
        
        if (PHASE1DIV1_sync == 12'hABC && PHASE2COUNT_sync == 10'h123)
            $display("  PASSED: Multi-bit signals synchronized");
        else
            $display("ERROR: FAILED: DIV=%h (exp ABC), CNT=%h (exp 123)", 
                   PHASE1DIV1_sync, PHASE2COUNT_sync);
        
        $display("CDC_sync Testbench Complete");
        $stop;
    end

endmodule
