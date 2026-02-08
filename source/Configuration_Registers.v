`timescale 1ns / 1ps

module Configuration_Registers (
    input wire NRST,
    input wire SCK,
    input wire [5:0] reg_addr,
    input wire [7:0] reg_value,
    input wire wr_en,

    output wire [511:0] cfg_data
);

    // 36 8-bit registers covering addresses 0x00 to 0x23
    reg [7:0] regs [0:35];
    integer i;

    always @(posedge SCK or negedge NRST) begin
        if (!NRST) begin
            for (i = 0; i < 36; i = i + 1) begin
                regs[i] <= 8'b0;
            end
        end else if (wr_en && (reg_addr < 36)) begin
            regs[reg_addr] <= reg_value;
        end
    end

    // Map registers to output
    genvar j;
    generate
        for (j = 0; j < 36; j = j + 1) begin : output_map
            assign cfg_data[j*8 +: 8] = regs[j];
        end
    endgenerate

    // Tie unused upper bits to low
    assign cfg_data[511:288] = 224'b0;

endmodule
