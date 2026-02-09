`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// SPI → Command_Interpreter → Configuration_Registers integration testbench
//
// Purpose:
// - Exercise SPI register write/readback using the real `spiCore` and
//   `Command_Interpreter` connected to the real `Configuration_Registers`.
// - Provide internal visibility into the write handshake:
//     - spiCore: cmd_byte/data_byte/word_rcvd
//     - Command_Interpreter: reg_addr/reg_value/wr_en
//     - Configuration_Registers: internal `regs[]` contents
//
// This TB is intentionally minimal (no HF clock domain, FIFO, etc.)
// so we can debug register writes thoroughly first.
//////////////////////////////////////////////////////////////////////////////////

module tb_spi_cim_cfg_regs;
    // -------------------------------------------------------------------------
    // DUT wiring (SCK domain)
    // -------------------------------------------------------------------------
    reg  NRST;
    reg  CS;
    reg  SCK;
    reg  MOSI;
    wire MISO;

    wire        byte_rcvd;
    wire        word_rcvd;
    wire [7:0]  cmd_byte;
    wire [7:0]  data_byte;

    wire [15:0] tx_buff;

    wire [5:0]  reg_addr;
    wire [7:0]  reg_value;
    wire        wr_en;

    wire [511:0] cfg_data;

    // Unused interfaces for this focused TB
    wire [127:0] ADC_data = 128'h0;
    wire [13:0]  status   = 14'h0;
    wire         ENSAMP_sync = 1'b0;
    wire [15:0]  TEMPVAL  = 16'h0;

    wire         FIFO_POP;

    wire         status_clr_req_tgl;
    wire [7:0]   status_clr_lo;
    wire [5:0]   status_clr_hi;
    wire         status_clr_ack_tgl = 1'b0;

    // -------------------------------------------------------------------------
    // Instantiate: spiCore → Command_Interpreter → Configuration_Registers
    // -------------------------------------------------------------------------
    spiCore u_spi (
        .NRST(NRST),
        .SCK(SCK),
        .PICO(MOSI),
        .CS(CS),
        .tx_buff(tx_buff),
        .byte_rcvd(byte_rcvd),
        .word_rcvd(word_rcvd),
        .POCI(MISO),
        .cmd_byte(cmd_byte),
        .data_byte(data_byte)
    );

    Command_Interpreter u_cim (
        .NRST(NRST),
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

    Configuration_Registers u_cfg (
        .NRST(NRST),
        .SCK(SCK),
        .reg_addr(reg_addr),
        .reg_value(reg_value),
        .wr_en(wr_en),
        .cfg_data(cfg_data)
    );

    // -------------------------------------------------------------------------
    // SPI mode 3 master tasks (CPOL=1, CPHA=1)
    // -------------------------------------------------------------------------
    task spi_txrx_word_noframe;
        input  [15:0] data;
        output [15:0] received;
        integer i;
        begin
            received = 16'h0000;
            CS = 1'b0;
            #100;

            // Mode 3 timing:
            // - Change MOSI on falling edges
            // - Sample MISO on rising edges
            for (i = 15; i >= 0; i = i - 1) begin
                MOSI = data[i];
                #50;
                SCK = 1'b0;   // falling
                #50;
                SCK = 1'b1;   // rising (sample)
                #25;
                received[i] = MISO;
                #25;
            end

        end
    endtask

    task spi_txrx_word;
        input  [15:0] data;
        output [15:0] received;
        begin
            CS = 1'b0;
            #100;
            spi_txrx_word_noframe(data, received);
            #100;
            CS = 1'b1;
            #200;
        end
    endtask

    task spi_read_word;
        output [15:0] received;
        integer i;
        begin
            received = 16'h0000;
            CS = 1'b0;
            #100;

            MOSI = 1'b0;
            for (i = 15; i >= 0; i = i - 1) begin
                #50;
                SCK = 1'b0;
                #50;
                SCK = 1'b1;
                #25;
                received[i] = MISO;
                #25;
            end

            #100;
            CS = 1'b1;
            #200;
        end
    endtask

    // -------------------------------------------------------------------------
    // Debug monitors
    // -------------------------------------------------------------------------
    always @(posedge SCK) begin
        if (byte_rcvd)
            $display("t=%0t byte_rcvd cmd=0x%02h data=0x%02h", $time, cmd_byte, data_byte);
        if (word_rcvd)
            $display("t=%0t word_rcvd cmd=0x%02h data=0x%02h", $time, cmd_byte, data_byte);
        if (wr_en)
            $display("t=%0t WR_EN addr=0x%02h value=0x%02h", $time, reg_addr, reg_value);
    end

    // Convenience: show selected cfg regs after any wr_en pulse
    task show_reg;
        input [5:0] addr;
        begin
            $display("  cfg[0x%02h] = 0x%02h", addr, u_cfg.regs[addr]);
        end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    reg [15:0] rx;
    reg [15:0] rd;

    initial begin
        // Waveforms
        $dumpfile("simulation/tb_spi_cim_cfg_regs.vcd");
        $dumpvars(0, tb_spi_cim_cfg_regs);

        // Defaults
        NRST = 1'b0;
        CS   = 1'b1;
        SCK  = 1'b1;  // mode 3 idle high
        MOSI = 1'b0;

        #500;
        NRST = 1'b1;
        #500;

        $display("========================================");
        $display("SPI/CIM/CFG test starting");
        $display("========================================");

        // ---------------------------------------------------------------------
        // Readback baseline (REG 0x23)
        // RDREG opcode: cmd_byte[7:6]=00, addr=0x23
        // Command_Interpreter returns status on 1st word, register data on 2nd.
        // CS must remain low across both 16-bit transfers.
        // ---------------------------------------------------------------------
        CS = 1'b0;
        #100;
        spi_txrx_word_noframe(16'h2300, rx);
        $display("  Status response: 0x%04h", rx);
        spi_txrx_word_noframe(16'h0000, rd);
        #100;
        CS = 1'b1;
        #200;
        $display("RD 0x23 -> 0x%04h (data)", rd);
        show_reg(6'h23);

        // ---------------------------------------------------------------------
        // Write REG 0x23 = 0x80 (ENSAMP bit at [7] per TLM mapping)
        // WRREG opcode: cmd_byte[7:6]=10 => 0x80 | addr
        // ---------------------------------------------------------------------
        spi_txrx_word(16'hA380, rx);
        $display("WR 0x23 = 0x80, status/ack=0x%04h", rx);
        #500;
        show_reg(6'h23);

        // Readback 0x23
        CS = 1'b0;
        #100;
        spi_txrx_word_noframe(16'h2300, rx);
        spi_txrx_word_noframe(16'h0000, rd);
        #100;
        CS = 1'b1;
        #200;
        $display("RD 0x23 -> 0x%04h (data)", rd);
        show_reg(6'h23);

        // ---------------------------------------------------------------------
        // Write/read a second register (0x1B) to confirm general write path
        // ---------------------------------------------------------------------
        spi_txrx_word(16'h9B10, rx); // WR 0x1B = 0x10
        $display("WR 0x1B = 0x10, status/ack=0x%04h", rx);
        #500;
        show_reg(6'h1B);

        CS = 1'b0;
        #100;
        spi_txrx_word_noframe(16'h1B00, rx);
        spi_txrx_word_noframe(16'h0000, rd);
        #100;
        CS = 1'b1;
        #200;
        $display("RD 0x1B -> 0x%04h (data)", rd);
        show_reg(6'h1B);

        $display("========================================");
        $display("SPI/CIM/CFG test done");
        $display("========================================");
        #1000;
        $stop;
    end

    // Timeout
    initial begin
        #2_000_000;
        $display("ERROR: Timeout in tb_spi_cim_cfg_regs");
        $stop;
    end
endmodule

