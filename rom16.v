// rom16.v
// EP (C) 2019-11-19
// A simple ROM with init file support.

module rom16
#(parameter WIDTH=8,  // 9 bits of data width
  parameter DEPTH=9,
  parameter RANGE=512,
  parameter INITFILE="roms/zeros256.mem")  // 9 bits of address
(
  input            clk,
  input [DEPTH-1:0] addr,
  output reg [WIDTH-1:0] dout,
);

   reg [WIDTH-1:0] rom [0:RANGE-1];

   always @(posedge clk)
     begin
        dout <= rom[addr];
     end
   
    initial begin
        $readmemh(INITFILE, rom);
    end
endmodule
