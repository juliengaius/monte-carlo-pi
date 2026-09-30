module hit_kernel_uq16_comb
(
    input wire [15:0] x_in, // unsigned 0.16 16 fractional bits
    input wire [15:0] y_in,   
    output wire inside // 1 if inside quarter circle
);
    // 16x16 -> 32
    wire [31:0] x2 = x_in * x_in; 
    wire [31:0] y2 = y_in * y_in; 

    // sum can be 33 bits (carry)
    wire [32:0] sum = {1'b0, x2} + {1'b0, y2};

    // 2^32 as 33-bit constant = 1 followed by 32 zeros 
    // this is the fixed-point value of 1.0 when x,y are 0.16 
    localparam [32:0] ONE_SQ = 33'h1_0000_0000; 

    assign inside = (sum <= ONE_SQ);
endmodule

