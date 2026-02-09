///////////////////////////////////////////////////////////////////////////////////////////////////
// Company: <MINT NEURO>
//
// File: spiCore.v
// File history:
// Version v0.2     
//
// Description: 
//
// SPI read and write using no synchronisation. Schmitt triggered inputs required
//
// Targeted device: TSMC 65nm
// Author: Ian Williams
//
/////////////////////////////////////////////////////////////////////////////////////////////////// 


`timescale 1ns / 1ps

module spiCore(
//inputs
NRST, 
SCK, 
PICO, 
CS, 
tx_buff,
//outputs
byte_rcvd,
word_rcvd,
POCI,
cmd_byte,
data_byte
);







/////////////////////////////////////////////////////////////////////////////////
// VARIABLES
/////////////////////////////////////////////////////////////////////////////////
//{
input NRST, SCK, CS, PICO;
input [15:0]tx_buff;
(* keep = 1 *) output wire word_rcvd /* cadence preserve_sequential */;  
output POCI;
output wire [7:0] cmd_byte;
output wire [7:0] data_byte;
output wire byte_rcvd;

//Receiving registers / wires
reg [3:0] bitcnt, bitcnt_n; // SPI in 16-bits format, so  4 bit counter 
reg [15:0] data_in;

// Expose stable "current" bytes and strobes combinationally so downstream
// SCK-domain logic can use them on the same rising edge (mode 3 sampling edge).
// This avoids same-edge NB visibility issues without sampling PICO on negedge.
reg [7:0] cmd_byte_reg;
reg [7:0] data_byte_reg;

//Sending registers / wires
reg [15:0] data_send;

wire SCK_CS;


//}








///////////////////////////////////////////////////////
// RECEIVING
///////////////////////////////////////////////////////

//{ 

always @(posedge SCK or posedge CS)
begin
	if (CS) bitcnt <=0;
	else bitcnt <= bitcnt + 1'b1;
end

always @(posedge SCK or posedge CS)
begin
	if (CS) data_in <=0;
	// implement a shift-left register (since we receive the data MSB first)
	else data_in[15:0]<= {data_in[14:0], PICO};
end



// Registered copies (for non-boundary cycles)
always @(posedge SCK or posedge CS)
begin
	if (CS) begin
		cmd_byte_reg  <= 8'h00;
		data_byte_reg <= 8'h00;
	end else begin
		if (bitcnt == 4'b0111) cmd_byte_reg  <= {data_in[6:0], PICO};
		if (bitcnt == 4'b1111) data_byte_reg <= {data_in[6:0], PICO};
	end
end

// Combinational "this-edge" visibility
assign byte_rcvd = (!CS) && (bitcnt == 4'b0111);
assign word_rcvd = (!CS) && (bitcnt == 4'b1111);
assign cmd_byte  = byte_rcvd ? {data_in[6:0], PICO} : cmd_byte_reg;
assign data_byte = word_rcvd ? {data_in[6:0], PICO} : data_byte_reg;





//}


/////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////
//	SENDING
/////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////

//{

always @(negedge SCK or posedge CS)
begin
	if (CS) bitcnt_n <=15; 
	else bitcnt_n <= bitcnt_n +1; 
end



//always @(negedge SCK or negedge CS or negedge NRST)
always @(negedge SCK) 
begin
	data_send <=  (bitcnt == 0)  ? tx_buff : data_send; 
end



assign POCI = CS ? 1'bz : data_send[15-bitcnt_n];  
assign SCK_CS = SCK || CS;


//}

endmodule
