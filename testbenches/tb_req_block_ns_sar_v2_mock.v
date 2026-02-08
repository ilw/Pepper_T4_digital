`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Unit testbench for the behavioral ADC mock (`ns_sar_v2` in `ns_sar_v2_mock.v`)
//
// Goals:
// - iverilog/cadence friendly (no SystemVerilog)
// - sanity-check DONE timing for SAR (OSR=0) and NS (OSR>0) modes
// - verify the immediate startup DONE on first active cycle (NS mode)
// - verify steady-state DONE period = 4*OSR+2 (NS mode)
// - sanity-check RESULT changes over time
//
// Expected behavior (matching real ADC netlist):
// - SAR mode (OSR=0): DONE stays high after reset deassert; RESULT each clk.
// - NS mode (OSR>0): Startup DONE on 1st active posedge. Then DONE pulses
//   every (4*OSR+2) cycles. DONE is 1-cycle delayed from internal trigger
//   (inherent in NBA scheduling, same as real ADC's registered CIC_DONE).
//////////////////////////////////////////////////////////////////////////////////

module tb_req_block_ns_sar_v2_mock;

    reg         SAMPLE_CLK;
    reg         nARST;
    reg         nARST_cmd;   // registered control for nARST (TB-side)
    reg  [3:0]  OSR;
    reg  [3:0]  GAIN;

    wire [15:0] RESULT;
    wire        DONE;
    wire        OVERFLOW;

    // Unused inputs
    reg ANALOG_ENABLE, CHP_EN, DWA_EN, MES_EN;
    reg EXT_CLK, EXT_CLK_EN;
    reg DONE_OVERRIDE, DONE_OVERRIDE_VAL;
    reg ANALOG_RESET_OVERRIDE, ANALOG_RESET_OVERRIDE_VAL;
    reg [2:0] DIGITAL_DEBUG_SELECT, ANALOG_TEST_SELECT;
    reg [7:0] ADC_SPARE;
    reg VIP, VIN, REFP, REFN, REFC, IBIAS_500N_PTAT;
    reg DVDD, DGND;

`ifdef CADENCE
    initial begin
        $shm_open("waves.shm");
        $shm_probe("ASM");
    end
