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

    // Task to send 16-bit word
    task send_word;
        input [15:0] data;
        output [15:0] received;
        integer i;
        begin
            received = 16'h0000;
            CS = 0;
            #100;
            
            // Send 16 bits MSB first
            for (i = 15; i >= 0; i = i - 1) begin
                MOSI = data[i];
                #50;
                SCK = 0;  // Falling edge (Mode 3)
                #50;
                received[i] = MISO;
                SCK = 1;  // Rising edge
                #50;
            end
            
            #100;
            CS = 1;
            #100;
        end
    endtask
    
    // Task to read word (MOSI held low)
    task read_word;
        output [15:0] received;
        integer i;
        begin
            received = 16'h0000;
            CS = 0;
            #100;
            
            MOSI = 0;
            for (i = 15; i >= 0; i = i - 1) begin
                #50;
                SCK = 0;
                #50;
                received[i] = MISO;
                SCK = 1;
                #50;
            end
            
            #100;
            CS = 1;
            #100;
        end
    endtask
    
    initial begin
        CS = 1;
        SCK = 1;  // Mode 3 idle high
        MOSI = 0;
    end

endmodule
