/////////////////////////////////////////////////////////////////////////////////
// Company: <MINT NEURO>
//
// File: tb_TLM.v
// File history:
// v0.2 
//
// Description: 
//
// Test System top level module
//
// Targeted device: TSMC 65nm
// Author: Ian Williams
//
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/100ps

module tb_TLM;



//////////////////////////////////////////////////////////////////////
// Variables and parameters
//////////////////////////////////////////////////////////////////////

//{

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




parameter SYSCLK_PERIOD = 500; // 20MHz
//parameter SYSCLK_PERIOD = 250; // 4MHz
parameter SPICLK_PERIOD = 50; // 50MHz
//parameter SPICLK_PERIOD = 2000; // 0.5MHz
//parameter SPICLK_PERIOD = 3000; // 0.3MHz
parameter JITTER = 3;

//localparam PROCESS_DATA = 16'h2000;
parameter CMD_SIZE = 19;
parameter DATA_SIZE = 8192;

reg SYSCLK;
reg NRST;

reg CS, SCK;
reg [15:0]ADC_data;
wire POCI, PICO;

reg [15:0]data_send, data_rcv,data_rx, data_tx;
integer errors, i,j,l;
reg [15:0] memData [DATA_SIZE-1:0];
reg [15:0] memCmds[CMD_SIZE-1:0];

reg [13:0] rxData [DATA_SIZE-1:0];






//inputs
reg EXT_START,EXT_CTRL_EN, EXT_MUX_EN, EXT_ABUFFER_EN, EXT_AFE_NRST, EXT_ASETTLE_EN, EXT_GLOBAL_EN, EXT_START_CONV, EXT_ADC_START, EXT_OVERSAMPLE_EN,EXT_DIVERT1, EXT_DIVERT2, nsubsystemreset;
reg [3:0]EXT_CHAN_SEL;
reg READY, AVGENABLE;
reg [13:0] DOUT;


// reg TDI, TMS, TCK, TRST, scan_en, scan_clk, test_mode;


//outputs
wire  DATA_RDY;
wire MUX_en, buffer_en, adaptive_settle_en, adc_start, oversample_en, ip_ref_buffer_en, VMID1_en, VMID2_en,divert1, divert2;
wire [3:0] MUX_chan;
wire [15:0] reset_low, ch_enable;
wire [7:0] IDAC_DATA;
wire SAMPLE, ADCRST;

wire READY_avg, round_flag; //
// wire TDO;



reg [7:0] CONFIG [7:0];
integer offset; 


//}

//////////////////////////////////////////////////////////////////////
// Initial setup
//////////////////////////////////////////////////////////////////////

//{
integer idx;
initial
begin
   $dumpfile("test.vcd");
   $dumpvars(0,tb_TLM);
   
   // for (idx = 0; idx < NREGISTERS; idx = idx + 1) $dumpvars(0, tlm0.cI.configReg[idx]);
   // for (idx = 0; idx < NUMCHANNELS; idx = idx + 1) $dumpvars(0, tlm0.sC.ADCReg[idx]);
   
end
//}

//////////////////////////////////////////////////////////////////////
// Initial setup
//////////////////////////////////////////////////////////////////////

//{
initial
begin
    SYSCLK = 1'b0;
    NRST = 1'b1;
	errors =0;
	offset=0;
	
	
	
	//$readmemh("cmds.txt",memCmds);
	$readmemh("data.txt",memData);
	//$readmemh("expected.txt",memExpect);
	
end
//}

//////////////////////////////////////////////////////////////////////
// NRST Pulse
//////////////////////////////////////////////////////////////////////

//{
initial
begin
    #(SYSCLK_PERIOD * 3 )
        NRST = 1'b0;
    #(SYSCLK_PERIOD * 10 )
        NRST = 1'b1;
end
//}

//////////////////////////////////////////////////////////////////////
// Clock Driver
//////////////////////////////////////////////////////////////////////

//{
always @(SYSCLK)
    #(SYSCLK_PERIOD / 2.0) SYSCLK <= !SYSCLK;
//}




/////////////////////////////////////////////////////////////////////
//  Assignments
/////////////////////////////////////////////////////////////////////

