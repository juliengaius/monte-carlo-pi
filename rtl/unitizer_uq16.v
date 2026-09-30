module unitizer_uq16
(
    input wire clk,
    input wire resetn,
    input wire load,
    input wire [31:0] rx,
    input wire [31:0] ry,
    output reg [15:0] x_uq16,
    output reg [15:0] y_uq16,
    output reg valid
);
    wire [15:0] x_raw = rx[31:16];
    wire [15:0] y_raw = ry[31:16];

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            x_uq16 <= 16'd0;
            y_uq16 <= 16'd0;
            valid  <= 1'b0;
        end else begin
            valid <= 1'b0; 
            if (load) begin
                x_uq16 <= x_raw;
                y_uq16 <= y_raw;
                valid  <= 1'b1;
            end
        end
    end
endmodule

// take the top 16 bits of the randx randy to lower the precision, take it as a fixed point 
// fraction where itis 0.<15:0> then calculate considering that it is a fixed point fraction
// in the hit kernel module

