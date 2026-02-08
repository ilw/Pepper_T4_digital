`timescale 1ns / 1ps

module Status_Monitor (
    input wire NRST_sync,
    input wire HF_CLK,
    input wire ENSAMP_sync,
    input wire [15:0] CRCCFG,
    input wire [7:0] AFERSTCH_sync,
    input wire FIFO_OVERFLOW_sync,
    input wire FIFO_UNDERFLOW_sync,
    input wire ADCOVERFLOW,
    input wire [7:0] SATDETECT_sync,
    input wire status_clr_pulse,
    input wire [13:0] status_clr_mask,

    output wire [13:0] status
);

    // Status bit registers
    reg ensamp_flag;
    reg cfgchng_flag;
    reg analog_reset_flag;
    reg fifo_udf_flag;
    reg fifo_ovf_flag;
    reg adc_ovf_flag;
    reg [7:0] sat_flags;

    // Previous CRCCFG for change detection
    reg [15:0] crccfg_prev;
    integer i;

    always @(posedge HF_CLK or negedge NRST_sync) begin
        if (!NRST_sync) begin
            ensamp_flag <= 1'b0;
            cfgchng_flag <= 1'b0;
            analog_reset_flag <= 1'b0;
            fifo_udf_flag <= 1'b0;
            fifo_ovf_flag <= 1'b0;
            adc_ovf_flag <= 1'b0;
            sat_flags <= 8'b0;
            crccfg_prev <= 16'b0;
        end else begin
            // Clear-on-write (W1C) handling
            // Clear first, then set logic below has priority if an event occurs same cycle.
            if (status_clr_pulse) begin
                if (status_clr_mask[12]) cfgchng_flag <= 1'b0;
                if (status_clr_mask[11]) analog_reset_flag <= 1'b0;
                if (status_clr_mask[10]) fifo_udf_flag <= 1'b0;
                if (status_clr_mask[9])  fifo_ovf_flag <= 1'b0;
                if (status_clr_mask[8])  adc_ovf_flag <= 1'b0;
                for (i = 0; i < 8; i = i + 1) begin
                    if (status_clr_mask[i]) sat_flags[i] <= 1'b0;
                end
            end

            // ENSAMP is a state indicator (level), not sticky
            ensamp_flag <= ENSAMP_sync;

            // CFGCHNG: set when CRCCFG changes, sticky until MCU clears
            crccfg_prev <= CRCCFG;
            if (CRCCFG != crccfg_prev) begin
                cfgchng_flag <= 1'b1;
            end

            // ANALOG_RESET: set if any AFERSTCH bit high, sticky until MCU clears
            if (|AFERSTCH_sync) begin
                analog_reset_flag <= 1'b1;
            end

            // FIFO_UDF: sticky until MCU clears
            if (FIFO_UNDERFLOW_sync) begin
                fifo_udf_flag <= 1'b1;
            end

            // FIFO_OVF: sticky until MCU clears
            if (FIFO_OVERFLOW_sync) begin
                fifo_ovf_flag <= 1'b1;
            end

            // ADC_OVF: sticky until MCU clears
            if (ADCOVERFLOW) begin
                adc_ovf_flag <= 1'b1;
            end

            // SAT[7:0]: each bit corresponds to SATDETECT_sync bit, sticky until MCU clears
            for (i = 0; i < 8; i = i + 1) begin
                if (SATDETECT_sync[i]) begin
                    sat_flags[i] <= 1'b1;
                end
            end
        end
    end

    // Assemble status word: [13:ENSAMP, 12:CFGCHNG, 11:ANALOG_RESET, 10:FIFO_UDF, 9:FIFO_OVF, 8:ADC_OVF, 7:0:SAT]
    assign status = {ensamp_flag, cfgchng_flag, analog_reset_flag, fifo_udf_flag, fifo_ovf_flag, adc_ovf_flag, sat_flags};

endmodule