//{
assign PICO = data_send[15]; 

//}

/////////////////////////////////////////////////////////////////////
//  Tasks
/////////////////////////////////////////////////////////////////////

//{
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
	SCK =0;
	#(SPICLK_PERIOD / 2.0 + $random %(JITTER));
    data_tx = data_send;
    repeat (15)
    begin
        SCK =1;
        data_rcv = {data_rcv[14:0],POCI}; // read on rising edge
        #(SPICLK_PERIOD / 2.0 + $random %(JITTER));
        SCK =0;
        data_send = data_send <<1; //transition on falling edge
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
	//#($random %(50 * SPICLK_PERIOD));
end
endtask

task spix2();
begin

	spi_pre;
	spi_word;
	spi_word;
	spi_post;
	//#($random %(50 * SPICLK_PERIOD));
end
endtask

task verify_output_word(input reg [15:0] simulated_value, input reg [15:0] expected_value);
begin

    if (simulated_value !== expected_value)
        begin
            errors = errors+1;
            $display("Simulated value = %h, Expected value = %h, errors = %d, at time = %t", simulated_value, expected_value, errors,$time); 
        end
		if (errors >20) $stop;
end

endtask

task verify_output_byte(input reg [15:0] simulated_value, input reg [15:0] expected_value);
begin

    if (simulated_value !== expected_value)
        begin
            errors = errors+1;
            $display("Simulated value = %h, Expected value = %h, errors = %d, at time = %t", simulated_value, expected_value, errors,$time); 
        end
end
endtask

 
task writeConfig();
begin
	$display("Writing config at time = %t",$time);
	for (b=0; b<8; b=b+1)
	begin
		data_send = {SPI_WRREG, b[2:0], CONFIG[b]};
		spi;
	end
end
endtask 


