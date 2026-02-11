`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Simple SPI Master BFM (Bus Functional Model)
//
// Provides basic SPI master functionality for testbench
//////////////////////////////////////////////////////////////////////////////////

module spi_master_bfm (
    output reg CS,
    output reg SCK,
    output reg MOSI,
    input wire MISO
);

    // SPI mode 3 helpers (CPOL=1, CPHA=1):
    // - SCK idles high
    // - Master changes MOSI on falling edge
    // - Master samples MISO on rising edge
    task begin_transaction;
        begin
            CS = 0;
            #100;
        end
    endtask

    task end_transaction;
        begin
            #100;
            CS = 1;
            #100;
        end
    endtask

    // Exactly 16 SCK cycles (16 rising edges).
    // Use this for multi-word transfers where CS stays low across words
    // (e.g. RDREG second-word readback, RDDATA bursts).
    task transfer_word16;
        input  [15:0] data;
        output [15:0] received;
        integer i;
        begin
            received = 16'h0000;
            for (i = 15; i >= 0; i = i - 1) begin
                MOSI = data[i];
                #50;
                SCK = 0;
                #50;
                SCK = 1;
                #25;
                received[i] = MISO;
                #25;
            end
        end
    endtask

    task transfer_word;
        input  [15:0] data;
        output [15:0] received;
        integer i;
        begin
            received = 16'h0000;
            // Send 16 bits MSB first
            for (i = 15; i >= 0; i = i - 1) begin
                MOSI = data[i];
                #50;
                SCK = 0;  // falling
                #50;
                SCK = 1;  // rising (sample)
                #25;
                received[i] = MISO;
                #25;
            end
            // Mode 3: Add one more SCK cycle after 16 bits to ensure downstream
            // logic clocked on posedge SCK can see any control signals (like wr_en)
            // that were set during the 16th bit.
            #50;
            SCK = 0;
            #50;
            SCK = 1;
            #50;
        end
    endtask

    // Backward-compatible single-word helpers (toggle CS per word)
    task send_word;
        input [15:0] data;
        output [15:0] received;
        begin
            begin_transaction();
            transfer_word(data, received);
            end_transaction();
        end
    endtask
    
    task read_word;
        output [15:0] received;
        begin
            MOSI = 0;
            send_word(16'h0000, received);
        end
    endtask
    
    initial begin
        CS = 1;
        SCK = 1;  // Mode 3 idle high
        MOSI = 0;
    end

endmodule
