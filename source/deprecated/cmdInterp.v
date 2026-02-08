/////////////////////////////////////////////////////////////////////////////////
// Company: <MINT NEURO>
//
// File: cmdInterp.v
// File history:
// v0.2     
//
// Description: 
//
// Command interpreter 
//
// Targeted device: TSMC 65nm
// Author: Ian Williams
//
/////////////////////////////////////////////////////////////////////////////


//`timescale 1ns/ 100ps
module cmdInterp(
//inputs
NRST, 
SCK, 
CS, 
byte_rcvd,
word_rcvd,
cmd_byte,
data_byte,
adc_data,
DATA_RDY,
//outputs
tx_buff,
start_conv,
reg_data,
nsubsystemreset
);



//`include "CONST.vh"

// Configurable variables
parameter NREGISTERS  =8;
parameter ADCBITDEPTH  =14;
parameter NUMCHANNELS  =16;
parameter REGISTERBITDEPTH  =8;

// SPI command bytes
parameter SPI_RDREG  =5'b00110;
parameter SPI_WRREG  =5'b11000;
parameter SPI_STARTCONV  =5'b10100;
parameter SPI_READDATA = 5'b01010;
parameter SPI_READDATASINGLE0 = 5'b11100;
parameter SPI_READDATASINGLE1 = 5'b11101;
parameter SPI_RESET = 5'b00001; 
parameter SPI_NULL = 16'h0;

// SPI responses
parameter SPI_ACK = 16'h3355 ;
parameter SPI_ERR = 16'hABCD ;
parameter SPI_REGDATA = 5'b11000;
parameter SPI_ADCDATA = 2'b10;
parameter SPI_CFGDATA = 5'b01000;






/////////////////////////////////////////////////////////////////////////////////
// VARIABLES
/////////////////////////////////////////////////////////////////////////////////
//{

// States - 1 hot encoded
localparam IDLE = 1;
localparam READREG = 2;
localparam WRITEREG = 4;
localparam CONVERTING = 8;
localparam READDATA = 16;
localparam READCONFIG = 32;
localparam READDATASINGLE = 64;
localparam RESETSUBSYSTEM = 128;


localparam NSTATES = 8;




//inputs
input NRST, SCK, CS, byte_rcvd, word_rcvd, DATA_RDY;
input [7:0] cmd_byte, data_byte;
input [ADCBITDEPTH*NUMCHANNELS-1:0] adc_data;
//outputs
output [15:0] tx_buff;
output start_conv;
output [REGISTERBITDEPTH*NREGISTERS-1:0] reg_data;
output  nsubsystemreset;

(* keep = 1 *) reg  [REGISTERBITDEPTH-1:0] configReg[NREGISTERS-1:0] /* cadence preserve_sequential */;
reg [NSTATES-1:0] nstate, state; 
reg [4:0] chanSelect;
wire [4:0] chanSelectPlus1;
wire allDataSent;
wire allConfigSent;
reg firstByte;


reg [1:0] data_ready_r; 
wire dataReadyRcvd;
wire [ADCBITDEPTH-1:0]adcDataIn [NUMCHANNELS-1:0];

//}







genvar i,j;
generate
	for (j=0; j<NREGISTERS; j=j+1)
	begin : jl
		for (i=0; i<REGISTERBITDEPTH; i=i+1)
		begin : il
			 assign reg_data[j*REGISTERBITDEPTH+i] = configReg[j][i];
		end	
	end
	
	for (j=0; j<NUMCHANNELS; j=j+1)
	begin : j2
		for (i=0; i<ADCBITDEPTH; i=i+1)
		begin : i2
			 assign adcDataIn[j][i] = adc_data[j*ADCBITDEPTH+i];
		end	
	end
	

endgenerate 






/////////////////////////////////
// State transitions (combinational)
///////////////////////////////////

//{
always @(*)
begin

	// if (firstByte) //If included these lines then only accept first command of each SPI transaction? (spi transaction = CS low), but causes issues for READDATA. 
	// begin
		case(state)

			IDLE: 
			begin
				if (byte_rcvd)
				begin
					case (cmd_byte[7:3])
						SPI_RDREG : nstate = READREG;
						SPI_WRREG  : nstate = WRITEREG;
						SPI_STARTCONV  : nstate = CONVERTING;
						SPI_READDATA  : nstate = firstByte ? READDATA : IDLE; //only accept read data command on the first word to avoid partial readout
						SPI_READDATASINGLE0 : nstate = READDATASINGLE; 
						SPI_READDATASINGLE1 : nstate = READDATASINGLE; 
						SPI_RESET : nstate = RESETSUBSYSTEM;
						default 		: nstate = IDLE;
					endcase
					
				end
				else nstate = IDLE;
			end
			READREG: 		nstate = (word_rcvd || firstByte) ? IDLE : READREG;
			WRITEREG:		nstate = (firstByte) ? IDLE : WRITEREG;
			CONVERTING:		nstate = dataReadyRcvd  ? IDLE : (byte_rcvd && cmd_byte[7:3] == SPI_RESET) ?  RESETSUBSYSTEM: CONVERTING;
			READDATA:		nstate = firstByte ? IDLE : allDataSent ? READCONFIG : READDATA;
			READCONFIG:		nstate = (firstByte || allConfigSent) ? IDLE :  READCONFIG;
			READDATASINGLE:	nstate = (word_rcvd || firstByte) ? IDLE : READDATASINGLE;
			RESETSUBSYSTEM: nstate = (word_rcvd || firstByte) ? IDLE : RESETSUBSYSTEM;
			default:		nstate = IDLE;
		endcase

