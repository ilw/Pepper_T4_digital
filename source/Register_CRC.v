`timescale 1ns / 1ps

module Register_CRC (
    input wire [511:0] cfg_data,
    output wire [15:0] CRCCFG
);

    // 16-bit XOR checksum: each bit XORs every 16th input bit
    // This provides good error detection with minimal area
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : checksum_gen
            wire [31:0] bit_slice;
            
            // Extract every 16th bit starting from position i
            assign bit_slice[0]  = cfg_data[i + 0*16];
            assign bit_slice[1]  = cfg_data[i + 1*16];
            assign bit_slice[2]  = cfg_data[i + 2*16];
            assign bit_slice[3]  = cfg_data[i + 3*16];
            assign bit_slice[4]  = cfg_data[i + 4*16];
            assign bit_slice[5]  = cfg_data[i + 5*16];
            assign bit_slice[6]  = cfg_data[i + 6*16];
            assign bit_slice[7]  = cfg_data[i + 7*16];
            assign bit_slice[8]  = cfg_data[i + 8*16];
            assign bit_slice[9]  = cfg_data[i + 9*16];
            assign bit_slice[10] = cfg_data[i + 10*16];
            assign bit_slice[11] = cfg_data[i + 11*16];
            assign bit_slice[12] = cfg_data[i + 12*16];
            assign bit_slice[13] = cfg_data[i + 13*16];
            assign bit_slice[14] = cfg_data[i + 14*16];
            assign bit_slice[15] = cfg_data[i + 15*16];
            assign bit_slice[16] = cfg_data[i + 16*16];
            assign bit_slice[17] = cfg_data[i + 17*16];
            assign bit_slice[18] = cfg_data[i + 18*16];
            assign bit_slice[19] = cfg_data[i + 19*16];
            assign bit_slice[20] = cfg_data[i + 20*16];
            assign bit_slice[21] = cfg_data[i + 21*16];
            assign bit_slice[22] = cfg_data[i + 22*16];
            assign bit_slice[23] = cfg_data[i + 23*16];
            assign bit_slice[24] = cfg_data[i + 24*16];
            assign bit_slice[25] = cfg_data[i + 25*16];
            assign bit_slice[26] = cfg_data[i + 26*16];
            assign bit_slice[27] = cfg_data[i + 27*16];
            assign bit_slice[28] = cfg_data[i + 28*16];
            assign bit_slice[29] = cfg_data[i + 29*16];
            assign bit_slice[30] = cfg_data[i + 30*16];
            assign bit_slice[31] = cfg_data[i + 31*16];
            
            // XOR all bits together
            assign CRCCFG[i] = ^bit_slice;
        end
    endgenerate

endmodule
