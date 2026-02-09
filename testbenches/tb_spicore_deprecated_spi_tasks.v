`timescale 1ns/100ps

//////////////////////////////////////////////////////////////////////////////////
// spiCore testbench using SPI tasks from deprecated `tb_TLM.v`
//
// Goal:
// - Reuse the same SPI task structure (`spi_pre`, `spi_word`, `spi_post`, `spi`,
//   `spix2`) to validate the current `spiCore` behavior.
// - Check:
//   - MOSI → `cmd_byte` / `data_byte` capture
//   - `byte_rcvd` / `word_rcvd` boundary strobes
//   - `POCI` (MISO) shifting out of `tx_buff`
//
// Notes vs `testbenches/spi_master_bfm.v`:
// - Both implement "change MOSI on falling edge, sample MISO on rising edge".
// - The deprecated tasks become **mode 3** (CPOL=1, CPHA=1) when SCK idles high.
//   This TB sets SCK=1 initially so the first action in `spi_word` (SCK=0) is a
//   leading falling edge, matching what `spiCore`'s transmitter expects.
//////////////////////////////////////////////////////////////////////////////////

module tb_spicore_deprecated_spi_tasks;
    // -------------------------------------------------------------------------
    // Parameters copied from deprecated tb (with jitter disabled by default)
    // -------------------------------------------------------------------------
    parameter SPICLK_PERIOD = 50; // nominal
    parameter JITTER = 0;

    // -------------------------------------------------------------------------
    // SPI wires
    // -------------------------------------------------------------------------
    reg  NRST;
    reg  CS, SCK;
    wire POCI;
    wire PICO;

    reg  [15:0] tx_buff;
    wire        byte_rcvd;
    wire        word_rcvd;
    wire [7:0]  cmd_byte;
    wire [7:0]  data_byte;

    // Task globals (matching deprecated tb style)
    reg [15:0] data_send, data_rcv, data_rx, data_tx;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    spiCore dut (
        .NRST(NRST),
        .SCK(SCK),
        .PICO(PICO),
        .CS(CS),
        .tx_buff(tx_buff),
        .byte_rcvd(byte_rcvd),
        .word_rcvd(word_rcvd),
        .POCI(POCI),
        .cmd_byte(cmd_byte),
        .data_byte(data_byte)
    );

    // Deprecated tb assignment
    assign PICO = data_send[15];

    // -------------------------------------------------------------------------
    // Debug monitors (strobe visibility at rising edge)
    // -------------------------------------------------------------------------
    always @(posedge SCK) begin
        if (!CS && byte_rcvd)
            $display("t=%0t byte_rcvd cmd=0x%02h", $time, cmd_byte);
        if (!CS && word_rcvd)
            $display("t=%0t word_rcvd data=0x%02h", $time, data_byte);
    end

    // -------------------------------------------------------------------------
    // SPI tasks copied from deprecated `tb_TLM.v`
    // -------------------------------------------------------------------------
    integer a,b,c,d;

    task spi_pre();
    begin
        #(SPICLK_PERIOD + $random %(JITTER));
        CS=0;
        #(SPICLK_PERIOD / 2.0 + $random %(JITTER));
    end
    endtask

    task spi_word();
    begin
        // IMPORTANT: with SCK idling high, this first assignment generates the
        // leading falling edge (mode 3), allowing spiCore to load tx_buff before
        // the first rising-edge sample.
        SCK =0;
        #(SPICLK_PERIOD / 2.0 + $random %(JITTER));
        data_tx = data_send;
        repeat (15)
        begin
            SCK =1;
            data_rcv = {data_rcv[14:0],POCI}; // read on rising edge
            #(SPICLK_PERIOD / 2.0 + $random %(JITTER));
            SCK =0;
            data_send = data_send <<1; // transition on falling edge
            #(SPICLK_PERIOD / 2.0 + $random %(JITTER));
        end
        SCK =1;
        data_rcv = {data_rcv[14:0],POCI}; // read on rising edge
        #(SPICLK_PERIOD / 2.0 + $random %(JITTER));
        data_rx = data_rcv;
    end
    endtask

    task spi_post();
    begin
        #(SPICLK_PERIOD / 2.0 + $random %(JITTER));
        CS=1;
        #(SPICLK_PERIOD + $random %(JITTER));
    end
    endtask

    task spi();
    begin
        spi_pre;
        spi_word;
        spi_post;
    end
    endtask

    task spix2();
    begin
        spi_pre;
        spi_word;
        spi_word;
        spi_post;
    end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    task expect_eq16(input [15:0] got, input [15:0] exp, input [256*8-1:0] what);
    begin
        if (got !== exp) begin
            $display("ERROR: %0s got=0x%04h exp=0x%04h", what, got, exp);
            $stop;
        end
    end
    endtask

    task expect_eq8(input [7:0] got, input [7:0] exp, input [256*8-1:0] what);
    begin
        if (got !== exp) begin
            $display("ERROR: %0s got=0x%02h exp=0x%02h", what, got, exp);
            $stop;
        end
    end
    endtask

    initial begin
        $dumpfile("simulation/tb_spicore_deprecated_spi_tasks.vcd");
        $dumpvars(0, tb_spicore_deprecated_spi_tasks);

        // Reset + idle
        NRST = 1'b0;
        CS   = 1'b1;
        SCK  = 1'b1; // idle high -> mode 3 framing for these tasks
        data_send = 16'h0000;
        data_rcv  = 16'h0000;
        data_rx   = 16'h0000;
        tx_buff   = 16'hBEEF;

        #500;
        NRST = 1'b1;
        #500;

        $display("========================================");
        $display("spiCore deprecated-task smoke test");
        $display("========================================");

        // 1) Send a command word and check cmd/data capture.
        //    Example: 0xA380 => cmd=0xA3, data=0x80
        data_send = 16'hA380;
        data_rcv  = 16'h0000;
        spi();
        expect_eq8(cmd_byte,  8'hA3, "cmd_byte capture");
        expect_eq8(data_byte, 8'h80, "data_byte capture");

        // 2) Check MISO shifts out tx_buff (spiCore uses tx_buff on negedge SCK)
        //    Perform a dummy read word with MOSI=0 to clock out tx_buff.
        data_send = 16'h0000;
        data_rcv  = 16'h0000;
        tx_buff   = 16'hCAFE;
        spi();
        expect_eq16(data_rx, 16'hCAFE, "POCI shift-out (tx_buff)");

        // 3) Two-word transaction (CS held low across 32 clocks)
        //    This matches how Command_Interpreter returns status on the first word
        //    and data on the second word.
        tx_buff   = 16'h1234;
        data_send = 16'h2300; // RDREG 0x23 (example)
        data_rcv  = 16'h0000;
        spix2();
        // For spiCore alone, just ensure we got 16 bits back (not X) on the first word.
        if (^data_rx === 1'bX) begin
            $display("ERROR: spix2 received Xs on POCI");
            $stop;
        end

        $display("PASS: spiCore behaves as expected with deprecated SPI tasks.");
        #1000;
        $stop;
    end

    initial begin
        #2_000_000;
        $display("ERROR: Timeout in tb_spicore_deprecated_spi_tasks");
        $stop;
    end
endmodule

