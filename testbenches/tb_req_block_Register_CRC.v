`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for Register_CRC
//
// Verifies requirements:
// DIG-66: CRC/Checksum calculation
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_Register_CRC();

    reg [511:0] cfg_data;
    reg NRST;
    wire [15:0] CRCCFG;
    
    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_Register_CRC.vcd");
        $dumpvars(0, tb_req_block_Register_CRC);
    end
`endif
    
    Register_CRC dut (
        .cfg_data(cfg_data),
        .CRCCFG(CRCCFG)
    );
    
    initial begin
        NRST = 1;
        cfg_data = 0;
        #10;
        
        // Test 1: Zero data -> Zero CRC
        if (CRCCFG == 0) $display("Pass: Zero input");
        else $display("ERROR: Fail: Zero input gave %h", CRCCFG);
        
        // Test 2: Single Bit
        cfg_data[0] = 1;
        #10;
        // Bit 0 corresponds to slice 0
        if (CRCCFG[0] == 1) $display("Pass: Bit 0 reflected");
        else $display("ERROR: Fail: Bit 0 not set");
        
        // Test 3: Bit 16 (matches bit 0 in XOR slice)
        cfg_data[16] = 1; 
        #10;
        // 1 XOR 1 = 0
        if (CRCCFG[0] == 0) $display("Pass: XOR cancellation");
        else $display("ERROR: Fail: No cancellation");
        
        $stop;
    end

endmodule
