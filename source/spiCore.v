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
(* keep = 1 *) output reg word_rcvd /* cadence preserve_sequential */;  
output POCI;
output reg [7:0] cmd_byte;
output reg [7:0] data_byte;
output reg byte_rcvd;

//Receiving registers / wires
reg [3:0] bitcnt, bitcnt_n; // SPI in 16-bits format, so  4 bit counter 
reg [15:0] data_in;

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



always @(posedge SCK)
begin
	cmd_byte[7:0] <= (bitcnt == 4'b0111) ? {data_in[6:0], PICO} : cmd_byte[7:0] ;
	data_byte[7:0]<= (bitcnt == 4'b1111) ? {data_in[6:0], PICO} : data_byte[7:0];
end

always @(posedge SCK or posedge CS)
begin
	if (CS) 
	begin
		byte_rcvd <=0;
		word_rcvd <=0;
	end
	else 
	begin
		// if the first data words  has been received 
		byte_rcvd <=(bitcnt == 4'b0111);
		//if the whole word has been received
		word_rcvd<=(bitcnt == 4'b1111);		
	end		
end





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
