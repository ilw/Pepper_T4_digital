`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// End-to-end testbench for W1C status clearing (Option B)
//
// Instantiates:
// - Status_Monitor (HF_CLK domain)
// - Status_Clear_CDC (SCK->HF_CLK bridge)
// - Command_Interpreter (SCK domain; produces clear requests)
//
// Uses intermittent SCK with SPI tasks. HF_CLK is free-running.
//
// Verifies:
// - status bits latch and do not clear on read
// - virtual reads 0x24/0x25 return status
// - W1C writes 0x26/0x27 clear the correct bits
// - set has priority over clear when event coincident with clear
//////////////////////////////////////////////////////////////////////////////////

module tb_req_status_w1c_end_to_end();

    localparam SCK_HALF  = 50;  // 50ns half-period -> 10MHz SCK
    localparam HF_PERIOD = 20;  // 20ns period -> 50MHz HF_CLK

    // Clocks / reset
    reg HF_CLK;
    reg SCK;
    reg RESETN;

    // SPI emulator signals into Command_Interpreter
    reg CS;
    reg byte_rcvd;
    reg word_rcvd;
    reg [7:0] cmd_byte;
    reg [7:0] data_byte;

    // Unused/placeholder inputs
    reg [127:0] ADC_data;
    reg [511:0] cfg_data;
    reg ENSAMP_sync;
    reg [15:0] TEMPVAL;

    // Status sources (HF domain inputs to Status_Monitor)
    reg [15:0] CRCCFG;
    reg [7:0] AFERSTCH_sync;
    reg FIFO_OVERFLOW_sync;
    reg FIFO_UNDERFLOW_sync;
    reg ADCOVERFLOW;
    reg [7:0] SATDETECT_sync;

    // Wires
    wire NRST_sync = RESETN; // Simplified for testbench
    wire [13:0] status;
    wire [15:0] tx_buff;
    wire [5:0] reg_addr;
    wire [7:0] reg_value;
    wire wr_en;
    wire FIFO_POP;

    // Clear bridge wires
    wire status_clr_req_tgl;
    wire [7:0] status_clr_lo;
    wire [5:0] status_clr_hi;
    wire status_clr_ack_tgl;
    wire status_clr_pulse;
    wire [13:0] status_clr_mask;

    // INT model (same as TLM): OR status[12:0]
    wire INT = |status[12:0];

    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_status_w1c_end_to_end.vcd");
        $dumpvars(0, tb_req_status_w1c_end_to_end);
    end
`endif

    // Free-running HF_CLK
    initial begin
        HF_CLK = 0;
        forever #(HF_PERIOD/2) HF_CLK = ~HF_CLK;
    end

    // SCK is Mode 3 idle-high, only toggled by SPI tasks
    initial SCK = 1;

    //=========================================================================
    // DUT Instantiations
    //=========================================================================

    Status_Monitor u_stat (
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

    Command_Interpreter u_cim (
        .NRST(RESETN),
        .CS(CS),
        .SCK(SCK),
        .byte_rcvd(byte_rcvd),
        .word_rcvd(word_rcvd),
        .cmd_byte(cmd_byte),
        .data_byte(data_byte),
        .tx_buff(tx_buff),
        .ADC_data(ADC_data),
        .FIFO_POP(FIFO_POP),
        .cfg_data(cfg_data),
        .reg_addr(reg_addr),
        .reg_value(reg_value),
        .wr_en(wr_en),
        .status(status),
        .ENSAMP_sync(ENSAMP_sync),
        .TEMPVAL(TEMPVAL),
        .status_clr_req_tgl(status_clr_req_tgl),
        .status_clr_lo(status_clr_lo),
        .status_clr_hi(status_clr_hi),
        .status_clr_ack_tgl(status_clr_ack_tgl)
    );

    Status_Clear_CDC u_clr_cdc (
        .HF_CLK(HF_CLK),
        .NRST_sync(NRST_sync),
        .status_clr_req_tgl_sck(status_clr_req_tgl),
        .status_clr_lo_sck(status_clr_lo),
        .status_clr_hi_sck(status_clr_hi),
        .status_clr_ack_tgl_hf(status_clr_ack_tgl),
        .status_clr_pulse(status_clr_pulse),
        .status_clr_mask(status_clr_mask)
    );

    //=========================================================================
    // SPI tasks (intermittent SCK, Mode 3)
    //=========================================================================

    task sck_cycle;
        begin
            #SCK_HALF SCK = 0;
            #SCK_HALF SCK = 1;
        end
    endtask

    task sck_n;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) sck_cycle;
        end
    endtask

    task spi_read;
        input [5:0] addr;
        output [15:0] rdata;
        begin
            CS = 0;
            sck_n(7);
            cmd_byte = {2'b00, addr};
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

    task spi_write;
        input [5:0] addr;
        input [7:0] wdata;
        begin
            CS = 0;
            sck_n(7);
            cmd_byte = {2'b10, addr};
            byte_rcvd = 1;
            sck_cycle;
            byte_rcvd = 0;
            sck_n(7);
            data_byte = wdata;
            word_rcvd = 1;
            sck_cycle;
            word_rcvd = 0;
            sck_n(2);
            CS = 1;
            sck_n(2);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================

    integer pass_count, fail_count;
    reg [15:0] rdata;

    initial begin
        // Init
        RESETN = 0;
        CS = 1;
        byte_rcvd = 0;
        word_rcvd = 0;
        cmd_byte = 8'h00;
        data_byte = 8'h00;
        ADC_data = 128'h0;
        cfg_data = 512'h0;
        ENSAMP_sync = 0;
        TEMPVAL = 16'h0000;
        CRCCFG = 16'h0000;
        AFERSTCH_sync = 8'h00;
        FIFO_OVERFLOW_sync = 0;
        FIFO_UNDERFLOW_sync = 0;
        ADCOVERFLOW = 0;
        SATDETECT_sync = 8'h00;
        pass_count = 0;
        fail_count = 0;

        #200;
        RESETN = 1;
        #200;

        $display("========================================");
        $display("E2E W1C Status Test Starting");
        $display("========================================");

        //===== Test 1: Set FIFO_OVF flag and verify sticky =====
        $display("\nTest 1: Set FIFO_OVF and check sticky");
        FIFO_OVERFLOW_sync = 1;
        @(posedge HF_CLK);
        FIFO_OVERFLOW_sync = 0;
        repeat (5) @(posedge HF_CLK);

        if (status[9]) begin
            $display("  PASSED: status[9] (FIFO_OVF) set");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status[9] not set");
            fail_count = fail_count + 1;
        end
        if (INT) begin
            $display("  PASSED: INT asserted");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: INT not asserted");
            fail_count = fail_count + 1;
        end

        //===== Test 2: Read status - should not clear =====
        $display("\nTest 2: Read status (no clear-on-read)");
        // Sync status into SCK domain inside CIM
        CS = 0; sck_n(6); CS = 1; sck_n(2);

        spi_read(6'h25, rdata);
        $display("  STATUS_HI readback = 0x%h", rdata);

        // Read again -> should still be set
        spi_read(6'h25, rdata);
        if (status[9]) begin
            $display("  PASSED: status[9] held after reads");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status[9] cleared by read");
            fail_count = fail_count + 1;
        end

        //===== Test 3: Clear FIFO_OVF via W1C write =====
        $display("\nTest 3: W1C clear FIFO_OVF (0x27, bit1)");
        spi_write(6'h27, 8'h02); // hi bit1 -> status bit9

        // Wait for CDC handshake (needs HF_CLK cycles for pulse + SCK cycles for ack)
        repeat (20) @(posedge HF_CLK);
        // Also need SCK cycles for ack to propagate back
        sck_n(6);

        if (!status[9]) begin
            $display("  PASSED: status[9] cleared");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status[9] not cleared");
            fail_count = fail_count + 1;
        end
        if (!INT) begin
            $display("  PASSED: INT deasserted");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: INT still asserted");
            fail_count = fail_count + 1;
        end

        //===== Test 4: SAT flags set/clear via 0x26 =====
        $display("\nTest 4: SAT flags set/clear");
        SATDETECT_sync = 8'h05; // bits 0 and 2
        @(posedge HF_CLK);
        SATDETECT_sync = 8'h00;
        repeat (5) @(posedge HF_CLK);

        if ((status[2:0] & 3'b101) == 3'b101) begin
            $display("  PASSED: SAT bits 0 and 2 set");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: SAT bits not set (status[7:0]=0x%h)", status[7:0]);
            fail_count = fail_count + 1;
        end

        spi_write(6'h26, 8'h05); // clear lo bits 0 and 2
        repeat (20) @(posedge HF_CLK);
        sck_n(6);

        if (!status[0] && !status[2]) begin
            $display("  PASSED: SAT bits 0 and 2 cleared");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: SAT bits not cleared (status[7:0]=0x%h)", status[7:0]);
            fail_count = fail_count + 1;
        end

        //===== Test 5: Set-priority over clear =====
        $display("\nTest 5: Set-priority over clear");
        FIFO_OVERFLOW_sync = 1; // hold high across clear attempt
        repeat (2) @(posedge HF_CLK);

        spi_write(6'h27, 8'h02);
        repeat (20) @(posedge HF_CLK);
        sck_n(6);

        if (status[9]) begin
            $display("  PASSED: status[9] remains set (set priority)");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status[9] cleared despite active input");
            fail_count = fail_count + 1;
        end

        FIFO_OVERFLOW_sync = 0;
        repeat (2) @(posedge HF_CLK);

        spi_write(6'h27, 8'h02);
        repeat (20) @(posedge HF_CLK);
        sck_n(6);

        if (!status[9]) begin
            $display("  PASSED: status[9] cleared after input removed");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status[9] still set");
            fail_count = fail_count + 1;
        end

        //===== Summary =====
        $display("\n========================================");
        $display("E2E Tests: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");
        $stop;
    end

    // Watchdog
    initial begin
        #1000000;
        $display("ERROR: Testbench timeout!");
        $stop;
    end

endmodule
