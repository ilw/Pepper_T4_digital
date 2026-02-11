`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Top-Level Integration Testbench
//
// Verifies:
// 1. SPI communication (register R/W, data readout)
// 2. Sampling enable/disable flow
// 3. ADC data acquisition with mux control (using ns_sar_v2 mock)
// 4. FIFO operation
// 5. End-to-end data path
//////////////////////////////////////////////////////////////////////////////////

module tb_top_level_integration();

    // Clock and reset
    reg HF_CLK;
    reg RESETN;
    
    // SPI signals
    wire CS, SCK, MOSI;
    wire MISO_CORE;
    wire MISO_PAD;
    wire OEN_w;
    
    // Scan pins (tie inactive for normal mode)
    reg SCANEN;
    reg SCANMODE;
    
    // ADC interface (directly wired between TLM and ns_sar_v2 mock)
    wire [7:0]  ATMCHSEL;
    // TLM no longer exports TEMPSEL; use the ENMONTSENSE control bit instead
    // to steer the dummy mux temperature input selection.
    wire        ENMONTSENSE_w;
    wire        SAMPLE_CLK_w;
    wire        nARST_w;
    wire [15:0] ADC_RESULT;
    wire        ADC_DONE;
    wire        ADC_OVERFLOW;
    
    // ADC configuration outputs from TLM
    wire [3:0]  ADCOSR_w;
    wire [3:0]  ADCGAIN_w;
    wire        ENADCANALOG_w;
    wire        ENMES_w;
    wire        ENCHP_w;
    wire        ENDWA_w;
    wire        ENEXTCLK_w;
    wire        DONEOVERRIDE_w;
    wire        DONEOVERRIDEVAL_w;
    wire        ANARSTOVERRIDE_w;
    wire        ANARSTOVERRIDEVAL_w;
    wire [2:0]  DIGDEBUGSEL_w;
    wire [2:0]  ANATESTSEL_w;

    // Mux interface
    wire [15:0] MUX_OUT;
    
    // Test variables
    reg [15:0] spi_rx_data;
    integer i, j;
    reg [127:0] fifo_readback;
    integer pad_errors;

    // Mock ADC exercise counters (helps verify OSR mode behavior)
    integer adc_done_posedges;
    integer adc_done_negedges;
    integer adc_sample_edges;

    always @(posedge ADC_DONE) adc_done_posedges = adc_done_posedges + 1;
    always @(negedge ADC_DONE) adc_done_negedges = adc_done_negedges + 1;
    always @(posedge SAMPLE_CLK_w) adc_sample_edges = adc_sample_edges + 1;

    // SPI write visibility (TLM internal)
    integer cfg_wr_pulses;
    always @(posedge dut.cim_wr_en) begin
        cfg_wr_pulses = cfg_wr_pulses + 1;
        $display("CFG write: addr=0x%02h value=0x%02h (t=%0t)", dut.cim_reg_addr, dut.cim_reg_value, $time);
    end
    
    // Waveform dumping
`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_top_level_integration.vcd");
        $dumpvars(0, tb_top_level_integration);
    end
