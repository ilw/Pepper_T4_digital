`timescale 1ns / 1ps

// Mock-signoff tier:
// - Uses `testbenches/ns_sar_v2_mock.v` (module name `ns_sar_v2`)
// - Intended to run on Icarus without foundry libraries
//
// "True" signoff (real ADC netlist) is in `tb_top_level_signoff.v`.
module tb_top_level_mock_signoff();

    reg HF_CLK;
    reg RESETN;
    reg SCANEN;
    reg SCANMODE;
    reg [7:0] SATDETECT_stim;
    reg ADCOVERFLOW_stim;

    reg CS;
    reg SCK;
    reg MOSI;
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

    reg [15:0] spi_rx;
    reg [127:0] frame_data;
    reg [13:0] status_shadow;
    reg [7:0] reg_readback;
    integer i;
    integer j;
    integer error_count;
    integer skip_count;
    integer pass_count;
    integer pad_errors;
    integer test_pass [0:15];
    integer sample_ctr;
    integer done_ctr;
    integer sample_mark_a;
    integer sample_mark_b;
    integer ok;
    integer period_expected;
    integer prev_rdy;
    integer stable;

    assign ADCOVERFLOW_in = ADC_OVERFLOW_MOCK | ADCOVERFLOW_stim;
    assign MISO_PAD = (OEN_w === 1'b0) ? MISO_CORE : 1'bz;

`ifdef CADENCE
    initial begin
        $shm_open("waves_mock_signoff.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_top_level_mock_signoff.vcd");
        $dumpvars(0, tb_top_level_mock_signoff);
    end
