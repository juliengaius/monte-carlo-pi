module hex_pi_driver #(
    parameter IN_W  = 61,
    parameter FBITS = 29          // fixed-point fractional bits
)(
    input  wire              clk,
    input  wire              resetn,
    input  wire              load,          // 1-cycle pulse
    input  wire [IN_W-1:0]   value_in,      // Q(3).FBITS fixed-point

    output reg               busy,
    output reg               valid,         // 1-cycle pulse when HEX updated

    // active-low 7-seg
    output reg  [6:0]        HEX5,
    output reg  [6:0]        HEX4,
    output reg  [6:0]        HEX3,
    output reg  [6:0]        HEX2,
    output reg  [6:0]        HEX1,
    output reg  [6:0]        HEX0,
    output reg               DP4            // decimal point between HEX4 & HEX3 (active high)
);

    localparam SCALE = 17'd100000;

    // mult result and 32-bit integer to convert
    reg [IN_W+17-1:0] mult_prod;
    reg [31:0]        bin_shift;

    // 6 decimal digits (BCD nibbles)
    reg [3:0] bcd5, bcd4, bcd3, bcd2, bcd1, bcd0;
    reg [5:0] dd_count;

    // FSM states
    localparam S_IDLE  = 2'd0;
    localparam S_MUL   = 2'd1;    // do multiply
    localparam S_PREP  = 2'd2;    // load bin_shift & clear BCD
    localparam S_SHIFT = 2'd3;    // double-dabble loop
    // OUT is folded into S_SHIFT termination + outputs

    reg [1:0] state, nstate;

    // 7-seg helper
    function [6:0] seg7;
        input [3:0] x;
        begin
            case (x)
                4'd0: seg7 = 7'b1000000;
                4'd1: seg7 = 7'b1111001;
                4'd2: seg7 = 7'b0100100;
                4'd3: seg7 = 7'b0110000;
                4'd4: seg7 = 7'b0011001;
                4'd5: seg7 = 7'b0010010;
                4'd6: seg7 = 7'b0000010;
                4'd7: seg7 = 7'b1111000;
                4'd8: seg7 = 7'b0000000;
                4'd9: seg7 = 7'b0010000;
                default: seg7 = 7'b1111111;
            endcase
        end
    endfunction

    // next-state logic
    always @* begin
        nstate = state;
        case (state)
            S_IDLE:  if (load)      nstate = S_MUL;
            S_MUL:                 nstate = S_PREP;
            S_PREP:                nstate = S_SHIFT;
            S_SHIFT: if (dd_count == 0) nstate = S_IDLE;
            default: nstate = S_IDLE;
        endcase
    end

    // sequential logic
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE;
            busy  <= 1'b0;
            valid <= 1'b0;

            HEX5 <= 7'b1111111;
            HEX4 <= 7'b1111111;
            HEX3 <= 7'b1111111;
            HEX2 <= 7'b1111111;
            HEX1 <= 7'b1111111;
            HEX0 <= 7'b1111111;
            DP4  <= 1'b0;

            mult_prod <= {(IN_W+17){1'b0}};
            bin_shift <= 32'd0;
            {bcd5,bcd4,bcd3,bcd2,bcd1,bcd0} <= 24'd0;
            dd_count <= 6'd0;
        end else begin
            state <= nstate;
            valid <= 1'b0;   // default

            case (state)
                // wait for new value
                S_IDLE: begin
                    busy <= 1'b0;
                    if (load) begin
                        busy      <= 1'b1;
                        mult_prod <= value_in * SCALE;   // compute value * 100000
                    end
                end

                // give multiply result one full cycle to settle
                S_MUL: begin
                    busy      <= 1'b1;
                    mult_prod <= mult_prod;              // hold
                end

                // load bin_shift, clear BCD, init loop counter
                S_PREP: begin
                    busy      <= 1'b1;
                    bin_shift <= mult_prod >> FBITS;     // Q(3).FBITS ? integer
                    {bcd5,bcd4,bcd3,bcd2,bcd1,bcd0} <= 24'd0;
                    dd_count <= 6'd32;                  // 32 bits in bin_shift
                end

                // double-dabble: 32 iterations
                S_SHIFT: begin
                    busy <= 1'b1;

                    if (dd_count != 0) begin
                        // add-3 to any digit ?5
                        if (bcd5 >= 5) bcd5 <= bcd5 + 3;
                        if (bcd4 >= 5) bcd4 <= bcd4 + 3;
                        if (bcd3 >= 5) bcd3 <= bcd3 + 3;
                        if (bcd2 >= 5) bcd2 <= bcd2 + 3;
                        if (bcd1 >= 5) bcd1 <= bcd1 + 3;
                        if (bcd0 >= 5) bcd0 <= bcd0 + 3;

                        // shift left {bcds, bin_shift} together
                        {bcd5,bcd4,bcd3,bcd2,bcd1,bcd0,bin_shift} <=
                        {bcd5,bcd4,bcd3,bcd2,bcd1,bcd0,bin_shift} << 1;

                        dd_count <= dd_count - 1'b1;

                        // when this was last iteration, update HEX outputs now
                        if (dd_count == 6'd1) begin
                            HEX5 <= seg7(bcd5);
                            HEX4 <= seg7(bcd4);
                            HEX3 <= seg7(bcd3);
                            HEX2 <= seg7(bcd2);
                            HEX1 <= seg7(bcd1);
                            HEX0 <= seg7(bcd0);
                            DP4  <= 1'b1;   // dot between HEX4 & HEX3
                            valid <= 1'b1;
                            busy  <= 1'b0;
                        end
                    end
                end
            endcase
        end
    end

endmodule

