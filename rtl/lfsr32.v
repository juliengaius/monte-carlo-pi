module lfsr32
#(
    //override this per instance
    parameter [31:0] RESET_SEED = 32'h0000_0001
)
(
    input wire clk,
    input wire resetn,
    input wire enable, // this is currently always written to 1 
    output reg  [31:0] state
);
    // taps: [31], [21], [1], [0] 
    wire new_bit = state[31] ^ state[21] ^ state[1] ^ state[0];

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            // on reset, go to the chosen seed once
            state <= RESET_SEED;
        end else if (enable) begin
            // otherwise just shift forever
            state <= {state[30:0], new_bit};
        end
    end
endmodule
