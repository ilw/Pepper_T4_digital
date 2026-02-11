`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Testbench for Command_Interpreter (block-level)
//
// Notes:
// - This TB drives the Command_Interpreter using the decoded spiCore-style
//   handshake signals: byte_rcvd, word_rcvd, cmd_byte, data_byte.
// - It does NOT attempt to bit-accurately emulate the full two-word RDREG
//   framing; that is covered by the top-level integration/medium/signoff TBs.
// - Procedural requirement alignment: any "disable sampling" action is kept
//   transaction-separated from data reads (conceptually, CS high between them).
//
// Verifies:
// - Status word formatting in IDLE
// - WRREG write enable pulse and write protection behavior
// - STATUS clear (W1C) request bridge outputs + ack handshake
// - RDDATA burst ordering (from ADC_data)
// - CRC readback placeholder behavior (0xFFFF)
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_Command_Interpreter();

    localparam integer SCK_HALF = 50; // 10MHz

    reg         NRST;
    reg         CS;
    reg         SCK;

    // "spiCore-decoded" handshake inputs
    reg         byte_rcvd;
    reg         word_rcvd;
    reg [7:0]   cmd_byte;
    reg [7:0]   data_byte;

    reg [127:0] ADC_data;
    reg [13:0]  status;
    reg [511:0] cfg_data;
    reg         ENSAMP_sync;
    reg [15:0]  TEMPVAL;

    wire [5:0]  reg_addr;
    wire [7:0]  reg_value;
    wire [15:0] tx_buff;
    wire        FIFO_POP;
    wire        wr_en;

    wire        status_clr_req_tgl;
    wire [7:0]  status_clr_lo;
    wire [5:0]  status_clr_hi;
    reg         status_clr_ack_tgl;

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

    // -------------------------------------------------------------------------
    // SCK helpers (Mode 3: idle high; sample on rising edge)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // High-level "transactions" (decoded-handshake model)
    // -------------------------------------------------------------------------
    task begin_tx;
        begin
            CS = 0;
        end
    endtask

    task end_tx;
        begin
            CS = 1;
            sck_n(2);
        end
    endtask

    // Send RDREG cmd byte (modeled): just asserts byte_rcvd for one sampled edge
    task send_cmd_byte;
        input [7:0] cb;
        begin
            cmd_byte  = cb;
            byte_rcvd = 1;
            sck_cycle;
            byte_rcvd = 0;
        end
    endtask

    // Send "word received" with provided data_byte (modeled)
    task send_data_word;
        input [7:0] db;
        begin
            data_byte = db;
            word_rcvd = 1;
            sck_cycle;
            word_rcvd = 0;
        end
    endtask

    // Write register (WRREG): cmd byte then data byte within the transaction
    task spi_write;
        input [5:0] addr;
        input [7:0] wdata;
        begin
            begin_tx();
            sck_n(2);
            send_cmd_byte({2'b10, addr});
            sck_n(2);
            send_data_word(wdata);
            end_tx();
        end
    endtask

    // Read-data burst (RDDATA): cmd byte then successive word_rcvd strobes
    task spi_read_data_burst;
        output [15:0] w0, w1, w2, w3, w4, w5, w6, w7;
        begin
            begin_tx();
            sck_n(2);
            send_cmd_byte({2'b11, 6'b000000});
            // Allow state to settle into READ_DATA before sampling word0.
            sck_cycle;
            w0 = tx_buff;
            // Each word_rcvd advances word_counter (and may trigger FIFO_POP on word7).
            send_data_word(8'h00); w1 = tx_buff;
            send_data_word(8'h00); w2 = tx_buff;
            send_data_word(8'h00); w3 = tx_buff;
            send_data_word(8'h00); w4 = tx_buff;
            send_data_word(8'h00); w5 = tx_buff;
            send_data_word(8'h00); w6 = tx_buff;
            send_data_word(8'h00); w7 = tx_buff;
            end_tx();
        end
    endtask

    // Read CRC (RDCRC): cmd byte then sample tx_buff in READ_CRC
    task spi_read_crc;
        output [15:0] rdata;
        begin
            begin_tx();
            sck_n(2);
            send_cmd_byte({2'b01, 6'b000000});
            sck_cycle; // allow state to settle
            rdata = tx_buff;
            end_tx();
        end
    endtask

    // -------------------------------------------------------------------------
    // wr_en capture (wr_en may be asserted via NBA; sample after small delay)
    // -------------------------------------------------------------------------
    reg        wr_en_seen;
    reg [5:0]  wr_en_cap_addr;
    reg [7:0]  wr_en_cap_value;
    always @(posedge SCK) begin
        #1;
        if (wr_en) begin
            wr_en_seen = 1'b1;
            wr_en_cap_addr = reg_addr;
            wr_en_cap_value = reg_value;
        end
    end

    // -------------------------------------------------------------------------
    // Status-clear ack model + payload capture at request launch
    // -------------------------------------------------------------------------
    reg        status_clr_seen;
    reg [7:0]  status_clr_seen_lo;
    reg [5:0]  status_clr_seen_hi;

    initial begin
        status_clr_ack_tgl = 1'b0;
        status_clr_seen = 1'b0;
        status_clr_seen_lo = 8'h00;
        status_clr_seen_hi = 6'h00;
    end

    always @(status_clr_req_tgl) begin
        status_clr_seen = 1'b1;
        status_clr_seen_lo = status_clr_lo;
        status_clr_seen_hi = status_clr_hi;
        #(4*SCK_HALF);
        status_clr_ack_tgl = status_clr_req_tgl;
    end

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    integer pass_count, fail_count;
    reg [15:0] rdata;
    reg [15:0] w0, w1, w2, w3, w4, w5, w6, w7;

    initial begin
        NRST      = 0;
        CS        = 1;
        SCK       = 1;
        byte_rcvd = 0;
        word_rcvd = 0;
        cmd_byte  = 8'h00;
        data_byte = 8'h00;
        ADC_data  = 128'h11112222333344445555666677778888;
        status    = 14'h1234;
        cfg_data  = 512'h0;
        ENSAMP_sync = 0;
        TEMPVAL   = 16'hAABB;

        wr_en_seen = 0;
        wr_en_cap_addr = 6'h00;
        wr_en_cap_value = 8'h00;

        pass_count = 0;
        fail_count = 0;

        #200;
        NRST = 1;
        #200;

        $display("========================================");
        $display("Command Interpreter Testbench Starting");
        $display("========================================");

        // Test 1: Status word in IDLE
        $display("\nTest 1: Status Response in IDLE");
        // Need a few SCK cycles to sync status through 2-FF
        begin_tx();
        sck_n(4);
        rdata = tx_buff;
        end_tx();
        if (rdata == 16'h48D1) begin
            $display("  PASSED: Status response = 0x%h", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Expected 0x48D1, Got 0x%h", rdata);
            fail_count = fail_count + 1;
        end

        // Test 2: WRREG allowed when not sampling
        $display("\nTest 2: Register Write (addr 0x10, data 0x55)");
        wr_en_seen = 0;
        spi_write(6'h10, 8'h55);
        if (wr_en_seen && (wr_en_cap_addr == 6'h10) && (wr_en_cap_value == 8'h55)) begin
            $display("  PASSED: wr_en pulsed, addr=0x%h val=0x%h", wr_en_cap_addr, wr_en_cap_value);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Write incorrect. seen=%b addr=0x%h val=0x%h",
                     wr_en_seen, wr_en_cap_addr, wr_en_cap_value);
            fail_count = fail_count + 1;
        end

        // Test 3: Write protection blocks normal reg writes during sampling
        $display("\nTest 3: Write Protection (blocked while sampling)");
        ENSAMP_sync = 1;
        // Need SCK cycles for ENSAMP to sync through 2-FF
        begin_tx(); sck_n(4); end_tx();
        wr_en_seen = 0;
        spi_write(6'h10, 8'hAA);
        if (!wr_en_seen) begin
            $display("  PASSED: Write blocked (wr_en never pulsed)");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: Write went through while ENSAMP high");
            fail_count = fail_count + 1;
        end

        // Test 4: Exception allows writes to 0x23 during sampling
        $display("\nTest 4: Write Protection Exception (0x23 during sampling)");
        wr_en_seen = 0;
        spi_write(6'h23, 8'hFF);
        if (wr_en_seen && (wr_en_cap_addr == 6'h23)) begin
            $display("  PASSED: 0x23 write allowed during sampling");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: 0x23 write was blocked. seen=%b", wr_en_seen);
            fail_count = fail_count + 1;
        end

        // Test 5: W1C status clear (0x26/0x27)
        $display("\nTest 5: W1C Status Clear");
        ENSAMP_sync = 0;
        begin_tx(); sck_n(4); end_tx(); // sync ENSAMP off
        wr_en_seen = 0;
        status_clr_seen = 1'b0;
        spi_write(6'h26, 8'h05);
        if (!wr_en_seen) begin
            $display("  PASSED: wr_en not asserted for 0x26");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: wr_en asserted for 0x26");
            fail_count = fail_count + 1;
        end
        sck_n(8);
        if (status_clr_seen && ((status_clr_seen_lo & 8'h05) == 8'h05)) begin
            $display("  PASSED: status_clr_lo includes 0x05");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status_clr_lo missing bits (got 0x%h)", status_clr_seen_lo);
            fail_count = fail_count + 1;
        end

        wr_en_seen = 0;
        status_clr_seen = 1'b0;
        spi_write(6'h27, 8'h02);
        sck_n(8);
        if (!wr_en_seen) begin
            $display("  PASSED: wr_en not asserted for 0x27");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: wr_en asserted for 0x27");
            fail_count = fail_count + 1;
        end
        if (status_clr_seen && ((status_clr_seen_hi & 6'h02) == 6'h02)) begin
            $display("  PASSED: status_clr_hi includes bit1");
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: status_clr_hi missing bit1 (got 0x%h)", status_clr_seen_hi);
            fail_count = fail_count + 1;
        end

        // Test 6: FIFO Readout (RDDATA)
        $display("\nTest 6: FIFO Readout");
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

        // Test 7: CRC readout placeholder
        $display("\nTest 7: CRC Readout (placeholder)");
        spi_read_crc(rdata);
        if (rdata == 16'hFFFF) begin
            $display("  PASSED: CRC = 0x%h (expected placeholder)", rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("ERROR: CRC unexpected (0x%h)", rdata);
            fail_count = fail_count + 1;
        end

        $display("\n========================================");
        $display("Tests: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");
        if (fail_count != 0) $display("ERROR: Command_Interpreter block TB had failures");
        $stop;
    end

    initial begin
        #1000000;
        $display("ERROR: Testbench timeout!");
        $stop;
    end

endmodule

