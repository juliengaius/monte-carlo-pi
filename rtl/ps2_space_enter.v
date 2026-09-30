module ps2_space_enter (
    input  wire clk,
    input  wire resetn,
    input  wire [7:0] scan_code,
    input  wire       scan_ready,
    output reg        space_pulse,
    output reg        enter_pulse
);
    reg break_flag;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            break_flag  <= 1'b0;
            space_pulse <= 1'b0;
            enter_pulse <= 1'b0;
        end else begin
            space_pulse <= 1'b0;
            enter_pulse <= 1'b0;

            if (scan_ready) begin
                if (scan_code == 8'hF0) begin
                    // next code is a BREAK
                    break_flag <= 1'b1;
                end else begin
                    if (!break_flag) begin
                        // MAKE code
                        if (scan_code == 8'h52) begin
                            space_pulse <= 1'b1;
                        end else if (scan_code == 8'h64) begin
                            enter_pulse <= 1'b1;
                        end
                    end
                    // clear break flag after non-F0
                    break_flag <= 1'b0;
                end
            end
        end
    end
endmodule
