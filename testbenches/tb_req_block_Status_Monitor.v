`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for Status_Monitor
//
// Verifies requirements:
// DIG-19/21: FIFO flags
// DIG-42: Saturation flags
// DIG-86-90: Aggregated status
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_Status_Monitor();

    reg NRST_sync;
    reg HF_CLK;
    reg ENSAMP_sync;
    reg [15:0] CRCCFG;
    reg [7:0] AFERSTCH_sync;
    reg FIFO_OVERFLOW_sync;
    reg FIFO_UNDERFLOW_sync;
    reg ADCOVERFLOW;
    reg [7:0] SATDETECT_sync;
    reg status_clr_pulse;
    reg [13:0] status_clr_mask;
    
    wire [13:0] status;

    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_Status_Monitor.vcd");
        $dumpvars(0, tb_req_block_Status_Monitor);
    end
`endif

    Status_Monitor dut (
        .NRST_sync(NRST_sync),
        .HF_CLK(HF_CLK),
        .ENSAMP_sync(ENSAMP_sync),
        .CRCCFG(CRCCFG),
        .AFERSTCH_sync(AFERSTCH_sync),
        .FIFO_OVERFLOW_sync(FIFO_OVERFLOW_sync),
        .FIFO_UNDERFLOW_sync(FIFO_UNDERFLOW_sync),
        .ADCOVERFLOW(ADCOVERFLOW),
        .SATDETECT_sync(SATDETECT_sync),
        .status_clr_pulse(status_clr_pulse),
        .status_clr_mask(status_clr_mask),
        .status(status)
    );
    
    initial begin
        HF_CLK = 0;
        forever #50 HF_CLK = ~HF_CLK;
    end
    
    initial begin
        NRST_sync = 0;
        ENSAMP_sync = 0;
        CRCCFG = 0;
        AFERSTCH_sync = 0;
        FIFO_OVERFLOW_sync = 0;
        FIFO_UNDERFLOW_sync = 0;
        ADCOVERFLOW = 0;
        SATDETECT_sync = 0;
        status_clr_pulse = 0;
        status_clr_mask = 14'b0;
        
        #200;
        NRST_sync = 1;
        #100;
        
        // Test 1: Flag set and sticky
        $display("Test 1: Sticky Flags");
        FIFO_OVERFLOW_sync = 1;
        @(posedge HF_CLK);
        FIFO_OVERFLOW_sync = 0;
        @(posedge HF_CLK);
        
        // Output format: [13:ENSAMP, 12:CFGCHNG, 11:ANALOG_RESET, 10:FIFO_UDF, 9:FIFO_OVF, 8:ADC_OVF, 7:0:SAT]
        // Expect bit 9 set.
        if (status[9] === 1'b1) $display("Test 1 Passed: Bit 9 Set");
        else $display("ERROR: Test 1 Failed: Bit 9 not set");
        
        // Test 2: Clear via W1C pulse+mask
        $display("Test 2: Clear");
        status_clr_mask[9] = 1'b1; // clear FIFO_OVF
        status_clr_pulse = 1;
        @(posedge HF_CLK);
        status_clr_pulse = 0;
        status_clr_mask = 14'b0;
        @(posedge HF_CLK);
        
        if (status[9] === 1'b0) $display("Test 2 Passed: Cleared");
        else $display("ERROR: Test 2 Failed: Not cleared");
        
        // Test 3: Saturation
        $display("Test 3: Saturation");
        SATDETECT_sync = 8'h05; // Bits 0 and 2
        @(posedge HF_CLK);
        SATDETECT_sync = 0;
        @(posedge HF_CLK);
        
        if (status[0] && status[2]) $display("Test 3 Passed: Sat bits set");
        else $display("ERROR: Test 3 Failed: Sat bits=%b", status[7:0]);

        // Clear sat bits 0 and 2
        status_clr_mask[0] = 1'b1;
        status_clr_mask[2] = 1'b1;
        status_clr_pulse = 1;
        @(posedge HF_CLK);
        status_clr_pulse = 0;
        status_clr_mask = 14'b0;
        @(posedge HF_CLK);
        
        $stop;
    end

endmodule
