module pi_divider #(
    parameter W = 32,
    parameter FBITS = 29
)(
    input  wire              clk,
    input  wire              resetn,
    input  wire              start,
    input  wire [W-1:0]      hits,
    input  wire [W-1:0]      total,
    output reg               busy,
    output reg               valid,
    output reg  [W+FBITS-1:0] pi_q
);

    localparam IDLE = 2'd0, PREP = 2'd1, RUN = 2'd2, DONE = 2'd3;
    reg [1:0] state, nstate;
	 reg [W+FBITS-1:0] numerator;
    reg [W-1:0] denom;


    always @(*) begin
        nstate = state;
        case (state)
            IDLE: if (start) nstate = PREP;
            PREP: nstate = RUN;
            RUN : nstate = DONE;
            DONE: nstate = IDLE;
				default: nstate = IDLE;
        endcase
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            busy  <= 1'b0;
            valid <= 1'b0;
            pi_q  <= {(W+FBITS){1'b0}};
            numerator <= {(W+FBITS){1'b0}};
            denom <= {W{1'b0}};      
        end else begin
            state <= nstate;
            valid <= 1'b0;

            case (nstate)
                IDLE: begin
                    busy <= 1'b0;
                end
                PREP: begin
                    busy      <= 1'b1;
                    numerator <= ({{FBITS{1'b0}}, hits} << 2) << FBITS;
                    denom     <= (total == 0) ? 1 : total;
                end
                RUN: begin
                    busy <= 1'b1;
						  pi_q <= numerator / denom; 	
					 end	
                DONE: begin       
                    busy <= 1'b0;
                    valid <= 1'b1;
                end
            endcase
        end
    end
endmodule
