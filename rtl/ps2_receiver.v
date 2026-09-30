module ps2_receiver (
    input  wire clk,        
    input  wire resetn,
    input  wire ps2_clk,
    input  wire ps2_data,
    output reg  [7:0] scan_code,
    output reg        scan_ready  
);
    // Synchronize ps2_clk into clk domain
    reg [2:0] ps2c_sync;
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            ps2c_sync <= 3'b111;
        else
            ps2c_sync <= {ps2c_sync[1:0], ps2_clk};
    end

    wire ps2c_fall = (ps2c_sync[2:1] == 2'b10);

    reg [3:0] bitcount;
    reg [10:0] shiftreg;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            bitcount   <= 4'd0;
            shiftreg   <= 11'd0;
            scan_code  <= 8'd0;
            scan_ready <= 1'b0;
        end else begin
            scan_ready <= 1'b0;
            if (ps2c_fall) begin
                shiftreg <= {ps2_data, shiftreg[10:1]};
                if (bitcount == 4'd10) begin
                   
                    bitcount  <= 4'd0;
                    scan_code <= shiftreg[8:1]; 
                    scan_ready <= 1'b1;
                end else begin
                    bitcount <= bitcount + 1'b1;
                end
            end
        end
    end
endmodule
