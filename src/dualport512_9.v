module dualport512_9 (
  // Port A
  input            clk_a,
  input            we_a,
  input [8:0]     addr_a,
  input [8:0]      din_a,
  // Port B
  input            clk_b,
  input [8:0]     addr_b,
  output reg [8:0] dout_b            
);

   reg [8:0] ram [0:511];

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
