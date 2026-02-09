`timescale 1ns / 1ps

/////////////////////////////////////////////////////////////////////////////////
// Company: MINT NEURO
//
// File: Command_Interpreter.v
// File history:
//     v0.1 - Initial implementation
//
// Description: 
//     Command interpreter for SPI interface
//     Handles register read/write, FIFO data readout, and CRC calculation
//     Separates state transition logic from output generation for clarity
//
// Targeted device: TSMC 65nm
// Author: Ian Williams
//
/////////////////////////////////////////////////////////////////////////////////

module Command_Interpreter (
    // Clock and reset
    input wire NRST,
    input wire CS,
    input wire SCK,
    
    // SPI Core interface
    input wire byte_rcvd,
    input wire word_rcvd,
    input wire [7:0] cmd_byte,
    input wire [7:0] data_byte,
    output wire [15:0] tx_buff,
    
    // FIFO interface
    input wire [127:0] ADC_data,
    output wire FIFO_POP,
    
    // Configuration register interface
    input wire [511:0] cfg_data,
    output wire [5:0] reg_addr,
    output wire [7:0] reg_value,
    output wire wr_en,
    
    // Status and temperature (from different clock domain)
    input wire [13:0] status,
    input wire ENSAMP_sync,
    input wire [15:0] TEMPVAL,

    // Status clear (W1C) request -> HF_CLK domain bridge
    output wire status_clr_req_tgl,
    output wire [7:0] status_clr_lo,
    output wire [5:0] status_clr_hi,
    input wire status_clr_ack_tgl
);

    /////////////////////////////////////////////////////////////////////////////////
    // PARAMETERS
    /////////////////////////////////////////////////////////////////////////////////
    
    // Command opcodes (bits [7:6] of cmd_byte)
    localparam CMD_RDREG  = 2'b00;
    localparam CMD_RDCRC  = 2'b01;
    localparam CMD_WRREG  = 2'b10;
    localparam CMD_RDDATA = 2'b11;
    
    // Response headers
    localparam RESP_REGDATA = 8'hC0;  // 11000000
    localparam RESP_STATUS  = 2'b01;  // bits [1:0] for status response
    
    // State encoding (one-hot)
    localparam IDLE       = 5'b00001;
    localparam READ_REG   = 5'b00010;
    localparam WRITE_REG  = 5'b00100;
    localparam READ_DATA  = 5'b01000;
    localparam READ_CRC   = 5'b10000;
    
    /////////////////////////////////////////////////////////////////////////////////
    // INTERNAL SIGNALS
    /////////////////////////////////////////////////////////////////////////////////
    
    // State machine
    reg [4:0] state, nstate;
    
    // Synchronized inputs from different clock domain
    reg [13:0] status_sync [1:0];
    reg [15:0] TEMPVAL_sync [1:0];
    reg [1:0] ENSAMP_sync_reg;
    
    // Register access
    reg [5:0] reg_addr_reg;
    reg [7:0] reg_value_reg;
    reg       wr_en_reg;
    reg       read_reg_word_count;  // 0=first word (status), 1=second word (data)
    
    // FIFO readout control
    reg [2:0] word_counter;  // 0-7 for 8 words
    reg fifo_pop_reg;
    
    // CRC calculation (modular for potential removal)
    reg [15:0] crc_value;
    reg crc_enable;
    
    // First transaction flag
    reg first_transaction;
    
    // TX buffer control
    reg [15:0] tx_buff_reg;

    /////////////////////////////////////////////////////////////////////////////////
    // STATUS CLEAR (W1C) QUEUE/INFLIGHT (SCK DOMAIN)
    /////////////////////////////////////////////////////////////////////////////////

    reg [7:0] status_clr_queued_lo;
    reg [5:0] status_clr_queued_hi;
    reg [7:0] status_clr_inflight_lo;
    reg [5:0] status_clr_inflight_hi;
    reg status_clr_req_tgl_reg;
    reg status_clr_inflight;

    // Ack toggle synchronizer into SCK domain
    reg [1:0] status_clr_ack_ff;
    reg status_clr_ack_prev;
    wire status_clr_ack_seen;
    assign status_clr_ack_seen = (status_clr_ack_ff[1] ^ status_clr_ack_prev);
    
    /////////////////////////////////////////////////////////////////////////////////
    // CLOCK DOMAIN CROSSING - 2-STAGE SYNCHRONIZERS
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            status_sync[0] <= 14'b0;
            status_sync[1] <= 14'b0;
            TEMPVAL_sync[0] <= 16'b0;
            TEMPVAL_sync[1] <= 16'b0;
            ENSAMP_sync_reg <= 2'b0;
        end else begin
            status_sync[0] <= status;
            status_sync[1] <= status_sync[0];
            TEMPVAL_sync[0] <= TEMPVAL;
            TEMPVAL_sync[1] <= TEMPVAL_sync[0];
            ENSAMP_sync_reg <= {ENSAMP_sync_reg[0], ENSAMP_sync};
        end
    end

    // Ack toggle sync
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            status_clr_ack_ff <= 2'b00;
            status_clr_ack_prev <= 1'b0;
        end else begin
            status_clr_ack_ff <= {status_clr_ack_ff[0], status_clr_ack_tgl};
            status_clr_ack_prev <= status_clr_ack_ff[1];
        end
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // FIRST TRANSACTION DETECTION
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(posedge SCK or posedge CS) begin
        if (CS) begin
            first_transaction <= 1'b1;
        end else if (byte_rcvd) begin
            first_transaction <= 1'b0;
        end
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // STATE TRANSITION LOGIC (COMBINATIONAL)
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(*) begin
        nstate = state;  // Default: stay in current state
        
        case (state)
            IDLE: begin
                if (byte_rcvd) begin
                    case (cmd_byte[7:6])
                        CMD_RDREG:  nstate = READ_REG;
                        CMD_WRREG:  nstate = WRITE_REG;
                        CMD_RDDATA: begin
                            if (cmd_byte[5:0] == 6'b000000)
                                nstate = READ_DATA;
                        end
                        CMD_RDCRC: begin
                            if (cmd_byte[5:0] == 6'b000000)
                                nstate = READ_CRC;
                        end
                        default: nstate = IDLE;
                    endcase
                end
            end
            
            READ_REG: begin
                // Stay in READ_REG for second word (to return register data).
                // After second word completes, return to IDLE.
                if ((word_rcvd && read_reg_word_count == 1'b1) || first_transaction)
                    nstate = IDLE;
            end
            
            WRITE_REG: begin
                if (word_rcvd || first_transaction)
                    nstate = IDLE;
            end
            
            READ_DATA: begin
                if (first_transaction)
                    nstate = IDLE;
                // Stay in READ_DATA until CS goes high (handled by state reset)
            end
            
            READ_CRC: begin
                if (word_rcvd || first_transaction)
                    nstate = IDLE;
            end
            
            default: nstate = IDLE;
        endcase
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // STATE REGISTER (SEQUENTIAL)
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            state <= IDLE;
        end else if (!CS) begin
            state <= nstate;
        end else begin
            state <= IDLE;  // Reset to IDLE when CS is high
        end
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // REGISTER ADDRESS CAPTURE
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            reg_addr_reg <= 6'b0;
            read_reg_word_count <= 1'b0;
        end else if (byte_rcvd && (state == IDLE)) begin
            reg_addr_reg <= cmd_byte[5:0];
            read_reg_word_count <= 1'b0;  // Reset counter on new command
        end else if ((state == READ_REG) && word_rcvd) begin
            read_reg_word_count <= read_reg_word_count + 1'b1;
        end
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // REGISTER WRITE LOGIC
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            reg_value_reg <= 8'b0;
            wr_en_reg <= 1'b0;
        end else if (state == WRITE_REG && word_rcvd) begin
            // Configuration register writes (0x00 - 0x23) only.
            // Write protection: only allow writes when not sampling OR to address 0x23.
            // Keep wr_en high; it will be cleared when state changes or CS goes high.
            if (reg_addr_reg <= 6'h23) begin
                if (!ENSAMP_sync_reg[1] || (reg_addr_reg == 6'h23)) begin
                    reg_value_reg <= data_byte;
                    wr_en_reg <= 1'b1;
                end else begin
                    wr_en_reg <= 1'b0;
                end
            end else begin
                // Non-config writes handled internally (e.g. STATUS_CLR), do not assert wr_en.
                wr_en_reg <= 1'b0;
            end
        end else if (state != WRITE_REG) begin
            // Clear wr_en when leaving WRITE_REG state
            wr_en_reg <= 1'b0;
        end
    end

    // STATUS_CLR W1C handling.
    // 0x26: STATUS_CLR_LO  -> clears SAT[7:0]
    // 0x27: STATUS_CLR_HI  -> clears status[13:8] using bits [5:0] of the written byte
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            status_clr_queued_lo <= 8'h00;
            status_clr_queued_hi <= 6'h00;
            status_clr_inflight_lo <= 8'h00;
            status_clr_inflight_hi <= 6'h00;
            status_clr_req_tgl_reg <= 1'b0;
            status_clr_inflight <= 1'b0;
        end else begin
            // Consume ack
            if (status_clr_ack_seen) begin
                status_clr_inflight <= 1'b0;
                status_clr_inflight_lo <= 8'h00;
                status_clr_inflight_hi <= 6'h00;
            end

            // Queue incoming clear requests (always allowed, even during sampling)
            if (state == WRITE_REG && word_rcvd) begin
                if (reg_addr_reg == 6'h26) begin
                    status_clr_queued_lo <= status_clr_queued_lo | data_byte;
                end else if (reg_addr_reg == 6'h27) begin
                    status_clr_queued_hi <= status_clr_queued_hi | data_byte[5:0];
                end
            end

            // Launch a request when not inflight and something is queued
            if (!status_clr_inflight && ((status_clr_queued_lo != 8'h00) || (status_clr_queued_hi != 6'h00))) begin
                status_clr_inflight_lo <= status_clr_queued_lo;
                status_clr_inflight_hi <= status_clr_queued_hi;
                status_clr_queued_lo <= 8'h00;
                status_clr_queued_hi <= 6'h00;
                status_clr_req_tgl_reg <= ~status_clr_req_tgl_reg;
                status_clr_inflight <= 1'b1;
            end
        end
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // FIFO WORD COUNTER
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            word_counter <= 3'b0;
        end else if (state == READ_DATA) begin
            if (word_rcvd) begin
                word_counter <= word_counter + 1'b1;
            end
        end else begin
            word_counter <= 3'b0;
        end
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // FIFO POP LOGIC
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            fifo_pop_reg <= 1'b0;
        end else begin
            // Pop when transitioning from READ_DATA to IDLE
            // OR when last word (counter = 7) has been read
            if ((state == READ_DATA) && (nstate == IDLE)) begin
                fifo_pop_reg <= 1'b1;
            end else if ((state == READ_DATA) && word_rcvd && (word_counter == 3'b111)) begin
                fifo_pop_reg <= 1'b1;
            end else begin
                fifo_pop_reg <= 1'b0;
            end
        end
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // CRC CALCULATION MODULE (Modular for potential removal)
    /////////////////////////////////////////////////////////////////////////////////
    
    // Simple CRC-16-CCITT implementation
    // This can be easily removed or replaced with a separate module
    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            crc_value  <= 16'hFFFF;
            crc_enable <= 1'b0;
        end else if (state == READ_DATA && word_rcvd) begin
            if (!crc_enable) begin
                // First word in burst: initialize CRC and include this word
                crc_value  <= crc_next(16'hFFFF, tx_buff_reg);
                crc_enable <= 1'b1;
            end else begin
                // Subsequent words: accumulate CRC
                crc_value <= crc_next(crc_value, tx_buff_reg);
            end
        end else if (state != READ_DATA) begin
            crc_value  <= 16'hFFFF;
            crc_enable <= 1'b0;
        end
    end
    
    // CRC calculation function (CRC-16-CCITT)
    function [15:0] crc_next;
        input [15:0] crc_in;
        input [15:0] data_in;
        integer i;
        reg [15:0] crc_temp;
        begin
            crc_temp = crc_in;
            for (i = 0; i < 16; i = i + 1) begin
                if (crc_temp[15] ^ data_in[15-i]) begin
                    crc_temp = {crc_temp[14:0], 1'b0} ^ 16'h1021;
                end else begin
                    crc_temp = {crc_temp[14:0], 1'b0};
                end
            end
            crc_next = crc_temp;
        end
    endfunction
    
    /////////////////////////////////////////////////////////////////////////////////
    // TX BUFFER GENERATION (COMBINATIONAL)
    /////////////////////////////////////////////////////////////////////////////////
    
    always @(*) begin
        tx_buff_reg = 16'h0000;  // Default
        
        case (state)
            IDLE: begin
                // Send status word at start of transaction
                tx_buff_reg = {status_sync[1], RESP_STATUS};
            end
            
            READ_REG: begin
                // First word: send status. Second word: send register data.
                if (read_reg_word_count == 1'b0) begin
                    // First word: status
                    tx_buff_reg = {status_sync[1], RESP_STATUS};
                end else begin
                    // Second word: register data
                    if (reg_addr_reg <= 6'h23) begin
                        // Physical registers 0x00-0x23
                        tx_buff_reg = {RESP_REGDATA, cfg_data[reg_addr_reg*8 +: 8]};
                    end else if (reg_addr_reg == 6'h24) begin
                        // STATUS_LO (SAT[7:0])
                        tx_buff_reg = {RESP_REGDATA, status_sync[1][7:0]};
                    end else if (reg_addr_reg == 6'h25) begin
                        // STATUS_HI (status[13:8] packed into [5:0])
                        tx_buff_reg = {RESP_REGDATA, {2'b00, status_sync[1][13:8]}};
                    end else if (reg_addr_reg == 6'h2C) begin
                        // TEMPVAL high byte
                        tx_buff_reg = {RESP_REGDATA, TEMPVAL_sync[1][15:8]};
                    end else if (reg_addr_reg == 6'h2D) begin
                        // TEMPVAL low byte
                        tx_buff_reg = {RESP_REGDATA, TEMPVAL_sync[1][7:0]};
                    end else begin
                        tx_buff_reg = {RESP_REGDATA, 8'h00};
                    end
                end
            end
            
            WRITE_REG: begin
                // Acknowledge write
                tx_buff_reg = {status_sync[1], RESP_STATUS};
            end
            
            READ_DATA: begin
                // Select 16-bit word from 128-bit ADC_data based on counter
                tx_buff_reg = ADC_data[word_counter*16 +: 16];
            end
            
            READ_CRC: begin
                // Return calculated CRC value
                tx_buff_reg = crc_value;
            end
            
            default: begin
                tx_buff_reg = {status_sync[1], RESP_STATUS};
            end
        endcase
    end
    
    /////////////////////////////////////////////////////////////////////////////////
    // OUTPUT ASSIGNMENTS
    /////////////////////////////////////////////////////////////////////////////////
    
    assign tx_buff   = tx_buff_reg;
    assign reg_addr  = reg_addr_reg;
    assign reg_value = reg_value_reg;
    assign wr_en     = wr_en_reg;
    assign FIFO_POP = fifo_pop_reg;

    // Status clear bridge outputs
    assign status_clr_req_tgl = status_clr_req_tgl_reg;
    assign status_clr_lo = status_clr_inflight_lo;
    assign status_clr_hi = status_clr_inflight_hi;
    
endmodule
