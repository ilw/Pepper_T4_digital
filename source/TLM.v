`timescale 1ns / 1ps

module TLM (
    // Digital I/O
    input wire RESETN,
    input wire MOSI,
    input wire SCK,
    input wire CS,
    input wire HF_CLK,
    
    // Scan Chain
    input wire SCANEN,
    input wire SCANMODE,
    
    // SPI Output
    output wire MISO,
    output wire OEN,

    // GPIO Output
    output wire DATA_RDY,
    output wire INT,

    // Analog Inputs
    input wire [15:0] RESULT,
    input wire DONE,
    input wire ADCOVERFLOW,
    input wire [7:0] SATDETECT,
    
    // Analog Outputs (Control Signals)
    // CREF Section
    output wire ENREGAFE,
    output wire ENREGADC,
    output wire PDREGDIG,
    output wire [3:0] RTGB,
    output wire [3:0] RTREGAFE,
    output wire [3:0] RTREGADC,
    output wire [3:0] RETREGDIG,
    
    // AFE Section
    output wire ENAFELNA,
    output wire ENAFELPF,
    output wire ENAFEBUF,
    output wire SENSEMODE,
    output wire ENREFBUF,
    output wire REFMODE,
    output wire AFELPFBYP,
    output wire [7:0] AFERSTCH,
    output wire AFEBUFRST,
    output wire [1:0] AFEBUFGT,
    output wire ENMONTSENSE,
    output wire ENLNAOUT,
    output wire ENLPFOUT,
    output wire ENMONAFE,
    output wire [7:0] AFELPFBW, 
    output wire [7:0] CHSEL,
    output wire ENLOWPWR,
    output wire [7:0] CHEN,
    
    // BIAS Section
    output wire ENBIAS,
    output wire ENTSENSE,
    output wire ENITEST,
    output wire [3:0] RTBGBIAS,
    output wire [3:0] ITAFELNACH0,
    output wire [3:0] ITAFELNACH1,
    output wire [3:0] ITAFELNACH2,
    output wire [3:0] ITAFELNACH3,
    output wire [3:0] ITAFELNACH4,
    output wire [3:0] ITAFELNACH5,
    output wire [3:0] ITAFELNACH6,
    output wire [3:0] ITAFELNACH7,
    output wire [3:0] ITAFELPFCH0,
    output wire [3:0] ITAFELPFCH1,
    output wire [3:0] ITAFELPFCH2,
    output wire [3:0] ITAFELPFCH3,
    output wire [3:0] ITAFELPFCH4,
    output wire [3:0] ITAFELPFCH5,
    output wire [3:0] ITAFELPFCH6,
    output wire [3:0] ITAFELPFCH7,
    output wire [3:0] ITAFEBUF,
    output wire [3:0] ITADC,
    
    // ADC Section
    output wire ENADCANALOG,
    output wire ENMES,
    output wire ENCHP,
    output wire ENDWA,
    output wire [3:0] ADCOSR,
    output wire [3:0] ADCGAIN,
    output wire ENEXTCLK,
    output wire DONEOVERRIDE,
    output wire DONEOVERRIDEVAL,
    output wire ANARSTOVERRIDE,
    output wire ANARSTOVERRIDEVAL,
    output wire [2:0] DIGDEBUGSEL,
    output wire [2:0] ANATESTSEL,
    output wire SAMPLE_CLK,
    output wire nARST,
    
    // ATM Section
    output wire ENATMIN,
    output wire ENATMOUT,
    output wire ENATMLNA,
    output wire ENATMLPF,
    output wire ENATMBUF,
    output wire ENTESTADC,
    output wire ATMBUFBYP,
    output wire [2:0] ATMMODE,
    output wire [7:0] ATMCHSEL,
    

    // Raw register outputs (0x00 - 0x23)
    // Only expose bits that are NOT already broken out as named outputs from `cfg_data`.
    // For split registers, the port range matches the original bit positions.
    output wire [7:3] REG_00,
    output wire [7:0] REG_03,
    output wire [7:3] REG_04,
    output wire [7:4] REG_0E,
    output wire [7:0] REG_0F,
    output wire [7:0] REG_10,
    output wire [7:7] REG_11,
    output wire [7:7] REG_13,
    output wire [7:1] REG_15,
    output wire [7:0] REG_17,
    output wire [7:7] REG_18,
    output wire [7:3] REG_19,
    output wire [7:0] REG_1A,
    output wire [7:7] REG_1D,
    output wire [7:0] REG_1E,
    output wire [7:0] REG_1F,
    output wire [7:0] REG_20,
    output wire [7:0] REG_21,
    output wire [7:0] REG_22,
    output wire [7:0] REG_23
);
    
    // Internal Wires
    
    // SPI Wires
    wire spi_byte_rcvd;
    wire spi_word_rcvd;
    wire [7:0] spi_cmd_byte;
    wire [7:0] spi_data_byte;
    
    // Command Interpreter Wires
    wire [5:0] cim_reg_addr;
    wire [7:0] cim_reg_value;
    wire [15:0] cim_tx_buff;
    wire cim_fifo_pop;
    wire cim_wr_en;

    // Status clear bridge wires
    wire status_clr_req_tgl;
    wire [7:0] status_clr_lo;
    wire [5:0] status_clr_hi;
    wire status_clr_ack_tgl;
    wire status_clr_pulse_hf;
    wire [13:0] status_clr_mask_hf;
    
    // Configuration Registers Wires
    wire [511:0] cfg_data; // 64 registers x 8 bits = 512 bits (packed array) 
    
    // CDC Sync Wires
    wire nrst_sync;
    wire ensamp_sync;
    wire [7:0] aferstch_sync;
    wire fifo_overflow_sync;
    wire fifo_underflow_sync;
    wire [7:0] satdetect_sync;
    wire [11:0] phase1div1_sync;
    wire [3:0] phase1count_sync;
    wire [9:0] phase2count_sync;
    wire [7:0]chen_sync; 
    wire enlowpwr_sync;
    wire enmontsense_sync;
    wire adcoverflow_sync;
    wire [3:0] adcosr_sync;

    // Effective sampling enable: only run sampling path if at least one channel enabled
    wire any_chan_en = |chen_sync;
    wire ensamp_active = ensamp_sync & any_chan_en;
    
    // CRC Wires
    wire [15:0] crccfg;
    
    // FIFO Wires
    wire data_rdy;
    wire fifo_overflow;
    wire [4:0] fifo_watermark_in; // Control signal from Regs
    wire [127:0] fifo_adc_data; // 8 words of 16 bits (packed array)
    wire fifo_underflow;
    
    // Status Monitor Wires
    wire [13:0] status_mon_out;
    
    // Temp-sense run (gates ADC + SAMPLE_CLK in temp mode)
    wire temp_run;

    // Qualified ADC DONE (startup DONE swallowed)
    wire DONE_QUAL;
    
    // ATM Control Wires
    wire [7:0] atm_control_atmchsel;      // Mux selection (switches at prediction time)
    wire [7:0] atm_control_atmchsel_data; // 1-cycle delayed (aligned with DONE, for FIFO)
    wire lastword;

    // Temperature Buffer Wires
    wire [15:0] tempval;
    
    // Internal signals from Regs
    wire [7:0] reg_phase1div1;
    wire [3:0] reg_phase1div2;
    wire [3:0] reg_phase1count;
    wire [7:0] reg_phase2count1;
    wire [1:0] reg_phase2count2;
    wire reg_ensamp;
    wire [3:0] reg_fifowatermark;
    
    // -------------------------------------------------------------------------
    // 1. SPI
    // -------------------------------------------------------------------------
    // spiCore uses PICO/POCI internally; connect MOSI/MISO here.
    spiCore u_spi (
        .NRST(RESETN),
        .SCK(SCK),
        .PICO(MOSI),
        .CS(CS),
        .tx_buff(cim_tx_buff), // Connects to Command Interpreter's tx_buff logic
        .byte_rcvd(spi_byte_rcvd),
        .word_rcvd(spi_word_rcvd),
        .POCI(MISO),
        .cmd_byte(spi_cmd_byte),
        .data_byte(spi_data_byte)
    );
    
    // -------------------------------------------------------------------------
    // 2. Command Interpreter
    // -------------------------------------------------------------------------
    Command_Interpreter u_cim (
        .NRST(RESETN),
        .CS(CS),
        .SCK(SCK),
        .byte_rcvd(spi_byte_rcvd),
        .word_rcvd(spi_word_rcvd),
        .cmd_byte(spi_cmd_byte),
        .data_byte(spi_data_byte),
        .ADC_data(fifo_adc_data), // From FIFO
        .status(status_mon_out),
        .cfg_data(cfg_data),
        .ENSAMP_sync(ensamp_sync),
        .TEMPVAL(tempval),
     
        .reg_addr(cim_reg_addr), // Renamed from .reg (keyword)
        .reg_value(cim_reg_value),
        .tx_buff(cim_tx_buff),

        .status_clr_req_tgl(status_clr_req_tgl),
        .status_clr_lo(status_clr_lo),
        .status_clr_hi(status_clr_hi),
        .status_clr_ack_tgl(status_clr_ack_tgl),
        .FIFO_POP(cim_fifo_pop),
        .wr_en(cim_wr_en)
    );
    
    // -------------------------------------------------------------------------
    // 3. Configuration Registers
    // -------------------------------------------------------------------------
    Configuration_Registers u_cfg_regs (
        .NRST(RESETN),
        .SCK(SCK),
        .reg_addr(cim_reg_addr), // Renamed from .reg (keyword)
        .reg_value(cim_reg_value),  
        .wr_en(cim_wr_en),
        
        .cfg_data(cfg_data)
    );
    
    // Configuration Register Unpacking / Breakout
    // Raw register outputs (0x00 - 0x23)
    assign REG_00 = cfg_data[7:0];
    assign REG_01 = cfg_data[15:8];
    assign REG_02 = cfg_data[23:16];
    assign REG_03 = cfg_data[31:24];
    assign REG_04 = cfg_data[39:32];
    assign REG_05 = cfg_data[47:40];
    assign REG_06 = cfg_data[55:48];
    assign REG_07 = cfg_data[63:56];
    assign REG_08 = cfg_data[71:64];
    assign REG_09 = cfg_data[79:72];
    assign REG_0A = cfg_data[87:80];
    assign REG_0B = cfg_data[95:88];
    assign REG_0C = cfg_data[103:96];
    assign REG_0D = cfg_data[111:104];
    assign REG_0E = cfg_data[119:112];
    assign REG_0F = cfg_data[127:120];
    assign REG_10 = cfg_data[135:128];
    assign REG_11 = cfg_data[143:136];
    assign REG_12 = cfg_data[151:144];
    assign REG_13 = cfg_data[159:152];
    assign REG_14 = cfg_data[167:160];
    assign REG_15 = cfg_data[175:168];
    assign REG_16 = cfg_data[183:176];
    assign REG_17 = cfg_data[191:184];
    assign REG_18 = cfg_data[199:192];
    assign REG_19 = cfg_data[207:200];
    assign REG_1A = cfg_data[215:208];
    assign REG_1B = cfg_data[223:216];
    assign REG_1C = cfg_data[231:224];
    assign REG_1D = cfg_data[239:232];
    assign REG_1E = cfg_data[247:240];
    assign REG_1F = cfg_data[255:248];
    assign REG_20 = cfg_data[263:256];
    assign REG_21 = cfg_data[271:264];
    assign REG_22 = cfg_data[279:272];
    assign REG_23 = cfg_data[287:280];

    // 0x00
    assign ENREGAFE   = cfg_data[0];
    assign ENREGADC   = cfg_data[1];
    assign PDREGDIG   = cfg_data[2];
    // 0x01
    assign RTGB       = cfg_data[11:8];
    assign RTREGAFE   = cfg_data[15:12];
    // 0x02
    assign RTREGADC   = cfg_data[19:16];
    assign RETREGDIG  = cfg_data[23:20];
    // 0x04
    assign ENBIAS     = cfg_data[32];
    assign ENTSENSE   = cfg_data[33];
    assign ENITEST    = cfg_data[34];
    // 0x05
    assign RTBGBIAS   = cfg_data[43:40];
    assign ITAFELNACH0 = cfg_data[47:44];
    // 0x06
    assign ITAFELNACH1 = cfg_data[51:48];
    assign ITAFELNACH2 = cfg_data[55:52];
    // 0x07
    assign ITAFELNACH3 = cfg_data[59:56];
    assign ITAFELNACH4 = cfg_data[63:60];
    // 0x08
    assign ITAFELNACH5 = cfg_data[67:64];
    assign ITAFELNACH6 = cfg_data[71:68];
    // 0x09
    assign ITAFELNACH7 = cfg_data[75:72];
    assign ITAFELPFCH0 = cfg_data[79:76];
    // 0x0A
    assign ITAFELPFCH1 = cfg_data[83:80];
    assign ITAFELPFCH2 = cfg_data[87:84];
    // 0x0B
    assign ITAFELPFCH3 = cfg_data[91:88];
    assign ITAFELPFCH4 = cfg_data[95:92];
    // 0x0C
    assign ITAFELPFCH5 = cfg_data[99:96];
    assign ITAFELPFCH6 = cfg_data[103:100];
    // 0x0D
    assign ITAFELPFCH7 = cfg_data[107:104];
    assign ITAFEBUF    = cfg_data[111:108];
    // 0x0E
    assign ITADC       = cfg_data[115:112];
    
    // 0x11
    assign ENAFELNA   = cfg_data[136];
    assign ENAFELPF   = cfg_data[137];
    assign ENAFEBUF   = cfg_data[138];
    assign SENSEMODE  = cfg_data[139];
    assign ENREFBUF   = cfg_data[140];
    assign REFMODE    = cfg_data[141];
    assign AFELPFBYP  = cfg_data[142];
    // 0x12
    assign AFERSTCH   = cfg_data[151:144];
    // 0x13
    assign AFEBUFRST  = cfg_data[152];
    assign AFEBUFGT   = cfg_data[154:153];
    assign ENMONTSENSE = cfg_data[155];
    assign ENLNAOUT   = cfg_data[156];
    assign ENLPFOUT   = cfg_data[157];
    assign ENMONAFE   = cfg_data[158];
    // 0x14
    assign AFELPFBW   = cfg_data[167:160];
    // 0x15
    assign ENLOWPWR   = cfg_data[168];
    // 0x16
    assign CHEN      = cfg_data[183:176]; // Port Output
        
    // 0x18
    assign ENATMIN    = cfg_data[192];
    assign ENATMOUT   = cfg_data[193];
    assign ENATMLNA   = cfg_data[194];
    assign ENATMLPF   = cfg_data[195];
    assign ENATMBUF   = cfg_data[196];
    assign ENTESTADC  = cfg_data[197];
    assign ATMBUFBYP  = cfg_data[198];
    // 0x19
    assign ATMMODE    = cfg_data[202:200];
    
    // 0x1B
    assign ENADCANALOG = cfg_data[216];
    assign ENMES       = cfg_data[217];
    assign ENCHP       = cfg_data[218];
    assign ENDWA       = cfg_data[219];
    assign ADCOSR      = cfg_data[223:220];
    // 0x1C
    assign ADCGAIN          = cfg_data[227:224];
    assign ENEXTCLK         = cfg_data[228];
    assign DONEOVERRIDE     = cfg_data[229];
    assign DONEOVERRIDEVAL  = cfg_data[230];
    assign ANARSTOVERRIDE   = cfg_data[231];
    // 0x1D
    assign ANARSTOVERRIDEVAL = cfg_data[232];
    assign DIGDEBUGSEL      = cfg_data[235:233];
    assign ANATESTSEL       = cfg_data[238:236];
    
    // 0x20
    assign reg_phase1div1   = cfg_data[263:256];
    // 0x21
    assign reg_phase1div2   = cfg_data[267:264]; // Where do I use this? Maybe concatenation?
                                                  // Diagram shows PHASE1DIV1[11:0] going to CDC.
                                                  // So {phase1div2, phase1div1} maybe?
    assign reg_phase1count  = cfg_data[271:268];
    
    // 0x22
    assign reg_phase2count1 = cfg_data[279:272];
    
    // 0x23
    assign reg_phase2count2 = cfg_data[281:280]; 
    assign reg_fifowatermark= cfg_data[285:282];
    assign reg_forcewren    = cfg_data[286];
    assign reg_ensamp       = cfg_data[287];

    assign fifo_watermark_in = {1'b0, reg_fifowatermark}; // 5 bits required by FIFO, reg has 4? block_ios says 4, diagram says 4:0. Mapping 4 bits.
    
    // Construct Combined Signals for CDC
    wire [11:0] phase1div1_combined = {reg_phase1div2, reg_phase1div1};
    wire [9:0] phase2count_combined = {reg_phase2count2, reg_phase2count1};
    
    // -------------------------------------------------------------------------
    // 4. Register CRC
    // -------------------------------------------------------------------------
`ifdef ENABLE_REGISTER_CRC
    Register_CRC u_reg_crc (
        .cfg_data(cfg_data),
        .CRCCFG(crccfg)
    );
