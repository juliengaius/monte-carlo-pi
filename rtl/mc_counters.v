module mc_counters
(
    input  wire clk,
    input  wire resetn,

    input  wire total_inc,
    input  wire inside_inc,

    output reg [31:0] total_points,
    output reg [31:0] inside_points
);
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            total_points  <= 32'b0;
            inside_points <= 32'b0;
        end else begin
            if (total_inc)  
                total_points <= total_points + 1;
            if (inside_inc) 
                inside_points <= inside_points + 1;
        end
    end
endmodule
