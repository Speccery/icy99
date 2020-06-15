//
// Simplistic 4096x16 RAM module
//
// This source code is public domain
//

module RAM(CLK, nCS, nWE, ADDR, DI, DO);

  // Port definition
  input CLK, nCS, nWE;
  input  [11:0] ADDR;
  input  [15:0] DI;
  output [15:0] DO;
  
  wire          CLK, nCS, nWE;
  wire   [11:0] ADDR;
  wire   [15:0] DI;
  reg    [15:0] DO;
  
  // Implementation
  reg [15:0] mem[1023:0]; // mem[4095:0];
  
  always @(posedge CLK)
  begin
    if (!nCS) begin
      if (!nWE) mem[ADDR[9:0]] <= DI;  // 11
    end
  end

  always @(posedge CLK)
  begin
    if (!nCS) begin
      DO <= mem[ADDR[11:0]];
    end
  end
 
endmodule