end

//}

/////////////////////////////////////////////
//	State transition (sequential)
/////////////////////////////////////////////

//{
always @(posedge SCK or negedge NRST)
begin
	if (!NRST) state <= IDLE;
	else if (!CS) state <=nstate;
end
//}






/////////////////////////////////////////////
//	Support code
/////////////////////////////////////////////

//{
// detect whether its the first byte of an SPI transaction
//always @(negedge NRST or posedge SCK or posedge CS)
always @(posedge SCK or posedge CS) //changed by PF
begin
	if (CS) firstByte <=1;
	else if (byte_rcvd) firstByte <=0;
	else firstByte <= firstByte;
end



//Block synchronising data_ready_s to SPI clock
always @(posedge SCK or negedge NRST or posedge CS)
begin
	if (!NRST || CS) data_ready_r <=0;
	else data_ready_r <= {data_ready_r[0], DATA_RDY};
end
assign dataReadyRcvd = data_ready_r == 2'b01;



//Working through the channel ADC data
always @(posedge SCK or negedge NRST)
begin
	if (!NRST)
	begin
		chanSelect <=0;
	end
	else if ((state == READDATA) || (state == READCONFIG)) 
	begin
		if (word_rcvd)chanSelect <= (allConfigSent || chanSelect==5'b10101) ? 5'b10101: chanSelect + 1;
		else chanSelect <= chanSelect;
	end
	else chanSelect <=0;
end


assign allDataSent = (chanSelect == 5'b10000);
assign allConfigSent = (chanSelect == 5'b10101); 
assign chanSelectPlus1 = chanSelect+1;

//}





/////////////////////////////////////////////
//	State machine outputs - tx_buffer, start_conv,  config_reg, and nsubsystemreset
/////////////////////////////////////////////

//{
// TX buffer
assign tx_buff = f(state, chanSelect, chanSelectPlus1, firstByte);
function [15:0] f(input [NSTATES-1:0] st, input [4:0] c, input [4:0] cp1, input fb);

	case (st)
		IDLE: f = SPI_ACK;
		READREG: f = {SPI_REGDATA,cmd_byte[2:0],configReg[cmd_byte[2:0]]}; 
		WRITEREG: f = SPI_ACK;
		CONVERTING: f = SPI_ERR;
		READDATA: 	f = fb ? SPI_ACK : {SPI_ADCDATA,adcDataIn[c[3:0]]};
		//READDATA: 	f = {SPI_ADCDATA,10'b0101010110, c[3:0]};
		READCONFIG: f =  fb ? SPI_ACK : {SPI_CFGDATA ,cp1[2:0], configReg[cp1[2:0]]};
		READDATASINGLE: f = {SPI_ADCDATA,adcDataIn[cmd_byte[3:0]]};
		RESETSUBSYSTEM: f = SPI_ACK;
		default: f = SPI_ACK;
	endcase

endfunction



//start_conv
assign start_conv = (state==CONVERTING); 
assign nsubsystemreset = !(state == RESETSUBSYSTEM);

//configuration registers
always @(posedge CS or negedge NRST)
begin
	if (!NRST) 
	begin
		configReg[0] <=1;
		configReg[1] <=0;
		configReg[2] <=0;
		configReg[3] <=0;
		configReg[4] <=0;
		configReg[5] <=0;
		configReg[6] <=0;
		configReg[7] <=0;
	end
	else if (state == WRITEREG)
	begin
		// Don't write reg 0
		case (cmd_byte[2:0])
			0: configReg[0] <= 1;
			1: configReg[1] <= data_byte;
			2: configReg[2] <= data_byte;
			3: configReg[3] <= data_byte;
			4: configReg[4] <= data_byte;
			5: configReg[5] <= data_byte;
			6: configReg[6] <= data_byte;
			7: configReg[7] <= data_byte;
		default: ;
		endcase
	end
	else 
	begin
		configReg[0] <= 1;
		configReg[1] <= configReg[1];
		configReg[2] <= configReg[2];
		configReg[3] <= configReg[3];
		configReg[4] <= configReg[4];
		configReg[5] <= configReg[5];
		configReg[6] <= configReg[6];
		configReg[7] <= configReg[7];
	end
	
end






endmodule