`else
    // Default when CRC block is cut: tie to constant.
    assign crccfg = 16'h0000;
`endif
    
    // -------------------------------------------------------------------------
    // 5. CDC Sync
    // -------------------------------------------------------------------------
    // "CFG_CHNGE" is likely a pulse generated when registers change. 
    // Usually Config Registers block would output this. 
    // Assuming '0' for now or need to check if Config Registers has this port. 
    // The diagram shows it entering CDC. I'll add a placeholder or assume it's derived.
    wire cfg_chnge = 1'b0; // Placeholder
    
    CDC_sync u_cdc_sync (
        .NRST(RESETN),
        .ENSAMP(reg_ensamp),
        .CFG_CHNGE(cfg_chnge),
        .AFERSTCH(AFERSTCH), // From Regs
        .FIFO_OVERFLOW(fifo_overflow),
        .FIFO_UNDERFLOW(fifo_underflow),
        .SATDETECT(SATDETECT),
        .ADCOVERFLOW(ADCOVERFLOW),
        .PHASE1DIV1(phase1div1_combined),
        .PHASE1COUNT(reg_phase1count),
        .PHASE2COUNT(phase2count_combined),
        .CHEN(CHEN), // "select sensing channel" from Regs 0x16
        .ENLOWPWR(ENLOWPWR),
        .ENMONTSENSE(ENMONTSENSE),
        .ADCOSR(ADCOSR),
        .HF_CLK(HF_CLK),
        
        // Outputs
        .NRST_sync(nrst_sync),
        .ENSAMP_sync(ensamp_sync),
        .CFG_CHNGE_sync(),
        .AFERSTCH_sync(aferstch_sync),
        .FIFO_OVERFLOW_sync(fifo_overflow_sync),
        .FIFO_UNDERFLOW_sync(fifo_underflow_sync),
        .SATDETECT_sync(satdetect_sync),
        .ADCOVERFLOW_sync(adcoverflow_sync),
        .PHASE1DIV1_sync(phase1div1_sync),
        .PHASE1COUNT_sync(phase1count_sync),
        .PHASE2COUNT_sync(phase2count_sync),
        .CHEN_sync(chen_sync),
        .ENLOWPWR_sync(enlowpwr_sync),
        .ENMONTSENSE_sync(enmontsense_sync),
        .ADCOSR_sync(adcosr_sync)
    );

    // Bridge status clear requests from SCK to HF_CLK domain
    Status_Clear_CDC u_status_clr_cdc (
        .HF_CLK(HF_CLK),
        .NRST_sync(nrst_sync),
        .status_clr_req_tgl_sck(status_clr_req_tgl),
        .status_clr_lo_sck(status_clr_lo),
        .status_clr_hi_sck(status_clr_hi),
        .status_clr_ack_tgl_hf(status_clr_ack_tgl),
        .status_clr_pulse(status_clr_pulse_hf),
        .status_clr_mask(status_clr_mask_hf)
    );
    
    // -------------------------------------------------------------------------
    // 6. Dual phase gated burst divider
    // -------------------------------------------------------------------------
    Dual_phase_gated_burst_divider u_divider (
        .PHASE1DIV1_sync(phase1div1_sync),
        .PHASE1COUNT_sync(phase1count_sync),
        .PHASE2COUNT_sync(phase2count_sync),
        .HF_CLK(HF_CLK),
        .ENSAMP_sync(ensamp_active),
        .NRST_sync(nrst_sync),
        .TEMP_RUN(temp_run),
        
        .SAMPLE_CLK(SAMPLE_CLK),
        .phase()
    );

    // Temp-sense controller (one-shot run gate)
    TempSense_Control u_temp_ctrl (
        .HF_CLK(HF_CLK),
        .NRST_sync(nrst_sync),
        .ENMONTSENSE_sync(enmontsense_sync),
        .DONE(DONE_QUAL),
        .temp_run(temp_run)
    );

    // -------------------------------------------------------------------------
    // ADC DONE qualification: swallow the first DONE after ADC enable.
    //
    // The ns_sar_v2 decimator's state[5] is preset to 1 by async reset and
    // state[4:0] is cleared to 0 (the terminal count value).  This causes
    // completion_flag to fire on the very first SAMPLE_CLK edge after nARST
    // deasserts, producing an immediate CIC_DONE pulse with invalid data
    // (CIC integrators are still empty).  In SAR mode (OSR=0) DONE is always
    // high, so the first cycle is also meaningless.
    //
    // DONE_QUAL suppresses this startup DONE: it stays low until we've
    // observed (and consumed) the first DONE while the ADC is enabled,
    // then follows DONE thereafter.  When nARST goes low the filter re-arms.
    // -------------------------------------------------------------------------
    reg discard_first_done;
    // IMPORTANT: SAMPLE_CLK is gated/stopped when nARST=0.
    // If we only re-arm discard_first_done synchronously to SAMPLE_CLK, we can miss the
    // nARST falling edge and accidentally carry discard_first_done=0 across disables.
    // That allows a startup DONE pulse to leak through on the next enable.
    //
    // Therefore we asynchronously re-arm on nARST falling.
    always @(posedge SAMPLE_CLK or negedge nrst_sync or negedge nARST) begin
        if (!nrst_sync) begin
            discard_first_done <= 1'b1;
        end else if (!nARST) begin
            discard_first_done <= 1'b1;
        end else begin
            // While enabled, clear the discard flag on the first observed DONE.
            if (discard_first_done && DONE) begin
                discard_first_done <= 1'b0;
            end
        end
    end
    // Gate DONE_QUAL to 0 when ADC is disabled (nARST=0) to prevent stale/glitch
    // DONE pulses from leaking through when SAMPLE_CLK is stopped/restarting.
    assign DONE_QUAL = DONE & ~discard_first_done & nARST;
    
    // -------------------------------------------------------------------------
    // 7. ATM Control
    // -------------------------------------------------------------------------
    ATM_Control u_atm_ctrl (
        .SAMPLE_CLK(SAMPLE_CLK),
        .ENSAMP_sync(ensamp_active),
        .CHEN_sync(chen_sync),
        .OSR_sync(adcosr_sync),
        .NRST_sync(nrst_sync),
        .ENLOWPWR_sync(enlowpwr_sync),
        
        .ATMCHSEL(atm_control_atmchsel),
        .ATMCHSEL_DATA(atm_control_atmchsel_data),
        .CHSEL(CHSEL), 
        .LASTWORD(lastword)
    );

    // NOTE:
    // `lastword` is generated by ATM_Control as a SAMPLE_CLK-domain registered signal.
    // When sampling is disabled, SAMPLE_CLK may be gated/stopped immediately; in that
    // case ATM_Control may not see another SAMPLE_CLK edge to clear `lastword_reg`.
    //
    // We therefore gate LASTWORD with `ensamp_sync` (HF_CLK-synchronized enable) so
    // downstream blocks never see a stale-high LASTWORD while the sampling path is
    // disabled.
    //
    // IMPORTANT: Do NOT gate with `ensamp_active` here, because `ensamp_active`
    // depends on `chen_sync` (a multi-bit bus that is intentionally not fully
    // synchronized for area reasons). Using `ensamp_sync` avoids introducing CDC
    // glitch sensitivity into the FIFO's frame-advance decision.
    wire lastword_gated = lastword & ensamp_sync;
    
    // Drive ATMCHSEL port
    // Hold mux select at 0 when not actively sampling or when no channels enabled
    assign ATMCHSEL = ensamp_active ? atm_control_atmchsel : 8'b0;

    
    // -------------------------------------------------------------------------
    // 8. FIFO
    // -------------------------------------------------------------------------
    FIFO #(
        .FRAME_DEPTH(4)
    ) u_fifo (
        .RESULT(RESULT),
        .DONE(DONE_QUAL),
        .SAMPLE_CLK(SAMPLE_CLK),
        .NRST_sync(nrst_sync),
        .ATMCHSEL(atm_control_atmchsel_data),  // Use delayed copy aligned with DONE
        .LASTWORD(lastword_gated),
        .FIFO_POP(cim_fifo_pop),
        .FIFOWATERMARK(fifo_watermark_in), // From Regs
        .SCK(SCK),
        .ENSAMP_sync(ensamp_active),

        
        .DATA_RDY(data_rdy),
        .FIFO_OVERFLOW(fifo_overflow),
        .ADC_data(fifo_adc_data),
        .FIFO_UNDERFLOW(fifo_underflow)
    );
    
    // -------------------------------------------------------------------------
    // 9. Status Monitor
    // -------------------------------------------------------------------------
    Status_Monitor u_stat_mon (
        .NRST_sync(nrst_sync),
        .HF_CLK(HF_CLK),
        .ENSAMP_sync(ensamp_active),
        .CRCCFG(crccfg),
        .AFERSTCH_sync(aferstch_sync),
        .FIFO_OVERFLOW_sync(fifo_overflow_sync),
        .FIFO_UNDERFLOW_sync(fifo_underflow_sync),
        .ADCOVERFLOW(adcoverflow_sync),
        .SATDETECT_sync(satdetect_sync),
        .status_clr_pulse(status_clr_pulse_hf),
        .status_clr_mask(status_clr_mask_hf),
        
        .status(status_mon_out)
    );

    // Interrupt is asserted if any status bit is high (excluding ENSAMP which is status[13])
    assign INT = |status_mon_out[12:0];

    // -------------------------------------------------------------------------
    // 10. Temperature Buffer
    // -------------------------------------------------------------------------
    Temperature_Buffer u_temp_buf (
        .ENMONTSENSE_sync(enmontsense_sync),
        .DONE(DONE_QUAL),
        .NRST_sync(nrst_sync),
        .SAMPLE_CLK(SAMPLE_CLK),
        .RESULT(RESULT),
        .TEMPVAL(tempval)
    );

    // ADC enable/start (nARST): enable during sampling, or during temp one-shot run
    // If no channels enabled, disable ADC + sampling path for clean behavior and power.
    assign nARST = ensamp_active | temp_run;

    // Drive top-level DATA_RDY from FIFO
    assign DATA_RDY = data_rdy;

    // Output enable for external bus: high when CS is deasserted and not in scan mode.
    assign OEN = CS & ~SCANMODE;



endmodule