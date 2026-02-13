`timescale 1ns / 1ps

module tb_top_level_medium();

    reg HF_CLK;
    reg RESETN;
    reg SCANEN;
    reg SCANMODE;
    reg [7:0] SATDETECT_stim;
    reg ADCOVERFLOW_stim;

    wire CS, SCK, MOSI;
    wire MISO_CORE;
    wire MISO_PAD;
    wire OEN_w;
    wire INT_w;

    wire [7:0] ATMCHSEL;
    wire ENMONTSENSE_w;
    wire SAMPLE_CLK_w;
    wire nARST_w;

    wire [15:0] ADC_RESULT;
    wire ADC_DONE;
    wire ADC_OVERFLOW_MOCK;

    wire [3:0] ADCOSR_w;
    wire [3:0] ADCGAIN_w;
    wire ENADCANALOG_w;
    wire ENMES_w;
    wire ENCHP_w;
    wire ENDWA_w;
    wire ENEXTCLK_w;
    wire DONEOVERRIDE_w;
    wire DONEOVERRIDEVAL_w;
    wire ANARSTOVERRIDE_w;
    wire ANARSTOVERRIDEVAL_w;
    wire [2:0] DIGDEBUGSEL_w;
    wire [2:0] ANATESTSEL_w;

    wire [15:0] MUX_OUT;
    wire ADCOVERFLOW_in;

    reg [15:0] spi_rx_data;
    reg [127:0] frame_data;
    reg [127:0] frame_before_disable;
    reg [127:0] frame_after;
    reg [127:0] frame_session_a;
    reg [15:0] status_word;
    reg [13:0] status_shadow;
    reg [7:0] reg_readback;
    reg [7:0] expected_readback;
    reg [7:0] cfg23_cached;
    reg [7:0] cfg13_cached;
    integer i;
    integer error_count;
    integer pad_errors;
    integer onehot_errors;
    integer seq_errors;
    integer timeout_ctr;
    integer done_seen;
    integer f;
    integer ok;

    assign ADCOVERFLOW_in = ADC_OVERFLOW_MOCK | ADCOVERFLOW_stim;

`ifdef CADENCE
    initial begin
        $shm_open("waves_medium.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_top_level_medium.vcd");
        $dumpvars(0, tb_top_level_medium);
    end
