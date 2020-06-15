// dualport_par.v
// EP (C) 2019-11-02
// Simple dual port memory with separate read and write ports and configurable depth and width.
// For example a simple 1K 8-bit wide RAM:
//  dualport_par #(8, 10) ram1k (...)
//
module dualport_par
#(parameter WIDTH=9,  // 9 bits of data width
  parameter DEPTH=9)  // 9 bits of address
(
  // Port A
  input            clk_a,
  input            we_a,
  input [DEPTH-1:0] addr_a,
  input [WIDTH-1:0] din_a,
  // Port B
  input            clk_b,
  input [DEPTH-1:0]      addr_b,
  output reg [WIDTH-1:0] dout_b            
);

  parameter RAM_RANGE = 1 << DEPTH;
   reg [WIDTH-1:0] ram [0:RAM_RANGE-1];

   always @(posedge clk_a)
     begin
        if (we_a)
          ram[addr_a] <= din_a;
     end

   always @(posedge clk_b)
     begin
        dout_b <= ram[addr_b];
     end
   
endmodule