task checkConfig();
begin
	$display("Reading config at time = %t",$time);
	data_send = {SPI_RDREG,3'b0, 8'b0};
	spix2;
	verify_output_word(data_rcv, {SPI_REGDATA, 3'b0, 8'h01}); 
	for (b=1; b<8; b=b+1)
	begin
		data_send = {SPI_RDREG,b[2:0], 8'b0};
		spix2;
		verify_output_word(data_rcv, {SPI_REGDATA, b[2:0], CONFIG[b]}); 
	end
end
endtask 


// Mock ADC
reg [5:0] count;
reg running;
always @(posedge SYSCLK or negedge NRST)
begin
	if (!NRST) 
	begin 
		READY <=0;
		a<=0;
		DOUT <=0;
		count <=0;
		running <=0;
	end
	else 
	begin
		if (SAMPLE) running <=1;
		else 
		begin
			if (running)
			begin
				count <= count +1;
				if (count == 20)
				begin
					DOUT <= memData[a][13:0];
					a <= a+1;
					running <=0; 
					READY <=1;
				end
			end 
			else
			begin
				READY<=0;
				count <=0;
			end
		end
	end
	

end


wire [15:0] channels_en;
reg [15:0]expected_value ;
reg [4:0] nSetBits;
integer avg; 
integer sum;
integer rounding;

assign channels_en = {CONFIG[1], CONFIG[2]};
task readADCdata ();
begin
	
	data_send = {SPI_READDATA,11'b0};
	spi_pre;
	spi_word;
	
	for (d=0; d<16; d=d+1)
		begin
			spi_word;
			if (!channels_en[d]) 
			begin
				expected_value = 16'h8000;
			end
			else if (CONFIG[5][6] == 1) //averaging enabled 
			begin
				sum=0; 
				for (avg=0; avg<16; avg=avg+1) 
				begin
					sum = sum +  memData[offset]  ;
					offset= offset +1;
				end
				rounding = (sum %16) < 8 ? 0: 1;
				expected_value = sum/16 + rounding;
			end
			else 
			begin
					expected_value =memData[offset];
					offset=offset+1;  
			end
			
			verify_output_word(data_rcv, expected_value); 
		end 
	

	spi_post; 
end
endtask


reg [3:0] ch_sel;
task readADCsingle();
begin
	
	for (d=0; d<16; d=d+1)
		begin
			ch_sel = d;
			data_send = {4'b1110,ch_sel,8'b0};
			spi_pre;
			spi_word;
			spi_word;
			spi_post;
			
			if (!channels_en[d]) 
			begin
				expected_value = 16'h8000;
			end
			else if (CONFIG[5][6] == 1) //averaging enabled 
			begin
				sum=0; 
				for (avg=0; avg<16; avg=avg+1) 
				begin
					sum = sum +  memData[offset]  ;
					offset=offset+1;
				end
				rounding = (sum %16) < 8 ? 0: 1;
				expected_value = sum/16 + rounding;
			end
			else 
			begin
					expected_value =memData[offset];
					offset=offset+1;  
			end
			
			verify_output_word(data_rcv, expected_value); 
		end 
	

	spi_post; 
end
endtask




//}



/////////////////////////////////////////////////////////////////////
//  Main test sequence
/////////////////////////////////////////////////////////////////////

//{
integer o;
initial 
begin
    
    //SCK =0;
	SCK =1;
    CS = 1;
    data_send=0;	
	EXT_CTRL_EN=0;
	EXT_START=0; 
	EXT_MUX_EN=0; 
	EXT_ABUFFER_EN=0; 
	EXT_AFE_NRST=0; 
	EXT_ASETTLE_EN=0; 
	EXT_OVERSAMPLE_EN=0;
	EXT_GLOBAL_EN=0; 
	EXT_START_CONV=0; 
	EXT_ADC_START=0; 
	EXT_CHAN_SEL =0;
	EXT_DIVERT1 =0;
	EXT_DIVERT2 =0;
	nsubsystemreset=1;
	READY =0;
	DOUT =0;
	AVGENABLE=0;
	o=0;
	// TDI = 0;
	// TMS = 0;
	// TCK = 0;
	// TRST = 0;
	// scan_en = 0;
	// scan_clk = 0;
	// test_mode = 0;
	
	
    #(50 * SYSCLK_PERIOD);
    

/////////////////////////////////////////////////////////
//// Send in some spi commmands
/////////////////////////////////////////////////////////

	CONFIG[0]=8'hFF;
	CONFIG[1]=8'h02;
	CONFIG[2]=8'hff;
	CONFIG[3]=8'h01;
	CONFIG[4]=8'h02;
	CONFIG[5]=8'ha4;
	CONFIG[6]=8'h01;
	CONFIG[7]=8'h03;

	writeConfig;
	checkConfig;
	
	$display("Start conversion at time = %t",$time);
	data_send = {SPI_STARTCONV,11'b0};
	spi;
	verify_output_word(data_rcv, SPI_ACK);

	
	$display("Reading data at time = %t",$time);
	data_send = {SPI_READDATA,11'b0};
	spi;
	verify_output_word(data_rcv, SPI_ERR); 
	#(3 * SYSCLK_PERIOD);
	while (!DATA_RDY) #10;

	readADCdata;

	
	for (o=0; o<10; o=o+1)
	begin
		#(50*SYSCLK_PERIOD);
		data_send = {SPI_STARTCONV,11'b0};
		spi;
		verify_output_word(data_rcv, SPI_ACK);
		#(3 * SYSCLK_PERIOD);
		while (!DATA_RDY) #10;

		readADCdata; 
	end


	$display("simulate other spi activity on the bus without CS going low at time = %t",$time);
	for (o=0; o<10; o=o+1)
	begin
		#(50*SYSCLK_PERIOD);
		spi_word;
	end

	$display("Enables channels 15:8 at time = %t",$time);
	CONFIG[1]=8'hff; // Enables channels 15:8
	$display("Enable averaging at time = %t",$time);
	CONFIG[5][6]=1;//Enables averaging
	$display("Change sample and startup delays at time = %t",$time);
	CONFIG[7]=8'hf0; //Changes sample and startup delays
	writeConfig;
	checkConfig;

	for (o=0; o<10; o=o+1)
	begin
		#(50*SYSCLK_PERIOD);
		data_send = {SPI_STARTCONV,11'b0};
		spi;
		verify_output_word(data_rcv, SPI_ACK);
		#(3 * SYSCLK_PERIOD);
		while (!DATA_RDY) #(10 * SYSCLK_PERIOD);

		readADCdata; 
	end
	
	$display("Disable averaging at time = %t",$time);
	CONFIG[5][6]=0;//Disables averaging
	writeConfig;
	checkConfig;
	#(50 * SYSCLK_PERIOD);
	
	for (o=0; o<10; o=o+1)
	begin
		#(50*SYSCLK_PERIOD);
		data_send = {SPI_STARTCONV,11'b0};
		spi;
		verify_output_word(data_rcv, SPI_ACK);
		#(3 * SYSCLK_PERIOD);
		while (!DATA_RDY) #(10 * SYSCLK_PERIOD);

		readADCdata; 
	end
	
	#(50 * SYSCLK_PERIOD);
	
	$display("External start at time = %t",$time);
	for (o=0; o<10; o=o+1)
	begin
		#(50*SYSCLK_PERIOD);
		EXT_START_CONV = 1;
		#(3 * SYSCLK_PERIOD);
		EXT_START_CONV = 0;
		#(3 * SYSCLK_PERIOD);
		while (!DATA_RDY) #(10 * SYSCLK_PERIOD);

		readADCdata; 
	end
	
	$display("External start and readout single at time = %t",$time);
	for (o=0; o<10; o=o+1)
	begin
		#(50*SYSCLK_PERIOD);
		EXT_START_CONV = 1;
		#(3 * SYSCLK_PERIOD);
		EXT_START_CONV = 0;
		#(3 * SYSCLK_PERIOD);
		while (!DATA_RDY) #(10 * SYSCLK_PERIOD);

		readADCsingle; 
	end
	

	
	$stop;
	//$finish;

end


//}




	
//}



//////////////////////////////////////////////////////////////////////
// Instantiate Unit Under Test:  TLM
//////////////////////////////////////////////////////////////////////

TLM tlm0(
//inputs
.NRST(NRST),  //pull high !!!!!!!
.SCK(SCK),  //pull low
.PICO(PICO),  //pull low
.CS(CS),  //pull high !!!!!!!
.CLK(SYSCLK),
.EXT_ADC_START(EXT_ADC_START), 
.EXT_START_CONV(EXT_START_CONV),  // pull low
.EXT_CTRL_EN(EXT_CTRL_EN),  //pull low
.EXT_MUX_EN(EXT_MUX_EN),  //pull low
.EXT_CHAN_SEL(EXT_CHAN_SEL),  //pull low
.EXT_ABUFFER_EN(EXT_ABUFFER_EN),  //pull low
.EXT_AFE_NRST(EXT_AFE_NRST),  //pull high !!!!!!!
.EXT_ASETTLE_EN(EXT_ASETTLE_EN),  //pull low
.EXT_GLOBAL_EN(EXT_GLOBAL_EN),  //pull low
.EXT_OVERSAMPLE_EN(EXT_OVERSAMPLE_EN),  //pull low
.READY(READY), 
.DOUT(DOUT), 
.EXT_DIVERT1(EXT_DIVERT1),
.EXT_DIVERT2(EXT_DIVERT2),
//outputs
.POCI(POCI), 
.DATA_RDY(DATA_RDY), 
.MUX_en(MUX_en), 
.MUX_chan(MUX_chan),  
.buffer_en(buffer_en), 
.reset_low(reset_low),  
.ch_enable(ch_enable), 
.adaptive_settle_en(adaptive_settle_en),  
.IDAC_DATA(IDAC_DATA), 
.ip_ref_buffer_en(ip_ref_buffer_en),
.VMID1_en(VMID1_en),
.VMID2_en(VMID2_en),
.divert1(divert1),
.divert2(divert2),
// .TDI(TDI), 
// .TMS(TMS), 
// .TCK(TCK), 
// .TRST(TRST), 
// .TDO(TDO),
// .scan_en(scan_en), 
// .scan_clk(scan_clk), 
// .test_mode(test_mode),
// .nsubsystemreset(nsubsystemreset),
.SAMPLE(SAMPLE), 
.ADCRST(ADCRST)
);


endmodule