`endif

    initial begin
        HF_CLK = 1'b0;
        forever #50 HF_CLK = ~HF_CLK;
    end

    TLM dut (
        .HF_CLK(HF_CLK),
        .RESETN(RESETN),
        .CS(CS),
        .SCK(SCK),
        .MOSI(MOSI),
        .MISO(MISO_CORE),
        .OEN(OEN_w),
        .INT(INT_w),
        .SCANEN(SCANEN),
        .SCANMODE(SCANMODE),
        .RESULT(ADC_RESULT),
        .DONE(ADC_DONE),
        .ADCOVERFLOW(ADCOVERFLOW_in),
        .SATDETECT(SATDETECT_stim),
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

    assign MISO_PAD = (OEN_w === 1'b0) ? MISO_CORE : 1'bz;

    always @(CS or OEN_w or SCANMODE or MISO_PAD) begin
        #0;
        if (SCANMODE === 1'b0) begin
            if (CS === 1'b1) begin
                if (OEN_w !== 1'b1) pad_errors = pad_errors + 1;
                if (MISO_PAD !== 1'bz) pad_errors = pad_errors + 1;
            end else if (CS === 1'b0) begin
                if (OEN_w !== 1'b0) pad_errors = pad_errors + 1;
                if (MISO_PAD === 1'bz) pad_errors = pad_errors + 1;
            end
        end
    end

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
        .VIP(1'b0), .VIN(1'b0), .REFP(1'b0), .REFN(1'b0), .REFC(1'b0),
        .IBIAS_500N_PTAT(1'b0), .DVDD(1'b1), .DGND(1'b0),
        .RESULT(ADC_RESULT),
        .DONE(ADC_DONE),
        .OVERFLOW(ADC_OVERFLOW_MOCK),
        .ANALOG_TEST(),
        .DIGITAL_DEBUG()
    );

    dummy_Mux mux (
        .ATMCHSEL(ATMCHSEL),
        .TEMPSEL(ENMONTSENSE_w),
        .CH0_IN(16'hA000), .CH1_IN(16'hA111), .CH2_IN(16'hA222), .CH3_IN(16'hA333),
        .CH4_IN(16'hA444), .CH5_IN(16'hA555), .CH6_IN(16'hA666), .CH7_IN(16'hA777),
        .TEMP1_IN(16'hF111), .TEMP2_IN(16'hF222),
        .MUX_OUT(MUX_OUT)
    );

    spi_master_bfm spi (
        .CS(CS),
        .SCK(SCK),
        .MOSI(MOSI),
        .MISO(MISO_PAD)
    );

    function [2:0] onehot_to_idx;
        input [7:0] onehot;
        begin
            case (onehot)
                8'h01: onehot_to_idx = 3'd0;
                8'h02: onehot_to_idx = 3'd1;
                8'h04: onehot_to_idx = 3'd2;
                8'h08: onehot_to_idx = 3'd3;
                8'h10: onehot_to_idx = 3'd4;
                8'h20: onehot_to_idx = 3'd5;
                8'h40: onehot_to_idx = 3'd6;
                8'h80: onehot_to_idx = 3'd7;
                default: onehot_to_idx = 3'd0;
            endcase
        end
    endfunction

    function [3:0] countones8;
        input [7:0] v;
        integer k;
        begin
            countones8 = 4'd0;
            for (k = 0; k < 8; k = k + 1) begin
                if (v[k]) countones8 = countones8 + 4'd1;
            end
        end
    endfunction

    task fail_if;
        input cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("ERROR: %0s (t=%0t)", msg, $time);
                error_count = error_count + 1;
            end
        end
    endtask

    // Convenience banner to make log/wave correlation easy.
    // Use this for each major test phase (M1..M11).
    task phase_banner;
        input [255:0] name;
        begin
            $display("=== %0s (t=%0t) ===", name, $time);
        end
    endtask

    task write_reg;
        input [5:0] addr;
        input [7:0] data;
        reg [15:0] rx;
        begin
            // Register write protocol (WRREG):
            // - MOSI word format: { 2'b10, addr[5:0], data[7:0] }
            // - MISO response during the same 16 clocks is the status word
            //   (Command_Interpreter returns {status_sync, RESP_STATUS}).
            //
            // Notes:
            // - This task uses `spi.send_word` (single 16-bit word transaction).
            // - Writes may be blocked when ENSAMP is high (write protection); tests
            //   M2/M6 call `stop_sampling()` before writing protected regs.
            spi.send_word({2'b10, addr, data}, rx);
        end
    endtask

    task read_reg;
        input [5:0] addr;
        output [7:0] data;
        reg [15:0] rx;
        begin
            // Register read protocol (RDREG) is a 2-word SPI transaction:
            // - Word 0 MOSI: { 2'b00, addr[5:0], 8'h00 } (command)
            //   Word 0 MISO: status word
            // - Word 1 MOSI: 16'h0000 (dummy)
            //   Word 1 MISO: {RESP_REGDATA, rdata[7:0]} for config regs, or a
            //               special mapping for STATUS/TEMP regs.
            //
            // IMPORTANT: Multi-word SPI transactions must be framed as *exactly*
            // 16 SCK cycles per word with CS held low. `transfer_word()` adds an
            // extra edge; always use `transfer_word16()` here.
            spi.begin_transaction();
            // IMPORTANT: multi-word transaction must be exactly 16 clocks per word.
            // Using transfer_word() inserts an extra SCK edge and breaks framing.
            spi.transfer_word16({2'b00, addr, 8'h00}, rx);
            spi.transfer_word16(16'h0000, rx);
            spi.end_transaction();
            data = rx[7:0];
        end
    endtask

    task read_status;
        output [13:0] st;
        reg [7:0] lo;
        reg [7:0] hi;
        begin
            // Status is exposed as two "register" addresses (packed):
            // - 0x24: STATUS_LO = status[7:0]   (SATDETECT bits)
            // - 0x25: STATUS_HI = status[13:8] packed into [5:0] (upper 2 bits are 0)
            //
            // The TB reconstructs the 14-bit status word as {hi[5:0], lo}.
            read_reg(6'h24, lo);
            read_reg(6'h25, hi);
            st = {hi[5:0], lo};
        end
    endtask

    task clear_status_bits;
        input [13:0] clr_mask;
        begin
            // Status clear is W1C via two write addresses:
            // - 0x26: STATUS_CLR_LO = clr_mask[7:0]
            // - 0x27: STATUS_CLR_HI = clr_mask[13:8] in bits [5:0]
            //
            // This is NOT an immediate combinational clear:
            // - Clear request is launched in SCK domain, crosses into HF_CLK domain
            //   via Status_Clear_CDC, then Status_Monitor clears sticky bits.
            // - Tests that depend on clear must allow CDC latency and handshake.
            write_reg(6'h26, clr_mask[7:0]);
            write_reg(6'h27, {2'b00, clr_mask[13:8]});
            repeat (8) @(posedge HF_CLK);
        end
    endtask

    task dbg_status_clear_signals;
        input [255:0] tag;
        begin
            $display("DBG(%0s) t=%0t status=%b ovf_pulse=%b udf_pulse=%b clr_pulse_hf=%b clr_mask_hf=%b req_tgl_sck=%b ack_tgl_hf=%b",
                     tag, $time,
                     dut.status_mon_out,
                     dut.fifo_overflow_sync,
                     dut.fifo_underflow_sync,
                     dut.status_clr_pulse_hf,
                     dut.status_clr_mask_hf,
                     dut.status_clr_req_tgl,
                     dut.status_clr_ack_tgl);
        end
    endtask

    task read_fifo_frame;
        output [15:0] st_word;
        output [127:0] data128;
        reg [15:0] rx;
        integer wi;
        begin
            // FIFO read protocol (RDDATA burst):
            // - Word 0 MOSI: 16'hC000 (CMD_RDDATA)
            //   Word 0 MISO: status word (same format as other transactions)
            // - Words 1..8 MOSI: 16'h0000 (dummy)
            //   Words 1..8 MISO: 8x 16-bit words from ADC_data[127:0]
            //
            // Subtlety:
            // - In Command_Interpreter, `word_counter` increments on each received
            //   word, including the command word. Therefore the first returned data
            //   word after the command corresponds to word_counter==1 (word1).
            spi.begin_transaction();
            // RDDATA burst: keep framing aligned (16 clocks per word).
            spi.transfer_word16(16'hC000, rx);
            st_word = rx;
            for (wi = 0; wi < 8; wi = wi + 1) begin
                spi.transfer_word16(16'h0000, rx);
                data128[wi*16 +: 16] = rx;
            end
            spi.end_transaction();
        end
    endtask

    // Command_Interpreter's READ_DATA stream is effectively rotated by 1 word because
    // word_counter increments on the command word's word_rcvd. Reorder so that
    // output word0 corresponds to channel 0 (bits [15:0]) as intended.
    task read_fifo_frame_reordered;
        output [15:0] st_word;
        output [127:0] data128_reordered;
        reg [127:0] data_raw;
        integer k;
        begin
            read_fifo_frame(st_word, data_raw);
            // raw[0] is word1, raw[1] is word2, ..., raw[6] is word7, raw[7] is word0
            data128_reordered[15:0] = data_raw[127:112]; // word0
            for (k = 0; k < 7; k = k + 1) begin
                data128_reordered[(k+1)*16 +: 16] = data_raw[k*16 +: 16];
            end
        end
    endtask

    task adc_config_for_test;
        begin
            // Ensure the mock produces clearly non-zero data.
            // Register map used here:
            // - 0x1C: ADCGAIN in low nibble [3:0]
            //   (upper bits are other ADC config spares/controls)
            write_reg(6'h1C, 8'h0F);
            // 0x1B: enable ADC analog + set OSR (bits[7:4]).
            // Set ENADCANALOG=1 (bit0) and default OSR=1 (0x10) => 0x11.
            // - 0x1B[7:4] = OSR code
            // - 0x1B[0]   = ENADCANALOG
            write_reg(6'h1B, 8'h11);
        end
    endtask

    // Configure SAMPLE_CLK to ~8kHz continuous (no silence phase).
    // HF_CLK is 10MHz in TB, so set PHASE1DIV1=625 => 10MHz/(2*625)=8kHz.
    task divider_config_slow_continuous;
        begin
            // NOTE:
            // - This config targets ~8kHz SAMPLE_CLK when HF_CLK=10MHz (PHASE1DIV1=625).
            // - M6 underflow relies on SPI consumption outrunning production, so we
            //   deliberately slow SAMPLE_CLK here (and restore it afterwards).
            //
            // Divider register map used here:
            // - 0x20: PHASE1DIV1[7:0]
            // - 0x21: { PHASE1COUNT[3:0], PHASE1DIV1[11:8] }
            // - 0x22: PHASE2COUNT[7:0]
            // - 0x23: also contains PHASE2COUNT[9:8] in [1:0] (shared with ENSAMP/WM)
            // PHASE1DIV1[7:0] in reg 0x20, PHASE1DIV1[11:8] in reg 0x21[3:0]
            // PHASE1COUNT in reg 0x21[7:4]; PHASE2COUNT in {reg0x23[1:0], reg0x22}
            write_reg(6'h20, 8'h71); // low byte of 0x271
            write_reg(6'h21, 8'h12); // PHASE1COUNT=1, PHASE1DIV2=2
            write_reg(6'h22, 8'h00); // PHASE2COUNT[7:0]=0 (continuous mode)
        end
    endtask

    // Configure SAMPLE_CLK to passthrough HF_CLK (fast) and continuous mode.
    // This keeps later tests fast after we intentionally slow the clock for M6.
    task divider_config_fast_passthrough;
        begin
            // PHASE1DIV1 = 0 => passthrough mode.
            write_reg(6'h20, 8'h00); // PHASE1DIV1[7:0]
            // PHASE1COUNT=1 (upper nibble), PHASE1DIV1[11:8]=0 (lower nibble)
            write_reg(6'h21, 8'h10);
            write_reg(6'h22, 8'h00); // PHASE2COUNT[7:0]=0
        end
    endtask

    task set_ensamp_and_watermark;
        input ensamp_en;
        input [3:0] wm;
        reg [7:0] v;
        begin
            // 0x23: ENSAMP/WATERMARK control register (TB view)
            // - [7]   ENSAMP enable
            // - [6:3] watermark (4-bit)
            // - [2:0] currently unused here
            //
            // NOTE: In RTL, 0x23 is also overloaded with some divider bits in [1:0]
            // (PHASE2COUNT[9:8]). This TB currently writes [2:0]=0 for simplicity.
            v = {ensamp_en, wm, 3'b000};
            write_reg(6'h23, v);
        end
    endtask

    task stop_sampling;
        reg [15:0] rx_tmp;
        begin
            set_ensamp_and_watermark(1'b0, 4'd0);
            repeat (20) @(posedge HF_CLK);
            // Ensure Command_Interpreter's SCK-domain ENSAMP_sync_reg has time to update
            // before we attempt writes to protected registers.
            spi.send_word(16'h0000, rx_tmp);
        end
    endtask

    task start_sampling;
        input [3:0] wm;
        begin
            set_ensamp_and_watermark(1'b1, wm);
            repeat (20) @(posedge HF_CLK);
        end
    endtask

    task set_osr;
        input [3:0] osr;
        begin
            // Convenience: program OSR code into reg 0x1B[7:4].
            // WARNING: This writes the whole low nibble to 0, so if you need to keep
            // ENADCANALOG or other control bits set, use `adc_config_for_test()` or
            // explicitly write the full desired value.
            write_reg(6'h1B, {osr, 4'b0000});
        end
    endtask

    task wait_for_data_rdy;
        output found;
        begin
            found = 1'b0;
            timeout_ctr = 0;
            // Allow long enough for slow SAMPLE_CLK configs and DONE_QUAL swallowing
            while ((found == 1'b0) && (timeout_ctr < 200000)) begin
                // DATA_RDY is generated inside FIFO in the SAMPLE_CLK domain and then
                // observed here in the TB (HF_CLK domain). Expect some latency when
                // SAMPLE_CLK is slow and/or when ENSAMP transitions have just occurred.
                if (dut.DATA_RDY === 1'b1) begin
                    found = 1'b1;
                end
                @(posedge HF_CLK);
                timeout_ctr = timeout_ctr + 1;
            end
        end
    endtask

    task wait_for_done_pulses;
        input integer n;
        output integer seen;
        integer guard;
        begin
            seen = 0;
            guard = 0;
            while ((seen < n) && (guard < 5000)) begin
                @(posedge SAMPLE_CLK_w);
                if (ADC_DONE) seen = seen + 1;
                guard = guard + 1;
            end
        end
    endtask

    initial begin
        RESETN = 1'b0;
        SCANEN = 1'b0;
        SCANMODE = 1'b0;
        SATDETECT_stim = 8'h00;
        ADCOVERFLOW_stim = 1'b0;
        error_count = 0;
        pad_errors = 0;
        onehot_errors = 0;
        seq_errors = 0;
        #500;
        RESETN = 1'b1;
        repeat (10) @(posedge HF_CLK);

        phase_banner("MEDIUM TB: M1 register round-trip");
        set_ensamp_and_watermark(1'b0, 4'd0);
        for (i = 0; i < 36; i = i + 1) begin
            expected_readback = (i * 8'h17) ^ 8'h5A;
            // Avoid accidentally enabling sampling during the register sweep.
            if (i[5:0] == 6'h23) expected_readback[7] = 1'b0; // ENSAMP bit
            write_reg(i[5:0], expected_readback);
            read_reg(i[5:0], reg_readback);
            fail_if(reg_readback !== expected_readback, "M1 register readback mismatch");
        end

        phase_banner("MEDIUM TB: M2 write protection");
        write_reg(6'h16, 8'h07);
        set_osr(4'h1);
        set_ensamp_and_watermark(1'b1, 4'd1);
        repeat (50) @(posedge HF_CLK);
        read_reg(6'h1B, reg_readback);
        cfg23_cached = reg_readback;
        write_reg(6'h1B, 8'h40);
        read_reg(6'h1B, reg_readback);
        fail_if(reg_readback !== cfg23_cached, "M2 protected write unexpectedly changed reg 0x1B");
        write_reg(6'h12, 8'hC3);
        read_reg(6'h12, reg_readback);
        fail_if(reg_readback !== 8'hC3, "M2 exempt write failed for 0x12");
        write_reg(6'h13, 8'h1F);
        read_reg(6'h13, reg_readback);
        fail_if(reg_readback !== 8'h1F, "M2 exempt write failed for 0x13");
        read_reg(6'h23, cfg13_cached);
        write_reg(6'h23, cfg13_cached ^ 8'h80);
        read_reg(6'h23, reg_readback);
        fail_if(reg_readback !== (cfg13_cached ^ 8'h80), "M2 exempt write failed for 0x23");
        set_ensamp_and_watermark(1'b1, 4'd1);

        phase_banner("MEDIUM TB: M3 reset behavior");
        RESETN = 1'b0;
        repeat (8) @(posedge HF_CLK);
        fail_if(nARST_w !== 1'b0, "M3 nARST not low during reset");
        fail_if(ATMCHSEL !== 8'h00, "M3 ATMCHSEL not zero during reset");
        RESETN = 1'b1;
        repeat (8) @(posedge HF_CLK);
        for (i = 0; i < 36; i = i + 1) begin
            read_reg(i[5:0], reg_readback);
            fail_if(reg_readback !== 8'h00, "M3 register not reset to zero");
        end

        phase_banner("MEDIUM TB: M4 channel sequencing");
        stop_sampling();
        write_reg(6'h16, 8'h85);
        adc_config_for_test();
        start_sampling(4'd1);
        repeat (30) @(posedge SAMPLE_CLK_w);
        for (i = 0; i < 80; i = i + 1) begin
            @(posedge SAMPLE_CLK_w);
            if (ATMCHSEL != 8'h00) begin
                if (countones8(ATMCHSEL) != 4'd1) onehot_errors = onehot_errors + 1;
                if ((ATMCHSEL != 8'h01) && (ATMCHSEL != 8'h04) && (ATMCHSEL != 8'h80)) seq_errors = seq_errors + 1;
            end
        end
        fail_if(onehot_errors != 0, "M4 one-hot violation observed");
        fail_if(seq_errors != 0, "M4 unexpected channel index observed");

        phase_banner("MEDIUM TB: M5 FIFO fill/watermark/readout");
        stop_sampling();
        write_reg(6'h16, 8'h07);
        adc_config_for_test();
        start_sampling(4'd2);
        wait_for_data_rdy(done_seen[0]);
        fail_if(done_seen[0] == 1'b0, "M5 DATA_RDY did not assert");
        // Look-ahead FIFO: Data is valid immediately (no prime needed)
        read_fifo_frame_reordered(status_word, frame_data);
        fail_if(frame_data[15:0]   == 16'h0000, "M5 CH0 data unexpectedly zero");
        fail_if(frame_data[31:16]  == 16'h0000, "M5 CH1 data unexpectedly zero");
        fail_if(frame_data[47:32]  == 16'h0000, "M5 CH2 data unexpectedly zero");
        fail_if(frame_data[63:48]  != 16'h0000, "M5 disabled CH3 should be zero");
        fail_if(frame_data[127:112] != 16'h0000, "M5 disabled CH7 should be zero");

        phase_banner("MEDIUM TB: M6 overflow/underflow/W1C");
        clear_status_bits(14'h3FFF);
        dbg_status_clear_signals("after_clear_all");
        stop_sampling();
        write_reg(6'h16, 8'hFF);
        adc_config_for_test();
        start_sampling(4'd4);
        repeat (600) @(posedge SAMPLE_CLK_w);
        read_status(status_shadow);
        dbg_status_clear_signals("after_overflow_fill");
        fail_if(status_shadow[9] !== 1'b1, "M6 FIFO overflow flag not set");

        // Underflow test: slow down sampling so SPI can outrun production.
        // Why: with reduced FIFO depth, a fast SAMPLE_CLK can produce frames faster
        // than we can drain over SPI, making underflow impossible to hit reliably.
        //
        // What "underflow" means here:
        // - FIFO_UNDERFLOW is an *event* (toggle in FIFO's SCK domain)
        // - That toggle is synchronized into HF_CLK and edge-detected into a 1-cycle
        //   pulse in `CDC_sync`, then latched sticky in `Status_Monitor`.
        // - Therefore after an empty pop we must allow time for:
        //     SCK-domain event -> HF_CLK pulse -> sticky set -> status sync back to SCK.
        //
        // If this test ever fails again, debug in waves around the "after_underflow_pop"
        // tag:
        // - `dut.cim_fifo_pop` (FIFO_POP source)
        // - `dut.u_fifo.frames_available`, `dut.u_fifo.read_ptr`, `dut.u_fifo.write_ptr_sync_bin`
        // - `dut.fifo_underflow_sync` (HF_CLK pulse)
        // - `dut.u_stat_mon.status` (sticky latch)
        //
        // Design note:
        // - If SAMPLE_CLK is fully gated/stopped immediately when ENSAMP drops, any
        //   write-domain cleanup that relies on SAMPLE_CLK edges will be delayed until
        //   the next enable. That can make "empty" detection timing-sensitive when
        //   FIFO depth is small.
        stop_sampling();
        divider_config_slow_continuous();
        write_reg(6'h16, 8'h01); // single channel => 1 DONE per frame
        adc_config_for_test();   // OSR=1
        start_sampling(4'd1);
        wait_for_data_rdy(done_seen[0]);
        fail_if(done_seen[0] == 1'b0, "M6 DATA_RDY did not assert for underflow setup");
        // Pop the one available frame, then immediately pop again while empty.
        read_fifo_frame_reordered(status_word, frame_data);
        read_fifo_frame_reordered(status_word, frame_data);
        // Allow CDC/status propagation: SCK->FIFO->HF_CLK->Status_Monitor->SCK
        repeat (50000) @(posedge HF_CLK);
        read_status(status_shadow);
        dbg_status_clear_signals("after_underflow_pop");
        fail_if(status_shadow[10] !== 1'b1, "M6 FIFO underflow flag not set");

        // Stop sampling so overflow/underflow cannot immediately re-fire while clearing
        stop_sampling();
        dbg_status_clear_signals("before_clear_fifo_flags");
        // Clear FIFO_UDF (bit10) and FIFO_OVF (bit9)
        clear_status_bits(14'h0600);
        dbg_status_clear_signals("after_clear_fifo_flags_cmd");
        // W1C clear crosses SCK->HF_CLK and is acknowledged; allow some time then poll.
        timeout_ctr = 0;
        repeat (50) @(posedge HF_CLK);
        read_status(status_shadow);
        dbg_status_clear_signals("poll0");
        while (((status_shadow[10] !== 1'b0) || (status_shadow[9] !== 1'b0)) && (timeout_ctr < 20)) begin
            repeat (50) @(posedge HF_CLK);
            read_status(status_shadow);
            dbg_status_clear_signals("pollN");
            timeout_ctr = timeout_ctr + 1;
        end
        fail_if((status_shadow[10] !== 1'b0) || (status_shadow[9] !== 1'b0), "M6 W1C failed to clear FIFO flags");

        // Restore fast SAMPLE_CLK for the rest of the tests (M6 underflow uses slow clock).
        divider_config_fast_passthrough();

        phase_banner("MEDIUM TB: M7 OSR integrity checks");
        set_ensamp_and_watermark(1'b0, 4'd0);
        write_reg(6'h1C, 8'h0F);
        set_osr(4'h0);
        set_ensamp_and_watermark(1'b1, 4'd1);
        repeat (20) @(posedge SAMPLE_CLK_w);
        fail_if(ADC_DONE !== 1'b1, "M7 OSR=0 expected DONE high");
        set_ensamp_and_watermark(1'b0, 4'd0);
        set_osr(4'h1);
        set_ensamp_and_watermark(1'b1, 4'd1);
        wait_for_done_pulses(4, done_seen);
        fail_if(done_seen < 4, "M7 OSR=1 insufficient DONE pulses");
        set_ensamp_and_watermark(1'b0, 4'd0);
        set_osr(4'h4);
        set_ensamp_and_watermark(1'b1, 4'd1);
        wait_for_done_pulses(3, done_seen);
        fail_if(done_seen < 3, "M7 OSR=4 insufficient DONE pulses");
        stop_sampling();

        phase_banner("MEDIUM TB: M8 disable/re-enable stale data");
        stop_sampling();
        write_reg(6'h16, 8'h0F);
        adc_config_for_test();
        start_sampling(4'd1);
        wait_for_data_rdy(done_seen[0]);
        // Look-ahead FIFO: First frame is valid data
        read_fifo_frame_reordered(status_word, frame_data);
        // Save pre-disable frame (not used for equality compare — ADC restarts can repeat)
        frame_session_a = frame_data;
        set_ensamp_and_watermark(1'b0, 4'd0);
        // Protocol rule: end transaction after ENSAMP=0 before attempting RDDATA.
        // This guarantees SCK edges for ensamp_rstn_sck and FIFO read-side reset.
        repeat (20) @(posedge HF_CLK);
        
        // Verify RDDATA returns zeros after disable (no stale data).
        read_fifo_frame_reordered(status_word, frame_data);
        fail_if(frame_data !== 128'h0, "M8 expected zero frame after disable");

        // Re-enable and verify new data flows (no stale data from before disable).
        set_ensamp_and_watermark(1'b1, 4'd1);
        wait_for_data_rdy(done_seen[0]);
        
        // Read a frame and verify it's non-zero (new conversions are happening).
        // We already verified post-disable reads returned zeros, so non-zero here
        // confirms the system reset cleanly and is generating fresh data.
        read_fifo_frame_reordered(status_word, frame_after);
        fail_if(frame_after === 128'h0, "M8 re-enable produced all-zero frame (no new data)");

        phase_banner("MEDIUM TB: M9 status and INT");
        clear_status_bits(14'h3FFF);
        SATDETECT_stim = 8'h20;
        repeat (4) @(posedge HF_CLK);
        SATDETECT_stim = 8'h00;
        read_status(status_shadow);
        fail_if(status_shadow[5] !== 1'b1, "M9 SAT bit5 not set");
        fail_if(INT_w !== 1'b1, "M9 INT not asserted on SAT status");
        clear_status_bits(14'h0020);
        repeat (6) @(posedge HF_CLK);
        read_status(status_shadow);
        fail_if(status_shadow[5] !== 1'b0, "M9 SAT bit5 not cleared");
        ADCOVERFLOW_stim = 1'b1;
        repeat (2) @(posedge HF_CLK);
        ADCOVERFLOW_stim = 1'b0;
        read_status(status_shadow);
        fail_if(status_shadow[8] !== 1'b1, "M9 ADC overflow bit not set");
        clear_status_bits(14'h0100);
        repeat (6) @(posedge HF_CLK);
        read_status(status_shadow);
        fail_if(status_shadow[8] !== 1'b0, "M9 ADC overflow bit not cleared");

        phase_banner("MEDIUM TB: M10 temperature one-shot");
        stop_sampling();
        // Ensure ADC mock produces a non-zero TEMPVAL and OSR=1 for predictable DONE pulses.
        adc_config_for_test();
        
        // Ensure ENMONTSENSE is low first, then raise it to create a rising edge.
        write_reg(6'h13, 8'h00);
        repeat (20) @(posedge HF_CLK);
        
        // Trigger one-shot (ENMONTSENSE rising edge).
        write_reg(6'h13, 8'h08); // Set ENMONTSENSE (bit3 of reg 0x13)

        // Temp run may be brief (one conversion). Verify it asserted at least once and
        // that it completed.
        timeout_ctr = 0;
        while ((dut.temp_run !== 1'b1) && (timeout_ctr < 2000)) begin
            @(posedge HF_CLK);
            timeout_ctr = timeout_ctr + 1;
        end
        fail_if(dut.temp_run !== 1'b1, "M10 temp one-shot did not start (temp_run never asserted)");

        timeout_ctr = 0;
        while ((dut.temp_run === 1'b1) && (timeout_ctr < 20000)) begin
            @(posedge HF_CLK);
            timeout_ctr = timeout_ctr + 1;
        end
        fail_if(dut.temp_run !== 1'b0, "M10 temp one-shot did not complete (temp_run stuck high)");
        
        // TEMPVAL is synchronized into Command_Interpreter in the SCK domain.
        // Provide SCK edges so TEMPVAL_sync[1] is guaranteed updated before readback.
        spi.send_word(16'h0000, spi_rx_data);
        spi.send_word(16'h0000, spi_rx_data);
        read_reg(6'h2C, reg_readback);
        status_word[15:8] = reg_readback;
        read_reg(6'h2D, reg_readback);
        status_word[7:0] = reg_readback;
        fail_if(status_word == 16'h0000, "M10 TEMPVAL remained zero");

        phase_banner("MEDIUM TB: M11 OEN/MISO pad checker");
        fail_if(pad_errors != 0, "M11 OEN/MISO pad checker found errors");

        if (error_count == 0) begin
            $display("PASS: tb_top_level_medium completed with 0 errors");
        end else begin
            $display("FAIL: tb_top_level_medium completed with %0d errors", error_count);
        end
        #1000;
        $stop;
    end

    initial begin
        #20000000;
        $display("ERROR: medium TB timeout");
        $stop;
    end

endmodule
