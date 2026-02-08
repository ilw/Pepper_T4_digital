`timescale 1ns / 1ps

// Simple combinational mux model for integration testing.
// - Selects one of CH0..CH7 based on one-hot ATMCHSEL[7:0]
// - When TEMPSEL=1, selects TEMP1_IN (TEMP2_IN kept for legacy compatibility)
module dummy_Mux (
    input  wire [7:0]  ATMCHSEL,
    input  wire        TEMPSEL,
    input  wire [15:0] CH0_IN,
    input  wire [15:0] CH1_IN,
    input  wire [15:0] CH2_IN,
    input  wire [15:0] CH3_IN,
    input  wire [15:0] CH4_IN,
    input  wire [15:0] CH5_IN,
    input  wire [15:0] CH6_IN,
    input  wire [15:0] CH7_IN,
    input  wire [15:0] TEMP1_IN,
    input  wire [15:0] TEMP2_IN,
    output reg  [15:0] MUX_OUT
);

    always @(*) begin
        if (TEMPSEL) begin
            MUX_OUT = TEMP1_IN;
        end else begin
            case (1'b1)
                ATMCHSEL[0]: MUX_OUT = CH0_IN;
                ATMCHSEL[1]: MUX_OUT = CH1_IN;
                ATMCHSEL[2]: MUX_OUT = CH2_IN;
                ATMCHSEL[3]: MUX_OUT = CH3_IN;
                ATMCHSEL[4]: MUX_OUT = CH4_IN;
                ATMCHSEL[5]: MUX_OUT = CH5_IN;
                ATMCHSEL[6]: MUX_OUT = CH6_IN;
                ATMCHSEL[7]: MUX_OUT = CH7_IN;
                default:     MUX_OUT = 16'h0000;
            endcase
        end
    end

    // Silence unused legacy port warning
    wire _unused_temp2 = ^TEMP2_IN;

endmodule