`else
    initial begin
        $dumpfile("simulation/tb_req_block_ns_sar_v2_mock.vcd");
        $dumpvars(0, tb_req_block_ns_sar_v2_mock);
    end
`endif

    // 10MHz clock
    initial begin
        SAMPLE_CLK = 0;
        forever #50 SAMPLE_CLK = ~SAMPLE_CLK;
    end

    // Requirement: nARST is synchronous to posedge SAMPLE_CLK.
    // Implement as a registered signal in the TB to avoid #delays and races.
    always @(posedge SAMPLE_CLK) begin
        nARST <= nARST_cmd;
    end

    // DUT (mock)
    ns_sar_v2 dut (
        .SAMPLE_CLK(SAMPLE_CLK),
        .nARST(nARST),
        .OSR(OSR),
        .GAIN(GAIN),
        .ANALOG_ENABLE(ANALOG_ENABLE),
        .CHP_EN(CHP_EN),
        .DWA_EN(DWA_EN),
        .MES_EN(MES_EN),
        .EXT_CLK(EXT_CLK),
        .EXT_CLK_EN(EXT_CLK_EN),
        .DONE_OVERRIDE(DONE_OVERRIDE),
        .DONE_OVERRIDE_VAL(DONE_OVERRIDE_VAL),
        .ANALOG_RESET_OVERRIDE(ANALOG_RESET_OVERRIDE),
        .ANALOG_RESET_OVERRIDE_VAL(ANALOG_RESET_OVERRIDE_VAL),
        .DIGITAL_DEBUG_SELECT(DIGITAL_DEBUG_SELECT),
        .ANALOG_TEST_SELECT(ANALOG_TEST_SELECT),
        .ADC_SPARE(ADC_SPARE),
        .VIP(VIP),
        .VIN(VIN),
        .REFP(REFP),
        .REFN(REFN),
        .REFC(REFC),
        .IBIAS_500N_PTAT(IBIAS_500N_PTAT),
        .DVDD(DVDD),
        .DGND(DGND),
        .RESULT(RESULT),
        .DONE(DONE),
        .OVERFLOW(OVERFLOW),
        .ANALOG_TEST(),
        .DIGITAL_DEBUG()
    );

    integer errors;

    // ==============================================================
    // Reference model for DONE timing (matches the mock's intent)
    // This lets us assert: DONE must *only* go high when expected.
    //
    // The mock now produces a combinational startup DONE on the very
    // first active posedge after nARST deasserts (NS mode only).
    // The startup pulse is visible in the active region but cleared
    // by NBA in the same delta, so the #0 post-NBA checker cannot
    // see it.  We use a dedicated active-region flag to track it.
    // ==============================================================
    reg [5:0] ref_cycle_count;
    reg       ref_done_ns;
    reg       ref_first_conv;

    wire ref_sar_mode = (OSR == 4'd0);
    wire [5:0] ref_conv_len = ref_sar_mode ? 6'd1 : ({OSR, 2'b00} + 6'd2);
    wire ref_startup_done = ref_first_conv & ~ref_sar_mode;

    always @(posedge SAMPLE_CLK or negedge nARST) begin
        if (!nARST) begin
            ref_cycle_count <= 6'd0;
            ref_done_ns     <= 1'b0;
            ref_first_conv  <= 1'b1;
        end else if (ref_sar_mode) begin
            // In SAR mode, DONE is a constant 1. Keep NS state cleared to
            // avoid any spurious pulse when OSR changes 0->nonzero.
            ref_cycle_count <= 6'd0;
            ref_done_ns     <= 1'b0;
            ref_first_conv  <= 1'b0;
        end else begin
            ref_done_ns    <= 1'b0;
            ref_first_conv <= 1'b0;
            if (ref_cycle_count == (ref_conv_len - 6'd1)) begin
                ref_cycle_count <= 6'd0;
                ref_done_ns     <= 1'b1;
            end else begin
                ref_cycle_count <= ref_cycle_count + 6'd1;
            end
        end
    end

    // Continuous checker for DONE on every posedge.
    //
    // The #0 delay puts us in the inactive region (after active, before NBA).
    // At the startup posedge, both mock's first_conv and ref_first_conv are
    // still 1 (NBA hasn't cleared them yet), so the combinational
    // startup_done and ref_startup_done are both visible.  We include
    // ref_startup_done in the expected DONE value so the check passes at
    // startup and falls back to ref_done_ns for steady-state.
    always @(posedge SAMPLE_CLK) begin
        #0;
        if (!nARST) begin
            if (DONE !== 1'b0) begin
                $display("ERROR: DONE must be low during reset time=%t", $time);
                errors = errors + 1;
            end
        end else begin
            if (ref_sar_mode) begin
                if (DONE !== 1'b1) begin
                    $display("ERROR: SAR mode DONE must be high time=%t", $time);
                    errors = errors + 1;
                end
            end else begin
                // Expected: steady-state done_reg OR combinational startup pulse
                if (DONE !== (ref_done_ns | ref_startup_done)) begin
                    $display("ERROR: NS mode DONE mismatch exp=%b got=%b OSR=%0d time=%t",
                             (ref_done_ns | ref_startup_done), DONE, OSR, $time);
                    errors = errors + 1;
                end
            end
        end
    end

    // Also check immediately on async reset assertion.
    always @(negedge nARST) begin
        #0;
        if (DONE !== 1'b0) begin
            $display("ERROR: DONE must be low on reset assertion time=%t", $time);
            errors = errors + 1;
        end
    end

    task wait_clks;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge SAMPLE_CLK);
        end
    endtask

    // Compute conv_len = 2 + 4*OSR (for OSR>0). OSR=0 is SAR bypass.
    function integer conv_len_from_osr;
        input [3:0] osr;
        begin
            if (osr == 4'd0)
                conv_len_from_osr = 1;
            else
                conv_len_from_osr = 2 + (osr * 4);
        end
    endfunction

    // Change OSR only while sampling is stopped (nARST=0).
    // Requirement: nARST transitions must be synchronous to posedge SAMPLE_CLK.
    task stop_sampling;
        begin
            nARST_cmd = 1'b0;
            wait_clks(1); // allow registered nARST to take effect
        end
    endtask

    task start_sampling_with_osr;
        input [3:0] new_osr;
        begin
            // Ensure OSR updates while in reset (nARST low)
            nARST_cmd = 1'b0;
            wait_clks(1);
            OSR = new_osr;
            wait_clks(1);
            nARST_cmd = 1'b1;
            wait_clks(1); // allow registered nARST to take effect
        end
    endtask

    // ==============================================================
    // Check that the startup DONE fires on the first active posedge.
    // Must be called immediately after start_sampling_with_osr()
    // for an NS mode OSR.  Checks in the active region (no #0).
    // ==============================================================
    task check_startup_done;
        input [3:0] osr;
        begin
            @(posedge SAMPLE_CLK);   // First active posedge for the DUT
            // Active region: first_conv still 1, startup_done should be high
            if (DONE !== 1'b1) begin
                $display("ERROR: OSR=%0d startup DONE not asserted on first active cycle time=%t", osr, $time);
                errors = errors + 1;
            end else begin
                $display("  OSR=%0d startup DONE asserted on first active cycle — OK (time=%t)", osr, $time);
            end
            // After NBA in this cycle, first_conv clears and DONE should drop
            @(posedge SAMPLE_CLK);
            #0;
            if (DONE !== 1'b0) begin
                $display("ERROR: OSR=%0d DONE still high 1 cycle after startup time=%t", osr, $time);
                errors = errors + 1;
            end
        end
    endtask

    // Measure cycles between DONE pulses (NS mode)
    task measure_done_period;
        output integer period;
        integer c;
        begin
            // wait for first pulse
            while (DONE !== 1'b1) @(posedge SAMPLE_CLK);
            // now count until next pulse
            c = 0;
            @(posedge SAMPLE_CLK);
            while (DONE !== 1'b1) begin
                c = c + 1;
                @(posedge SAMPLE_CLK);
            end
            period = c + 1; // include the cycle we just waited
        end
    endtask

    // For NS mode: verify N consecutive conversions.
    // Checks:
    // - We observe N DONE pulses
    // - Spacing between pulses equals expected conv_len
    // - RESULT changes on each DONE (basic sanity)
    task check_n_consecutive_samples_ns;
        input [3:0] osr;
        input integer n;
        integer i;
        integer p;
        integer expected;
        reg [15:0] r_prev;
        reg [15:0] r_now;
        begin
            expected = conv_len_from_osr(osr); // for osr>0: 2+4*osr

            // Wait for the first DONE pulse
            while (DONE !== 1'b1) @(posedge SAMPLE_CLK);
            r_prev = RESULT;

            // For remaining samples, check period and result update
            for (i = 1; i < n; i = i + 1) begin
                measure_done_period(p);
                if (p != expected) begin
                    $display("ERROR: OSR=%0d expected DONE period %0d, got %0d (sample %0d)", osr, expected, p, i);
                    errors = errors + 1;
                end

                // At this point we are on a DONE pulse cycle again.
                r_now = RESULT;
                if (r_now === r_prev) begin
                    $display("ERROR: OSR=%0d RESULT did not change on DONE (sample %0d) val=0x%h time=%t",
                             osr, i, r_now, $time);
                    errors = errors + 1;
                end
                r_prev = r_now;
            end

            $display("  OSR=%0d: observed %0d consecutive DONE pulses — OK", osr, n);
        end
    endtask

    initial begin
        errors = 0;

        // default unused inputs
        ANALOG_ENABLE = 0; CHP_EN = 0; DWA_EN = 0; MES_EN = 0;
        EXT_CLK = 0; EXT_CLK_EN = 0;
        DONE_OVERRIDE = 0; DONE_OVERRIDE_VAL = 0;
        ANALOG_RESET_OVERRIDE = 0; ANALOG_RESET_OVERRIDE_VAL = 0;
        DIGITAL_DEBUG_SELECT = 0; ANALOG_TEST_SELECT = 0;
        ADC_SPARE = 0;
        VIP = 0; VIN = 0; REFP = 0; REFN = 0; REFC = 0; IBIAS_500N_PTAT = 0;
        DVDD = 1; DGND = 0;

        // reset
        nARST_cmd = 0;
        nARST = 0;
        OSR   = 0;
        GAIN  = 4'hF;
        // Release reset synchronously
        wait_clks(2);
        nARST_cmd = 1;
        wait_clks(2);

        // ==============================================================
        // Test 1: SAR mode (OSR=0) — DONE high, RESULT changes each cycle
        // ==============================================================
        $display("=== Test 1: SAR mode (OSR=0) ===");
        // Ensure clean entry
        stop_sampling();
        OSR  = 4'd0;
        GAIN = 4'hF;
        start_sampling_with_osr(4'd0);
        wait_clks(2);

        if (DONE !== 1'b1) begin
            $display("ERROR: SAR mode DONE not high");
            errors = errors + 1;
        end

        begin : sar_result_check
            reg [15:0] r0, r1;
            r0 = RESULT;
            wait_clks(1);
            r1 = RESULT;
            if (r1 === r0) begin
                $display("ERROR: SAR mode RESULT did not change (r0=0x%h r1=0x%h)", r0, r1);
                errors = errors + 1;
            end else begin
                $display("  SAR mode RESULT changes (r0=0x%h r1=0x%h) — OK", r0, r1);
            end
        end

        // Stop sampling before changing OSR (matches intended real usage)
        $display("  Stopping sampling before OSR change (nARST=0)");
        stop_sampling();

        // ==============================================================
        // Test 2: NS mode (OSR=1) — startup DONE + period 6 cycles
        // ==============================================================
        $display("=== Test 2: NS mode (OSR=1) ===");
        OSR  = 4'd1;               // conv_len = 4*1+2 = 6
        GAIN = 4'hF;
        start_sampling_with_osr(4'd1);
        // Verify the immediate startup DONE on first active cycle
        check_startup_done(4'd1);

        begin : ns_done_period
            integer p;
            measure_done_period(p);
            if (p != 6) begin
                $display("ERROR: OSR=1 expected DONE period 6, got %0d", p);
                errors = errors + 1;
            end else begin
                $display("  OSR=1 DONE period = %0d — OK", p);
            end
        end

        // Requirement: do 3 consecutive samples at this OSR
        check_n_consecutive_samples_ns(4'd1, 3);

        // Stop sampling before changing OSR again
        $display("  Stopping sampling before OSR change (nARST=0)");
        stop_sampling();

        // ==============================================================
        // Test 3: NS mode (OSR=4) — startup DONE + period 18 cycles
        // ==============================================================
        $display("=== Test 3: NS mode (OSR=4) ===");
        OSR  = 4'd4;               // conv_len = 4*4+2 = 18
        GAIN = 4'hF;
        start_sampling_with_osr(4'd4);
        // Verify the immediate startup DONE on first active cycle
        check_startup_done(4'd4);

        begin : ns_done_period2
            integer p2;
            measure_done_period(p2);
            if (p2 != 18) begin
                $display("ERROR: OSR=4 expected DONE period 18, got %0d", p2);
                errors = errors + 1;
            end else begin
                $display("  OSR=4 DONE period = %0d — OK", p2);
            end
        end

        // Requirement: do 3 consecutive samples at this OSR
        check_n_consecutive_samples_ns(4'd4, 3);

        // ==============================================================
        // Test 4: OSR change while nARST high must not cause DONE glitch
        // (this is the specific failure mode you observed)
        // ==============================================================
        $display("=== Test 4: Live OSR change (no reset) — no DONE glitch ===");
        stop_sampling();
        OSR = 4'd0;
        start_sampling_with_osr(4'd0);
        wait_clks(3);

        // Change OSR while keeping nARST high (nARST transitions remain posedge-synchronous)
        // (OSR itself is allowed to change asynchronously here for this test case.)
        @(posedge SAMPLE_CLK);
        OSR = 4'd1;

        // In NS mode, DONE must now follow the NS pattern (and not stay high)
        wait_clks(2);

        $display("========================================");
        if (errors == 0)
            $display("tb_req_block_ns_sar_v2_mock PASSED (0 errors)");
        else
            $display("tb_req_block_ns_sar_v2_mock FAILED (%0d errors)", errors);
        $display("========================================");

        $stop;
    end

endmodule

