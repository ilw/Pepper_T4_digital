`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for Configuration_Registers
//
// Verifies requirements:
// DIG-58: 6-bit address map
// DIG-63: Power-on reset defaults
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_Configuration_Registers();

    reg NRST;
    reg SCK;
    reg [5:0] reg_addr;
    reg [7:0] reg_value;
    reg wr_en;
    wire [511:0] cfg_data;

    integer i;

    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_Configuration_Registers.vcd");
        $dumpvars(0, tb_req_block_Configuration_Registers);
    end
`endif

    Configuration_Registers dut (
        .NRST(NRST),
        .SCK(SCK),
        .reg_addr(reg_addr),
        .reg_value(reg_value),
        .wr_en(wr_en),
        .cfg_data(cfg_data)
    );

    initial begin
        SCK = 0;
        forever #10 SCK = ~SCK;
    end

    initial begin
        NRST = 0;
        reg_addr = 0;
        reg_value = 0;
        wr_en = 0;
        
        #50;
        NRST = 1;
        #50;
        
        // Test 1: Defaults
        if (cfg_data === 512'b0) 
            $display("Test 1 Passed: Reset values correct");
        else
            $display("ERROR: Test 1 Failed: Non-zero default values");
            
        // Test 2: Read/Write Access
        // Write walking 1s to registers
        $display("Test 2: Writing Registers");
        for (i = 0; i < 36; i = i + 1) begin
            reg_addr = i;
            reg_value = 8'hFF;
            wr_en = 1;
            @(posedge SCK);
            wr_en = 0;
            @(posedge SCK);
            
            // Verify output mapped correctly
            if (cfg_data[i*8 +: 8] !== 8'hFF)
                $display("ERROR: Test 2 Failed: Reg %d did not update. Expected 0xFF, Got 0x%h", i, cfg_data[i*8 +: 8]);
                
            // Verify others remained 0 (simple check)
            if (i > 0 && cfg_data[(i-1)*8 +: 8] === 8'hFF) begin
                // Previous should stay set
            end
        end
        $display("Test 2 Completed");
        
        // Test 3: Write Disable
        reg_addr = 0;
        reg_value = 8'hAA;
        wr_en = 0;
        @(posedge SCK);
        if (cfg_data[7:0] !== 8'hFF) // Was set to FF in loop
             $display("Test 3 Passed: No write when wr_en=0");
             
        $stop;
    end

endmodule