`endif

    initial begin
        HF_CLK = 1'b0;
        forever #50 HF_CLK = ~HF_CLK;
    end

    always @(posedge SAMPLE_CLK_w) sample_ctr = sample_ctr + 1;

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

    // NOTE: This instantiates `ns_sar_v2` which is provided by `ns_sar_v2_mock.v`
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

    task mark_test;
        input integer idx;
        input integer pass;
        begin
            test_pass[idx] = pass;
        end
    endtask

    task spi_begin;
        begin
            CS = 1'b0;
            #100;
        end
    endtask

    task spi_end;
        begin
            #100;
            CS = 1'b1;
            SCK = 1'b1;
            #100;
        end
    endtask

    // Transfer exactly 16 SCK cycles for one 16-bit word (Mode 3).
    // IMPORTANT: Multi-word transactions (RDREG, RDDATA bursts) require *exact* 16-cycle
    // framing per word with CS held low. Do NOT add trailing clocks here.
    task spi_transfer_word16_timed;
        input [15:0] tx;
        input integer half_period_ns;
        output [15:0] rx;
        integer bi;
        begin
            rx = 16'h0000;
            for (bi = 15; bi >= 0; bi = bi - 1) begin
                MOSI = tx[bi];
                #(half_period_ns);
                SCK = 1'b0;
                #(half_period_ns);
                SCK = 1'b1;
                #(half_period_ns/2);
                rx[bi] = MISO_PAD;
                #(half_period_ns/2);
            end
        end
    endtask

    // Write-friendly transfer: 16 cycles + one extra rising edge.
    task spi_transfer_word_wr_timed;
        input [15:0] tx;
        input integer half_period_ns;
        output [15:0] rx;
        begin
            spi_transfer_word16_timed(tx, half_period_ns, rx);
            #(half_period_ns);
            SCK = 1'b0;
            #(half_period_ns);
            SCK = 1'b1;
            #(half_period_ns);
        end
    endtask

    task write_reg_timed;
        input [5:0] addr;
        input [7:0] data;
        input integer half_period_ns;
        begin
            spi_begin();
            spi_transfer_word_wr_timed({2'b10, addr, data}, half_period_ns, spi_rx);
            spi_end();
        end
    endtask

    task read_reg_timed;
        input [5:0] addr;
        input integer half_period_ns;
        output [7:0] data;
        begin
            spi_begin();
            spi_transfer_word16_timed({2'b00, addr, 8'h00}, half_period_ns, spi_rx);
            spi_transfer_word16_timed(16'h0000, half_period_ns, spi_rx);
            spi_end();
            data = spi_rx[7:0];
        end
    endtask

    task read_status;
        output [13:0] st;
        reg [7:0] lo;
        reg [7:0] hi;
        begin
            read_reg_timed(6'h24, 50, lo);
            read_reg_timed(6'h25, 50, hi);
            st = {hi[5:0], lo};
        end
    endtask

    task clear_status_bits;
        input [13:0] clr_mask;
        begin
            write_reg_timed(6'h26, clr_mask[7:0], 50);
            write_reg_timed(6'h27, {2'b00, clr_mask[13:8]}, 50);
            repeat (8) @(posedge HF_CLK);
        end
    endtask

    task set_ensamp_wm;
        input ensamp_en;
        input [3:0] wm;
        begin
            write_reg_timed(6'h23, {ensamp_en, wm, 3'b000}, 50);
        end
    endtask

    // Configure SAMPLE_CLK to ~8 kHz continuous (no silence phase) for realistic operation.
    // HF_CLK is 10 MHz in TB, so set PHASE1DIV1=625 => 10MHz/(2*625)=8kHz.
    task divider_config_8khz_continuous;
        begin
            // Disable sampling before touching divider regs (safe/procedural).
            set_ensamp_wm(1'b0, 4'd0);
            repeat (10) @(posedge HF_CLK);
            // PHASE1DIV1[7:0] in reg 0x20, PHASE1DIV1[11:8] in reg 0x21[3:0]
            // PHASE1COUNT in reg 0x21[7:4]; PHASE2COUNT in {reg0x23[1:0], reg0x22}
            write_reg_timed(6'h20, 8'h71, 50); // low byte of 12'h271 (625)
            write_reg_timed(6'h21, 8'h12, 50); // PHASE1COUNT=1, PHASE1DIV1[11:8]=2
            write_reg_timed(6'h22, 8'h00, 50); // PHASE2COUNT low byte = 0 (continuous mode)
        end
    endtask

    task read_fifo_frame;
        output [127:0] data128;
        begin
            spi_begin();
            spi_transfer_word16_timed(16'hC000, 50, spi_rx);
            for (i = 0; i < 8; i = i + 1) begin
                spi_transfer_word16_timed(16'h0000, 50, spi_rx);
                data128[i*16 +: 16] = spi_rx;
            end
            spi_end();
        end
    endtask

    initial begin
        for (i = 0; i < 16; i = i + 1) test_pass[i] = -1;
        pass_count = 0;
        skip_count = 0;
        error_count = 0;
        pad_errors = 0;
        sample_ctr = 0;
        done_ctr = 0;

        RESETN = 1'b0;
        SCANEN = 1'b0;
        SCANMODE = 1'b0;
        SATDETECT_stim = 8'h00;
        ADCOVERFLOW_stim = 1'b0;
        CS = 1'b1;
        SCK = 1'b1;
        MOSI = 1'b0;
        #500;
        RESETN = 1'b1;
        repeat (10) @(posedge HF_CLK);

        // This file is a direct copy of the signoff logic; see `tb_top_level_signoff.v`
        // for the test list and coverage summary. Keeping the body identical ensures
        // mock-signoff and real-signoff run the same sequences.

        // S1..S14 body (kept identical to tb_top_level_signoff)
        ok = 1;
        write_reg_timed(6'h00, 8'h00, 50); read_reg_timed(6'h00, 50, reg_readback); if (reg_readback !== 8'h00) ok = 0;
        write_reg_timed(6'h00, 8'hFF, 50); read_reg_timed(6'h00, 50, reg_readback); if (reg_readback !== 8'hFF) ok = 0;
        write_reg_timed(6'h00, 8'hA5, 50); read_reg_timed(6'h00, 50, reg_readback); if (reg_readback !== 8'hA5) ok = 0;
        write_reg_timed(6'h00, 8'h5A, 50); read_reg_timed(6'h00, 50, reg_readback); if (reg_readback !== 8'h5A) ok = 0;
        fail_if(ok == 0, "S1 SPI edge-pattern write/read failed");
        mark_test(1, ok);

        ok = 1;
        for (i = 0; i < 8; i = i + 1) begin
            write_reg_timed(i[5:0], (8'h31 + i[7:0]), 33);
            read_reg_timed(i[5:0], 33, reg_readback);
            if (reg_readback !== (8'h31 + i[7:0])) ok = 0;
        end
        fail_if(ok == 0, "S2 fast SPI R/W failed");
        mark_test(2, ok);

        ok = 1;
        write_reg_timed(6'h16, 8'h01, 50);
        write_reg_timed(6'h1B, 8'h10, 50);
        write_reg_timed(6'h20, 8'h00, 50);
        write_reg_timed(6'h21, 8'h10, 50);
        write_reg_timed(6'h22, 8'h00, 50);
        set_ensamp_wm(1'b1, 4'd1);
        repeat (20) @(posedge SAMPLE_CLK_w);
        sample_mark_a = sample_ctr;
        repeat (20) @(posedge HF_CLK);
        sample_mark_b = sample_ctr;
        if (sample_mark_b <= sample_mark_a) ok = 0;
        set_ensamp_wm(1'b0, 4'd0);
        fail_if(ok == 0, "S3 divider did not produce SAMPLE_CLK");
        mark_test(3, ok);

        ok = 1;
        write_reg_timed(6'h1B, 8'h10, 50);
        for (j = 0; j < 6; j = j + 1) begin
            case (j)
                0: write_reg_timed(6'h16, 8'h01, 50);
                1: write_reg_timed(6'h16, 8'h80, 50);
                2: write_reg_timed(6'h16, 8'h55, 50);
                3: write_reg_timed(6'h16, 8'hAA, 50);
                4: write_reg_timed(6'h16, 8'hFF, 50);
                default: write_reg_timed(6'h16, 8'h00, 50);
            endcase
            set_ensamp_wm(1'b1, 4'd1);
            repeat (40) @(posedge HF_CLK);
            if (j == 5) begin
                if (nARST_w !== 1'b0) ok = 0;
            end
            set_ensamp_wm(1'b0, 4'd0);
        end
        fail_if(ok == 0, "S4 CHEN permutation behavior failed");
        mark_test(4, ok);

        ok = 1;
        write_reg_timed(6'h16, 8'h01, 50);
        for (j = 0; j < 16; j = j + 1) begin
            set_ensamp_wm(1'b0, 4'd0);
            write_reg_timed(6'h1B, {j[3:0], 4'b0000}, 50);
            set_ensamp_wm(1'b1, 4'd1);
            repeat (3) @(posedge SAMPLE_CLK_w);
            if (j == 0) begin
                if (ADC_DONE !== 1'b1) ok = 0;
            end else begin
                while (ADC_DONE !== 1'b1) @(posedge SAMPLE_CLK_w);
                sample_mark_a = sample_ctr;
                @(posedge SAMPLE_CLK_w);
                while (ADC_DONE !== 1'b1) @(posedge SAMPLE_CLK_w);
                sample_mark_b = sample_ctr;
                period_expected = (4*j) + 2;
                if ((sample_mark_b - sample_mark_a) != period_expected) ok = 0;
            end
        end
        set_ensamp_wm(1'b0, 4'd0);
        fail_if(ok == 0, "S5 OSR sweep DONE period failed");
        mark_test(5, ok);

        ok = 1;
        clear_status_bits(14'h3FFF);
        for (j = 0; j < 8; j = j + 1) begin
            SATDETECT_stim = (8'h01 << j);
            repeat (3) @(posedge HF_CLK);
            SATDETECT_stim = 8'h00;
            read_status(status_shadow);
            if (status_shadow[j] !== 1'b1) ok = 0;
            clear_status_bits(14'h0001 << j);
        end
        SATDETECT_stim = 8'hA5;
        repeat (3) @(posedge HF_CLK);
        SATDETECT_stim = 8'h00;
        read_status(status_shadow);
        if (status_shadow[7:0] != 8'hA5) ok = 0;
        clear_status_bits(14'h00FF);
        fail_if(ok == 0, "S6 saturation status failed");
        mark_test(6, ok);

        ok = 1;
        ADCOVERFLOW_stim = 1'b1;
        repeat (3) @(posedge HF_CLK);
        ADCOVERFLOW_stim = 1'b0;
        read_status(status_shadow);
        if (status_shadow[8] !== 1'b1) ok = 0;
        clear_status_bits(14'h0100);
        read_status(status_shadow);
        if (status_shadow[8] !== 1'b0) ok = 0;
        fail_if(ok == 0, "S7 ADC overflow status failed");
        mark_test(7, ok);

`ifdef ENABLE_REGISTER_CRC
        ok = 1;
        spi_begin();
        spi_transfer_word16_timed(16'h4000, 50, spi_rx);
        spi_transfer_word16_timed(16'h0000, 50, spi_rx);
        spi_end();
        if (spi_rx === 16'hxxxx) ok = 0;
        mark_test(8, ok);
        fail_if(ok == 0, "S8 CRC read command failed");
`else
        mark_test(8, 2);
`endif

        // S9: DATA_RDY semantics (use realistic 8kHz SAMPLE_CLK)
        ok = 1;
        divider_config_8khz_continuous();
        write_reg_timed(6'h16, 8'hFF, 50);
        write_reg_timed(6'h1B, 8'h10, 50); // OSR=1
        set_ensamp_wm(1'b1, 4'd2);
        // Wait long enough for two frames to be produced at 8kHz/OSR=1.
        repeat (20000) @(posedge HF_CLK);
        if (dut.DATA_RDY !== 1'b1) ok = 0;
        // Drain until DATA_RDY deasserts (producer is slow, so this should converge).
        for (j = 0; j < 8; j = j + 1) begin
            if (dut.DATA_RDY === 1'b1) begin
                read_fifo_frame(frame_data);
                repeat (2000) @(posedge HF_CLK);
            end
        end
        if (dut.DATA_RDY !== 1'b0) ok = 0;
        set_ensamp_wm(1'b0, 4'd0);
        fail_if(ok == 0, "S9 DATA_RDY threshold behavior failed");
        mark_test(9, ok);

        // S10: Frame cleared before being (re)written (avoid over-specific timing on mem-clear-after-pop).
        // Approach:
        // 1) Run with all channels enabled to ensure non-zero words exist in frame slots.
        // 2) Disable, then switch to CHEN=0x01 (only channel 0 enabled).
        // 3) Re-enable and read a frame; verify channels 1..7 read as 0 (no stale leftovers).
        ok = 1;
        divider_config_8khz_continuous();
        write_reg_timed(6'h1B, 8'h10, 50); // OSR=1
        write_reg_timed(6'h16, 8'hFF, 50);
        set_ensamp_wm(1'b1, 4'd1);
        repeat (20000) @(posedge HF_CLK);
        read_fifo_frame(frame_data);
        // Disable and change CHEN (must not do this while sampling).
        set_ensamp_wm(1'b0, 4'd0);
        repeat (2000) @(posedge HF_CLK);
        write_reg_timed(6'h16, 8'h01, 50);
        set_ensamp_wm(1'b1, 4'd1);
        repeat (20000) @(posedge HF_CLK);
        read_fifo_frame(frame_data);
        // frame_data[15:0] is channel 0. Channels 1..7 must be zero if frame slots are cleared.
        if (frame_data[127:16] !== 112'h0) ok = 0;
        set_ensamp_wm(1'b0, 4'd0);
        fail_if(ok == 0, "S10 frame slot not cleared before write (stale disabled channels)");
        mark_test(10, ok);

        // S11: Disable mid-frame; requirement is "no stale data" (0x0000 words are valid).
        // Check:
        // - After disable, FIFO read returns all zeros (cleared session)
        // - After re-enable and some time, FIFO returns non-zero frame data again
        ok = 1;
        divider_config_8khz_continuous();
        write_reg_timed(6'h16, 8'hFF, 50);
        write_reg_timed(6'h1B, 8'h10, 50); // OSR=1
        set_ensamp_wm(1'b1, 4'd1);
        repeat (17) @(posedge SAMPLE_CLK_w); // mid-frame-ish
        set_ensamp_wm(1'b0, 4'd0);
        // Procedural rule: end transaction already occurred (CS high in write_reg_timed).
        repeat (5000) @(posedge HF_CLK);
        read_fifo_frame(frame_data);
        if (frame_data !== 128'h0) ok = 0;
        set_ensamp_wm(1'b1, 4'd1);
        // Wait for at least one frame (poll DATA_RDY as a proxy; watermark=1 here).
        i = 0;
        while ((dut.DATA_RDY !== 1'b1) && (i < 500000)) begin
            @(posedge HF_CLK);
            i = i + 1;
        end
        if (dut.DATA_RDY !== 1'b1) ok = 0;
        // FIFO readout is "one-behind": first RDDATA after (re)enable may return 0
        // and only becomes valid after the first FIFO_POP. Prime once, then read again.
        read_fifo_frame(frame_data); // prime (pop one frame, returned data may be stale/0)
        i = 0;
        while ((dut.DATA_RDY !== 1'b1) && (i < 500000)) begin
            @(posedge HF_CLK);
            i = i + 1;
        end
        if (dut.DATA_RDY !== 1'b1) ok = 0;
        read_fifo_frame(frame_data); // valid readback of previously popped frame
        if (frame_data === 128'h0) ok = 0;
        set_ensamp_wm(1'b0, 4'd0);
        fail_if(ok == 0, "S11 no-stale-data check failed across disable/re-enable");
        mark_test(11, ok);

        ok = 1;
        write_reg_timed(6'h16, 8'h01, 50);
        write_reg_timed(6'h1B, 8'h10, 50);
        set_ensamp_wm(1'b1, 4'd1);
        // At 8kHz SAMPLE_CLK, wait on SAMPLE_CLK edges (HF_CLK cycles are too short).
        repeat (3) @(posedge SAMPLE_CLK_w);
        sample_mark_a = sample_ctr;
        SCANEN = 1'b1;
        SCANMODE = 1'b1;
        repeat (3) @(posedge SAMPLE_CLK_w);
        sample_mark_b = sample_ctr;
        if (sample_mark_b <= sample_mark_a) ok = 0;
        SCANEN = 1'b0;
        SCANMODE = 1'b0;
        set_ensamp_wm(1'b0, 4'd0);
        fail_if(ok == 0, "S12 scan pins affected functional behavior");
        mark_test(12, ok);

        ok = 1;
        RESETN = 1'b0;
        repeat (6) @(posedge HF_CLK);
        RESETN = 1'b1;
        repeat (6) @(posedge HF_CLK);
        for (j = 0; j < 36; j = j + 1) begin
            read_reg_timed(j[5:0], 50, reg_readback);
            if (reg_readback !== 8'h00) ok = 0;
        end
        fail_if(ok == 0, "S13 register defaults are not all zero");
        mark_test(13, ok);

        // S14: Continuous sampling endurance (realistic rate; ensure no overflow under reasonable drain)
        // Aim (DIG-13/DIG-16/DIG-84): run for many frames, keep draining, and verify no FIFO overflow.
        ok = 1;
        divider_config_8khz_continuous();
        clear_status_bits(14'h3FFF);
        write_reg_timed(6'h16, 8'hFF, 50);
        write_reg_timed(6'h1B, 8'h10, 50); // OSR=1
        set_ensamp_wm(1'b1, 4'd1);
        // Prime the FIFO readout pipeline once (first read may return stale/0).
        stable = 0;
        i = 0;
        while ((stable == 0) && (i < 500000)) begin
            @(posedge HF_CLK);
            if (dut.DATA_RDY === 1'b1) begin
                // Require DATA_RDY to remain asserted across SAMPLE_CLK edges (avoid glitches/CDC lag)
                repeat (2) @(posedge SAMPLE_CLK_w);
                if (dut.DATA_RDY === 1'b1) stable = 1;
            end
            i = i + 1;
        end
        if ((stable == 0) && (ok == 1)) ok = 0;
        read_fifo_frame(frame_data); // prime pop (ignore content)

        // Drain 50 frames, paced by DATA_RDY. After each read, wait a few SAMPLE_CLK
        // edges so the read-pointer CDC settles before we look at DATA_RDY again.
        for (j = 0; j < 50; j = j + 1) begin
            // Wait for stable DATA_RDY assertion
            stable = 0;
            i = 0;
            while ((stable == 0) && (i < 500000)) begin
                @(posedge HF_CLK);
                if (dut.DATA_RDY === 1'b1) begin
                    repeat (2) @(posedge SAMPLE_CLK_w);
                    if (dut.DATA_RDY === 1'b1) stable = 1;
                end
                i = i + 1;
            end
            if ((stable == 0) && (ok == 1)) ok = 0;
            read_fifo_frame(frame_data);
            // Allow read_ptr CDC into SAMPLE_CLK domain to settle. Prefer to see
            // DATA_RDY deassert (FIFO emptied) before looping, but don't stall if
            // additional frames are already buffered.
            i = 0;
            while ((dut.DATA_RDY === 1'b1) && (i < 8)) begin
                @(posedge SAMPLE_CLK_w);
                i = i + 1;
            end
        end
        read_status(status_shadow);
        if ((status_shadow[9] !== 1'b0) && (ok == 1)) ok = 0; // FIFO overflow sticky flag must remain clear
        set_ensamp_wm(1'b0, 4'd0);
        fail_if(ok == 0, "S14 endurance overflow/stuck behavior failed");
        mark_test(14, ok);

        if (pad_errors != 0) error_count = error_count + 1;
        $display("===============================================");
        $display("Mock-Signoff Test Coverage Summary (S1..S14)");
        $display("===============================================");
        for (j = 1; j <= 14; j = j + 1) begin
            if (test_pass[j] == 1) begin
                pass_count = pass_count + 1;
                $display("S%0d : PASS", j);
            end else if (test_pass[j] == 2) begin
                skip_count = skip_count + 1;
                $display("S%0d : SKIP", j);
            end else begin
                $display("S%0d : FAIL", j);
                error_count = error_count + 1;
            end
        end
        $display("-----------------------------------------------");
        $display("PASS=%0d SKIP=%0d FAIL=%0d", pass_count, skip_count, error_count);
        if (error_count == 0) begin
            $display("PASS: tb_top_level_mock_signoff");
        end else begin
            $display("FAIL: tb_top_level_mock_signoff");
        end
        #1000;
        $stop;
    end

    initial begin
        // Endurance tests at 8kHz can take hundreds of milliseconds of sim time.
        #500000000;
        $display("ERROR: mock-signoff TB timeout");
        $stop;
    end

endmodule