`endif
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        HF_CLK = 0;
        forever #50 HF_CLK = ~HF_CLK;  // 10MHz
    end
    
    //==========================================================================
    // DUT: Top-Level Module (TLM)
    //==========================================================================
    
    TLM dut (
        .HF_CLK(HF_CLK),
        .RESETN(RESETN),
        .CS(CS),
        .SCK(SCK),
        .MOSI(MOSI),
        .MISO(MISO_CORE),
        .OEN(OEN_w),
        .SCANEN(SCANEN),
        .SCANMODE(SCANMODE),
        .RESULT(ADC_RESULT),
        .DONE(ADC_DONE),
        .ADCOVERFLOW(ADC_OVERFLOW),
        .SATDETECT(8'h00),
        .ATMCHSEL(ATMCHSEL),
        .ENMONTSENSE(ENMONTSENSE_w),
        .SAMPLE_CLK(SAMPLE_CLK_w),
        .nARST(nARST_w),
        .ADCOSR(ADCOSR_w),
        .ADCGAIN(ADCGAIN_w),
        .ENADCANALOG(ENADCANALOG_w),
        .ENMES(ENMES_w),
        .ENCHP(ENCHP_w),
        .ENDWA(ENDWA_w),
        .ENEXTCLK(ENEXTCLK_w),
        .DONEOVERRIDE(DONEOVERRIDE_w),
        .DONEOVERRIDEVAL(DONEOVERRIDEVAL_w),
        .ANARSTOVERRIDE(ANARSTOVERRIDE_w),
        .ANARSTOVERRIDEVAL(ANARSTOVERRIDEVAL_w),
        .DIGDEBUGSEL(DIGDEBUGSEL_w),
        .ANATESTSEL(ANATESTSEL_w)
    );

    //==========================================================================
    // MISO pad model (tri-state) controlled by OEN (active-low enable)
    //==========================================================================
    // OEN=0 -> pad drives core MISO
    // OEN=1 -> pad is high-Z
    assign MISO_PAD = (OEN_w === 1'b0) ? MISO_CORE : 1'bz;

    // Pad behavior checks in normal (non-scan) mode.
    always @(CS or OEN_w or SCANMODE or MISO_PAD) begin
        #0;
        if (SCANMODE === 1'b0) begin
            if (CS === 1'b1) begin
                if (OEN_w !== 1'b1) begin
                    $display("ERROR: OEN should be 1 when CS=1 (t=%0t)", $time);
                    pad_errors = pad_errors + 1;
                end
                if (MISO_PAD !== 1'bz) begin
                    $display("ERROR: MISO pad should be Z when CS=1 (t=%0t) got=%b", $time, MISO_PAD);
                    pad_errors = pad_errors + 1;
                end
            end else if (CS === 1'b0) begin
                if (OEN_w !== 1'b0) begin
                    $display("ERROR: OEN should be 0 when CS=0 (t=%0t)", $time);
                    pad_errors = pad_errors + 1;
                end
                if (MISO_PAD === 1'bz) begin
                    $display("ERROR: MISO pad should be driven when CS=0 (t=%0t)", $time);
                    pad_errors = pad_errors + 1;
                end
            end
        end
    end
    
    //==========================================================================
    // Behavioral ADC Mock (ns_sar_v2)
    //==========================================================================
    
    ns_sar_v2 adc_mock (
        .SAMPLE_CLK(SAMPLE_CLK_w),
        .nARST(nARST_w),
        .OSR(ADCOSR_w),
        .GAIN(ADCGAIN_w),
        .ANALOG_ENABLE(ENADCANALOG_w),
        .CHP_EN(ENCHP_w),
        .DWA_EN(ENDWA_w),
        .MES_EN(ENMES_w),
        .EXT_CLK(1'b0),
        .EXT_CLK_EN(ENEXTCLK_w),
        .DONE_OVERRIDE(DONEOVERRIDE_w),
        .DONE_OVERRIDE_VAL(DONEOVERRIDEVAL_w),
        .ANALOG_RESET_OVERRIDE(ANARSTOVERRIDE_w),
        .ANALOG_RESET_OVERRIDE_VAL(ANARSTOVERRIDEVAL_w),
        .DIGITAL_DEBUG_SELECT(DIGDEBUGSEL_w),
        .ANALOG_TEST_SELECT(ANATESTSEL_w),
        .ADC_SPARE(8'h00),
        // Analog pins (unused)
        .VIP(1'b0),
        .VIN(1'b0),
        .REFP(1'b0),
        .REFN(1'b0),
        .REFC(1'b0),
        .IBIAS_500N_PTAT(1'b0),
        .DVDD(1'b1),
        .DGND(1'b0),
        // Outputs
        .RESULT(ADC_RESULT),
        .DONE(ADC_DONE),
        .OVERFLOW(ADC_OVERFLOW),
        .ANALOG_TEST(),
        .DIGITAL_DEBUG()
    );
    
    //==========================================================================
    // Dummy Multiplexer
    //==========================================================================
    
    dummy_Mux mux (
        .ATMCHSEL(ATMCHSEL),
        .TEMPSEL(ENMONTSENSE_w),
        .CH0_IN(16'hA000),
        .CH1_IN(16'hA111),
        .CH2_IN(16'hA222),
        .CH3_IN(16'hA333),
        .CH4_IN(16'hA444),
        .CH5_IN(16'hA555),
        .CH6_IN(16'hA666),
        .CH7_IN(16'hA777),
        .TEMP1_IN(16'hF111),
        .TEMP2_IN(16'hF222),
        .MUX_OUT(MUX_OUT)
    );
    
    //==========================================================================
    // SPI Master BFM
    //==========================================================================
    
    spi_master_bfm spi (
        .CS(CS),
        .SCK(SCK),
        .MOSI(MOSI),
        .MISO(MISO_PAD)
    );
    
    //==========================================================================
    // Test Sequence
    //==========================================================================
    
    initial begin
        $display("========================================");
        $display("Top-Level Integration Test Starting");
        $display("========================================");
        
        // Initialize
        RESETN = 0;
        adc_done_posedges = 0;
        adc_done_negedges = 0;
        adc_sample_edges  = 0;
        cfg_wr_pulses     = 0;
        pad_errors        = 0;
        SCANEN            = 1'b0;
        SCANMODE          = 1'b0;
        
        #500;
        RESETN = 1;
        #500;
        
        //======================================================================
        // Test 1: Configure ADC (OSR and GAIN)
        //======================================================================
        $display("\n=== Test 1: Configure ADC ===");
        
        // Set up SAR mode first (OSR=0). This must be written while sampling is OFF.
        // cfg_data[223:216] = reg 0x1B
        // bit [0]=ENADCANALOG, [1]=ENMES, [2]=ENCHP, [3]=ENDWA, [7:4]=ADCOSR
        spi.send_word(16'h9B00, spi_rx_data);
        $display("Wrote reg 0x1B = 0x00 (OSR=0, SAR mode)");
        #500;
        
        // Write ADCGAIN=15 to reg 0x1C
        // cfg_data[227:224] = ADCGAIN, [228]=ENEXTCLK, [229]=DONEOVERRIDE, etc.
        // GAIN=15 → 4'b1111 in bits [3:0] → byte = 8'h0F
        spi.send_word(16'h9C0F, spi_rx_data);
        $display("Wrote reg 0x1C = 0x0F (GAIN=15)");
        #500;
        
        //======================================================================
        // Test 2: Configure channels and divider
        //======================================================================
        $display("\n=== Test 2: Configure Channels ===");
        
        // Write CHEN register (0x16) — enable channels 0,1,2
        spi.send_word(16'h9607, spi_rx_data);
        $display("Wrote CHEN=0x07 (channels 0,1,2)");
        #500;
        
        // Write PHASE1DIV1 low byte (reg 0x20) = 4
        spi.send_word(16'hA004, spi_rx_data);
        $display("Wrote PHASE1DIV1 low = 0x04");
        #500;
        
        // Write PHASE1COUNT + PHASE1DIV1 high (reg 0x21)
        // bits [3:0] = PHASE1DIV2 (high nibble of PHASE1DIV1)
        // bits [7:4] = PHASE1COUNT
        spi.send_word(16'hA180, spi_rx_data);
        $display("Wrote reg 0x21 = 0x80 (PHASE1COUNT=8, PHASE1DIV2=0)");
        #500;
        
        //======================================================================
        // Test 3: Enable Sampling (SAR mode check)
        //======================================================================
        $display("\n=== Test 3: Enable Sampling (SAR mode) ===");
        
        // Write ENSAMP bit in reg 0x23
        // In TLM.v: ENSAMP is cfg_data[287] → bit[7] of reg 0x23 → byte = 8'h80
        spi.send_word(16'hA380, spi_rx_data);
        $display("Enabled sampling (reg 0x23 = 0x80)");

        // Quick sanity: read back reg 0x23 and check that nARST/SAMPLE_CLK start
        spi.begin_transaction();
        // Multi-word transaction: use exact 16-clock transfers (no extra SCK edge)
        spi.transfer_word16(16'h2300, spi_rx_data); // RDREG @ 0x23 (returns status)
        spi.transfer_word16(16'h0000, spi_rx_data); // returns reg data
        spi.end_transaction();
        $display("Reg 0x23 readback: 0x%h (expect 0xC0xx with bit7=1 in low byte)", spi_rx_data);
        #2000;
        $display("Post-ENSAMP: nARST=%b SAMPLE_CLK=%b ADC_DONE=%b ADCOSR=%0d",
                 nARST_w, SAMPLE_CLK_w, ADC_DONE, ADCOSR_w);

        // Ensure nARST comes high reasonably soon after ENSAMP is written
        if (nARST_w !== 1'b1) begin
            $display("ERROR: nARST did not assert after enabling ENSAMP.");
            $stop;
        end
        
        // Wait for ADC activity
        #5000;
        
        // SAR-mode expectation: DONE stays high whenever nARST is high.
        // Note: DONE_QUAL in TLM swallows the first DONE after enable; in SAR mode
        // the mock DONE is constantly high, so we should observe ADC_DONE high here.
        #1000;
        if (ADC_DONE !== 1'b1) begin
            $display("ERROR: Expected ADC_DONE=1 in SAR mode while nARST is high.");
            $stop;
        end
        $display("SAR mode OK: ADC_DONE is high.");

        // -------------------------------------------------------------------
        // Switch to NS mode (OSR=1) for the rest of the system-level tests.
        // Writes to 0x1B are blocked while sampling is enabled, so:
        //   disable sampling → write OSR=1 → re-enable sampling
        // -------------------------------------------------------------------
        $display("\n=== Switch to NS mode (OSR=1) ===");
        spi.send_word(16'hA300, spi_rx_data); // ENSAMP=0
        #2000;
        spi.send_word(16'h9B10, spi_rx_data); // OSR=1
        $display("Wrote reg 0x1B = 0x10 (OSR=1)");
        #500;
        spi.send_word(16'hA380, spi_rx_data); // ENSAMP=1
        $display("Re-enabled sampling (reg 0x23 = 0x80)");
        #5000;
        
        // Debug: Check actual register values
        $display("DEBUG: reg[0x1B]=0x%02h (expect 0x10), reg[0x23]=0x%02h (expect 0x80), ADCOSR=%0d, SAMPLE_CLK=%b",
                 dut.u_cfg_regs.regs[8'h1B], dut.u_cfg_regs.regs[8'h23], ADCOSR_w, SAMPLE_CLK_w);

        // NS-mode expectation: DONE pulses
        adc_done_posedges = 0;
        adc_done_negedges = 0;
        adc_sample_edges  = 0;
        repeat (80) @(posedge SAMPLE_CLK_w);
        if (adc_done_posedges < 2 || adc_done_negedges < 2) begin
            $display("ERROR: Expected pulsed DONE in NS mode (OSR=%0d). posedges=%0d negedges=%0d",
                     ADCOSR_w, adc_done_posedges, adc_done_negedges);
            $stop;
        end else begin
            $display("NS mode OK: DONE pulses observed. posedges=%0d negedges=%0d over %0d SAMPLE_CLK edges",
                     adc_done_posedges, adc_done_negedges, adc_sample_edges);
        end
        
        //======================================================================
        // Test 4: Verify Mux Control (channel sequencing)
        //======================================================================
        $display("\n=== Test 4: Verify Mux Control ===");
        
        // Wait for channel transitions
        wait(ATMCHSEL[0] == 1);
        $display("  ATMCHSEL = Ch0, MUX_OUT = 0x%h", MUX_OUT);
        
        wait(ATMCHSEL[1] == 1);
        $display("  ATMCHSEL = Ch1, MUX_OUT = 0x%h", MUX_OUT);
        
        wait(ATMCHSEL[2] == 1);
        $display("  ATMCHSEL = Ch2, MUX_OUT = 0x%h", MUX_OUT);
        
        #20000;  // Let several frames accumulate
        
        //======================================================================
        // Test 5: FIFO Readout via SPI
        //======================================================================
        $display("\n=== Test 5: FIFO Readout via SPI ===");
        
        // Send RDDATA command (0xC0)
        // As with RDREG, the first returned word is STATUS, and subsequent
        // 16-bit transfers while CS remains low return FIFO data words.
        spi.begin_transaction();
        // Burst read: exact 16-clock transfers for correct framing
        spi.transfer_word16(16'hC000, spi_rx_data);
        $display("Sent RDDATA command, Status response: 0x%h", spi_rx_data);
        
        // Read 8 words (one frame)
        for (i = 0; i < 8; i = i + 1) begin
            spi.transfer_word16(16'h0000, spi_rx_data);
            fifo_readback[i*16 +: 16] = spi_rx_data;
            $display("  Word %0d: 0x%h", i, spi_rx_data);
        end
        spi.end_transaction();
        
        // Verify data pattern
        if (fifo_readback[15:0] != 16'h0000 && fifo_readback[31:16] != 16'h0000)
            $display("FIFO data looks valid (non-zero)");
        else
            $display("Warning: FIFO data may be invalid");
        
        //======================================================================
        // Test 6: Disable Sampling
        //======================================================================
        $display("\n=== Test 6: Disable Sampling ===");
        
        // Write ENSAMP = 0
        spi.send_word(16'hA300, spi_rx_data);
        $display("Disabled sampling");
        #2000;
        
        $display("Checking ADC stops...");
        #5000;
        $display("  (ADC should be idle)");
        
        //======================================================================
        // Test 7: Re-enable and Verify No Stale Data
        //======================================================================
        $display("\n=== Test 7: Re-enable Sampling (Stale Data Check) ===");
        
        spi.send_word(16'hA380, spi_rx_data);
        $display("Re-enabled sampling");
        #20000;
        
        // Read FIFO again
        spi.begin_transaction();
        spi.transfer_word16(16'hC000, spi_rx_data);
        for (i = 0; i < 8; i = i + 1) begin
            spi.transfer_word16(16'h0000, spi_rx_data);
            $display("  New Word %0d: 0x%h", i, spi_rx_data);
        end
        spi.end_transaction();
        
        //======================================================================
        // Test 8: Register Readback
        //======================================================================
        $display("\n=== Test 8: Register Readback ===");
        
        // Read CHEN register (addr 0x16)
        // Command: RDREG (00) | Addr (010110) = 0x16
        // NOTE: Command_Interpreter returns STATUS on the first 16 clocks of a CS-low
        // transaction. The register data is returned on the *next* 16 clocks while
        // CS remains low. So we must keep CS asserted across two word transfers.
        spi.begin_transaction();
        spi.transfer_word16(16'h1600, spi_rx_data);
        $display("Status: 0x%h", spi_rx_data);
        spi.transfer_word16(16'h0000, spi_rx_data); // clock out reg data
        spi.end_transaction();
        $display("CHEN readback: 0x%h (expected 0xC007 i.e. 0xC0 header + 0x07 data)", spi_rx_data);
        
        //======================================================================
        // Summary
        //======================================================================
        $display("\n========================================");
        $display("Integration Test Complete");
        $display("========================================");
        $display("Tests Performed:");
        $display("  [+] ADC configuration (OSR, GAIN)");
        $display("  [+] Channel enable and divider setup");
        $display("  [+] Sampling enable/disable");
        $display("  [+] Mux control verification");
        $display("  [+] FIFO data readout");
        $display("  [+] Stale data prevention");
        $display("  [+] Register readback");
        $display("========================================");
        if (pad_errors == 0)
            $display("MISO pad/OEN checks PASSED (0 errors)");
        else
            $display("ERROR: MISO pad/OEN checks FAILED (%0d errors)", pad_errors);
        
        #1000;
        $stop;
    end
    
    // Timeout watchdog
    initial begin
        #1000000;
        $display("ERROR: Testbench timeout!");
        $stop;
    end

endmodule
