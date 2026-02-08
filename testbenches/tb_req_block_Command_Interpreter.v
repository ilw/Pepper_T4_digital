`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for Command_Interpreter
// 
// Uses intermittent SCK (Mode 3: idle high, only toggling during transactions)
// with SPI tasks that emulate the spiCore decoded outputs.
//
// Verifies requirements:
// DIG-4: SPI slave interface
// DIG-5: 16-bit words, MSB-first
// DIG-27: FIFO readout sync
// DIG-30: Write protection
// DIG-48,49,50,51: Register R/W
// DIG-52,53,54: Read data, Status, CRC
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_Command_Interpreter();

    localparam SCK_HALF = 50; // 50ns half-period -> 10MHz SCK

    // Signals
    reg NRST;
    reg CS;
    reg SCK;
    reg byte_rcvd;
    reg word_rcvd;
    reg [7:0] cmd_byte;
    reg [7:0] data_byte;
    reg [127:0] ADC_data;
    reg [13:0] status;
    reg [511:0] cfg_data;
    reg ENSAMP_sync;
    reg [15:0] TEMPVAL;

    wire [5:0] reg_addr;
    wire [7:0] reg_value;
    wire [15:0] tx_buff;
    wire FIFO_POP;
    wire wr_en;
    wire status_clr_req_tgl;
    wire [7:0] status_clr_lo;
    wire [5:0] status_clr_hi;
    reg status_clr_ack_tgl;

    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_Command_Interpreter.vcd");
        $dumpvars(0, tb_req_block_Command_Interpreter);
    end
`endif

    // DUT Instantiation
    Command_Interpreter dut (
        .NRST(NRST),
        .CS(CS),
        .SCK(SCK),
        .byte_rcvd(byte_rcvd),
        .word_rcvd(word_rcvd),
        .cmd_byte(cmd_byte),
        .data_byte(data_byte),
        .ADC_data(ADC_data),
        .status(status),
        .cfg_data(cfg_data),
        .ENSAMP_sync(ENSAMP_sync),
        .TEMPVAL(TEMPVAL),
        .reg_addr(reg_addr),
        .reg_value(reg_value),
        .tx_buff(tx_buff),
        .status_clr_req_tgl(status_clr_req_tgl),
        .status_clr_lo(status_clr_lo),
        .status_clr_hi(status_clr_hi),
        .status_clr_ack_tgl(status_clr_ack_tgl),
        .FIFO_POP(FIFO_POP),
        .wr_en(wr_en)
    );

    //=========================================================================
    // SPI tasks (intermittent SCK, Mode 3: idle high)
    //
    // These emulate the spiCore decoded outputs (byte_rcvd, word_rcvd,
    // cmd_byte, data_byte) while properly toggling SCK so the
    // Command_Interpreter's sequential logic advances.
    //=========================================================================

    task sck_cycle;
        begin
            #SCK_HALF SCK = 0;  // falling edge
            #SCK_HALF SCK = 1;  // rising edge (posedge SCK - CIM samples here)
        end
    endtask

    task sck_n;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) sck_cycle;
        end
    endtask

    // SPI Read Register: send command byte, capture tx_buff response
    task spi_read;
        input [5:0] addr;
        output [15:0] rdata;
        begin
            CS = 0;
            sck_n(7);                           // 7 SCK cycles (bits 0-6)
            cmd_byte = {2'b00, addr};           // RDREG + address
            byte_rcvd = 1;
            sck_cycle;                          // CIM sees byte_rcvd=1 -> transitions to READ_REG
            byte_rcvd = 0;
            sck_cycle;                          // state now READ_REG, tx_buff updated
            rdata = tx_buff;                    // capture response
            sck_n(6);                           // complete 16-bit frame
            CS = 1;
            sck_n(2);                           // inter-transaction gap
        end
    endtask

    // SPI Write Register: send command + data
    task spi_write;
        input [5:0] addr;
        input [7:0] wdata;
        begin
            CS = 0;
            sck_n(7);
            cmd_byte = {2'b10, addr};           // WRREG + address
            byte_rcvd = 1;
            sck_cycle;                          // CIM transitions IDLE -> WRITE_REG
            byte_rcvd = 0;
            sck_n(7);
            data_byte = wdata;
            word_rcvd = 1;
            sck_cycle;                          // CIM processes write
            word_rcvd = 0;
            sck_n(2);
            CS = 1;
            sck_n(2);
        end
    endtask

    // SPI Read Data Burst (RDDATA): 8 x 16-bit words from FIFO
    task spi_read_data_burst;
        output [15:0] w0, w1, w2, w3, w4, w5, w6, w7;
        begin
            CS = 0;
            sck_n(7);
            cmd_byte = {2'b11, 6'b000000};     // RDDATA
            byte_rcvd = 1;
            sck_cycle;                          // CIM enters READ_DATA
            byte_rcvd = 0;
            sck_cycle;                          // state settled
            w0 = tx_buff;                       // Word 0

            sck_n(6); word_rcvd = 1; sck_cycle; word_rcvd = 0; sck_cycle; w1 = tx_buff;
            sck_n(6); word_rcvd = 1; sck_cycle; word_rcvd = 0; sck_cycle; w2 = tx_buff;
            sck_n(6); word_rcvd = 1; sck_cycle; word_rcvd = 0; sck_cycle; w3 = tx_buff;
            sck_n(6); word_rcvd = 1; sck_cycle; word_rcvd = 0; sck_cycle; w4 = tx_buff;
            sck_n(6); word_rcvd = 1; sck_cycle; word_rcvd = 0; sck_cycle; w5 = tx_buff;
            sck_n(6); word_rcvd = 1; sck_cycle; word_rcvd = 0; sck_cycle; w6 = tx_buff;
            sck_n(6); word_rcvd = 1; sck_cycle; word_rcvd = 0; sck_cycle; w7 = tx_buff;

            sck_n(2);
            CS = 1;
            sck_n(2);
        end
    endtask

    // SPI Read CRC
    task spi_read_crc;
        output [15:0] rdata;
        begin
            CS = 0;
            sck_n(7);
            cmd_byte = {2'b01, 6'b000000};     // RDCRC
            byte_rcvd = 1;
            sck_cycle;
            byte_rcvd = 0;
            sck_cycle;
            rdata = tx_buff;
            sck_n(6);
            CS = 1;
            sck_n(2);
        end
    endtask

    //=========================================================================
    // Write-enable capture monitor (wr_en is a single-cycle pulse)
    //=========================================================================
    reg wr_en_seen;
    reg [5:0] wr_en_cap_addr;
    reg [7:0] wr_en_cap_value;

    always @(posedge SCK) begin
        if (wr_en) begin
            wr_en_seen = 1'b1;
            wr_en_cap_addr = reg_addr;
            wr_en_cap_value = reg_value;
        end
    end

    //=========================================================================
    // Ack model: echo req toggle back after a short delay
    //=========================================================================
    initial status_clr_ack_tgl = 1'b0;

    always @(status_clr_req_tgl) begin
        #(4*SCK_HALF);
        status_clr_ack_tgl = status_clr_req_tgl;
    end

    //=========================================================================
    // Test Sequence
    //=========================================================================
    integer pass_count, fail_count;
    reg [15:0] rdata;
    reg [15:0] w0, w1, w2, w3, w4, w5, w6, w7;

    initial begin
        // Initialize
        NRST = 0;
        CS = 1;
        SCK = 1; // Mode 3 idle high
        byte_rcvd = 0;
        word_rcvd = 0;
        cmd_byte = 0;
        data_byte = 0;
        ADC_data = 128'h11112222333344445555666677778888;
        status = 14'h1234;
        cfg_data = 512'h0;
        ENSAMP_sync = 0;
        TEMPVAL = 16'hAABB;
        pass_count = 0;
        fail_count = 0;

        // Reset
        #200;
        NRST = 1;
        #200;

        $display("========================================");
        $display("Command Interpreter Testbench Starting");
        $display("========================================");

        //===== Test 1: Status response in IDLE =====
        $display("\nTest 1: Status Response in IDLE");
        // Need a few SCK cycles to sync status (14'h1234) through 2-FF
        // Expected IDLE tx_buff: {status_sync[1], 2'b01}
        // {14'h1234, 2'b01} = 0100_1000_1101_0001 = 0x48D1
        CS = 0;
        sck_n(4); // sync status through 2-FF
        rdata = tx_buff;
        CS = 1;
        sck_n(2);

        if (rdata == 16'h48D1) begin
            $display("  PASSED: Status response = 0x%h", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Expected 0x48D1, Got 0x%h", rdata);
            fail_count = fail_count + 1;
        end

        //===== Test 2: Register Write =====
        $display("\nTest 2: Register Write (addr 0x10, data 0x55)");
        wr_en_seen = 0;
        spi_write(6'h10, 8'h55);

        if (wr_en_seen && wr_en_cap_addr == 6'h10 && wr_en_cap_value == 8'h55) begin
            $display("  PASSED: wr_en pulsed, addr=0x%h val=0x%h", wr_en_cap_addr, wr_en_cap_value);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Write incorrect. seen=%b addr=0x%h val=0x%h",
                     wr_en_seen, wr_en_cap_addr, wr_en_cap_value);
            fail_count = fail_count + 1;
        end

        //===== Test 3: Write Protection (ENSAMP high, non-0x23 addr) =====
        $display("\nTest 3: Write Protection (blocked while sampling)");
        ENSAMP_sync = 1;
        // Need SCK cycles for ENSAMP to sync through the CIM's 2-FF
        CS = 0; sck_n(4); CS = 1; sck_n(2);

        wr_en_seen = 0;
        spi_write(6'h10, 8'hAA);

        if (!wr_en_seen) begin
            $display("  PASSED: Write blocked (wr_en never pulsed)");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Write went through while ENSAMP high");
            fail_count = fail_count + 1;
        end

        //===== Test 4: Write Protection Exception (addr 0x23) =====
        $display("\nTest 4: Write Protection Exception (0x23 during sampling)");
        // ENSAMP_sync is still 1 from Test 3
        wr_en_seen = 0;
        spi_write(6'h23, 8'hFF);

        if (wr_en_seen && wr_en_cap_addr == 6'h23) begin
            $display("  PASSED: 0x23 write allowed during sampling");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: 0x23 write was blocked. seen=%b", wr_en_seen);
            fail_count = fail_count + 1;
        end

        ENSAMP_sync = 0;
        CS = 0; sck_n(4); CS = 1; sck_n(2); // sync ENSAMP off

        //===== Test 5: Register Read (TEMPVAL high byte) =====
        $display("\nTest 5: Read TEMPVAL high byte (0x2C)");
        // TEMPVAL = 0xAABB -> high byte = 0xAA
        // Sync TEMPVAL through 2-FF first
        CS = 0; sck_n(4); CS = 1; sck_n(2);

        spi_read(6'h2C, rdata);
        if (rdata == {8'hC0, 8'hAA}) begin
            $display("  PASSED: Read 0x2C = 0x%h", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Expected 0xC0AA, Got 0x%h", rdata);
            fail_count = fail_count + 1;
        end

        //===== Test 5b: Status Virtual Registers (0x24/0x25) =====
        $display("\nTest 5b: Read Status Virtual Registers");
        status = 14'b10_0011_1010_0101;
        // Sync new status value
        CS = 0; sck_n(4); CS = 1; sck_n(2);

        // Read STATUS_LO (0x24) -> SAT[7:0] = 0xA5
        spi_read(6'h24, rdata);
        if (rdata == {8'hC0, 8'hA5}) begin
            $display("  PASSED: 0x24 = 0x%h", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: 0x24 expected 0xC0A5, got 0x%h", rdata);
            fail_count = fail_count + 1;
        end

        // Read STATUS_HI (0x25) -> {2'b00, status[13:8]} = 0x23
        spi_read(6'h25, rdata);
        if (rdata == {8'hC0, 8'h23}) begin
            $display("  PASSED: 0x25 = 0x%h", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: 0x25 expected 0xC023, got 0x%h", rdata);
            fail_count = fail_count + 1;
        end

        //===== Test 5c: W1C Status Clear (0x26/0x27) =====
        $display("\nTest 5c: W1C Status Clear");

        // Write 0x05 to 0x26 (clear SAT bits 0 and 2)
        wr_en_seen = 0;
        spi_write(6'h26, 8'h05);
        // wr_en should NOT fire for virtual status clear registers
        if (!wr_en_seen) begin
            $display("  PASSED: wr_en not asserted for 0x26");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: wr_en asserted for 0x26 (should be internal only)");
            fail_count = fail_count + 1;
        end

        // Wait for handshake to complete, then check clear mask
        sck_n(8);
        if ((status_clr_lo & 8'h05) == 8'h05) begin
            $display("  PASSED: status_clr_lo includes 0x05");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status_clr_lo missing bits (got 0x%h)", status_clr_lo);
            fail_count = fail_count + 1;
        end

        // Write 0x02 to 0x27 (clear hi bit1 -> FIFO_OVF)
        wr_en_seen = 0;
        spi_write(6'h27, 8'h02);
        sck_n(8);
        if (!wr_en_seen) begin
            $display("  PASSED: wr_en not asserted for 0x27");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: wr_en asserted for 0x27");
            fail_count = fail_count + 1;
        end
        if ((status_clr_hi & 6'h02) == 6'h02) begin
            $display("  PASSED: status_clr_hi includes bit1");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status_clr_hi missing bit1 (got 0x%h)", status_clr_hi);
            fail_count = fail_count + 1;
        end

        //===== Test 6: FIFO Readout =====
        $display("\nTest 6: FIFO Readout");
        // ADC_data = 128'h11112222333344445555666677778888
        // Word 0 = ADC_data[15:0]   = 0x8888
        // Word 1 = ADC_data[31:16]  = 0x7777
        spi_read_data_burst(w0, w1, w2, w3, w4, w5, w6, w7);

        if (w0 == 16'h8888) begin
            $display("  PASSED: Word 0 = 0x%h", w0);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Word 0 expected 0x8888, got 0x%h", w0);
            fail_count = fail_count + 1;
        end
        if (w1 == 16'h7777) begin
            $display("  PASSED: Word 1 = 0x%h", w1);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Word 1 expected 0x7777, got 0x%h", w1);
            fail_count = fail_count + 1;
        end

        //===== Test 7: CRC Readout =====
        $display("\nTest 7: CRC Readout");
        spi_read_crc(rdata);
        if (rdata != 16'h0000 && rdata != 16'hFFFF) begin
            $display("  PASSED: CRC = 0x%h (non-trivial)", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: CRC looks invalid (0x%h)", rdata);
            fail_count = fail_count + 1;
        end

        //===== Summary =====
        $display("\n========================================");
        $display("Tests: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");
        $stop;
    end

    // Watchdog timeout
    initial begin
        #1000000;
        $display("ERROR: Testbench timeout!");
        $stop;
    end

endmodule
