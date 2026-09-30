// Stand-in for object_mem.v in simulation only.
// The real module wraps Intel's altsyncram ROM, which Icarus Verilog can't
// simulate. Sprite pixel colours don't affect any control timing or the
// Monte Carlo datapath, so a registered 1-cycle-latency ROM that returns a
// constant non-black pixel is enough for functional and timing checks.
module object_mem (address, clock, q);
    parameter n = 3;
    parameter Mn = 6;
    parameter INIT_FILE = "";

    input  wire [Mn-1:0] address;
    input  wire          clock;
    output reg  [n-1:0]  q;

    always @(posedge clock) q <= {n{1'b1}};
endmodule
