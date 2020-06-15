module dualport4k
(
  // Port A
  input            clk_a,
  input            we_a,
  input [11:0]     addr_a,
  input [7:0]      din_a,
  // Port B
  input            clk_b,
  input [11:0]     addr_b,
  output reg [7:0] dout_b            
);

   reg [7:0] ram [0:4095];

   // EP for simulation zero out the memory
   reg [11:0] myaddr;
   initial begin
    //  $display("RAM clear start");
    //  for(myaddr=0; myaddr<4095; myaddr=myaddr+1) begin
    //     ram[myaddr] <= 0;
    //  end
    //  $display("RAM cleared");
    ram[0] <= 0;
    ram[1] <= 1;
    ram[16] <= 2;
    ram[32] <= 0;
    ram[33] <= 1;
    ram[34] <= 2;
    ram[32*12] <= 2;

    ram[12'h380] <= 8'h17;  // color table entries
    ram[12'h381] <= 8'h4a;  // some more

    ram[12'h800] <= 8'h00;  // character definition 0
    ram[12'h801] <= 8'h3C;  
    ram[12'h802] <= 8'h42;  
    ram[12'h803] <= 8'h42;  
    ram[12'h804] <= 8'h7e;  
    ram[12'h805] <= 8'h42;  
    ram[12'h806] <= 8'h42;  
    ram[12'h807] <= 8'h42;  

    ram[12'h808] <= 8'h00;  // character definition 1
    ram[12'h809] <= 8'h38;  
    ram[12'h80a] <= 8'h44;  
    ram[12'h80b] <= 8'h44;  
    ram[12'h80c] <= 8'h38;  
    ram[12'h80d] <= 8'h10;  
    ram[12'h80e] <= 8'h38;  
    ram[12'h80f] <= 8'h10;  

    // character definition 2
    ram[12'h810] <= 8'b00000000;
    ram[12'h811] <= 8'b01000001;
    ram[12'h812] <= 8'b00100010;
    ram[12'h813] <= 8'b01111111;
    ram[12'h814] <= 8'b01011101;
    ram[12'h815] <= 8'b01111111;
    ram[12'h816] <= 8'b00111110;
    ram[12'h817] <= 8'b01000001;
   end

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
