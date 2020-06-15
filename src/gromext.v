//--------------------------------------------------------------------------------
// gromext.vhd
//
// GROM memory implementation code.
//
// This file is part of the ep994a design, a TI-99/4A clone 
// designed by Erik Piehl in October 2016.
// Erik Piehl, Kauniainen, Finland, speccery@gmail.com
//
// This is copyrighted software.
// Please see the file LICENSE for license terms. 
//
// NO WARRANTY, THE SOURCE CODE IS PROVIDED "AS IS".
// THE SOURCE IS PROVIDED WITHOUT ANY GUARANTEE THAT IT WILL WORK 
// FOR ANY PARTICULAR USE. IN NO EVENT IS THE AUTHOR LIABLE FOR ANY 
// DIRECT OR INDIRECT DAMAGE CAUSED BY THE USE OF THE SOFTWARE.
//
// Synthesized with Xilinx ISE 14.7.
//--------------------------------------------------------------------------------
// Description: 	Implementation of GROM for external memory.
//						Basically here we map GROM accesses to external RAM addresses.
//						Since we're not using internal block RAM, we can use 8K
//						for each of the GROMs.
//						This is the address space layout for 20 bit addresses:
//						1 1 1 1 1 1 1 1 1 1
//                9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
//										          |<--- in grom addr  --->|
//	          				    |<->|	3 bit GROM chip select (0,1,2 are console in all bases)
//						    |<--->|			4 bit base select
//
//--------------------------------------------------------------------------------

module gromext(
  input wire [7:0] din,   // data in, write bus for addresses
  output wire [7:0] dout, // data out, read bus
  input wire clk,         
  input wire we,          // write enable, 1 cycle long
  input wire rd,          // read signal, may be up for multiple cycles
  output wire selected,   // High when this GROM is enabled during READ.
                          // When high, databus should be driven by data from addr below.
  output wire reg_out,    // When high, the GROM registers are read.
  input wire [4:0] mode,  // A5..A1 (4 bits for GROM base select, 1 bit for register select)
  input wire reset,       
  output wire [19:0] addr // 1 megabyte GROM address out
);

reg  [12:0] offset;
reg  [2:0]  grom_sel;  // top 3 bits of GROM address
wire [15:0] rom_addr;
reg  [3:0]  grom_base;
reg  [15:0] read_addr;
reg read_addr_refresh;
reg old_rd;
  wire  [12:0] next_offset = offset + 1;

  // assign selected = (/*grom_base == 4'h0 && */ grom_sel == 3'd0  && grom_sel == 3'd1  && grom_sel == 3'd2) 
  //  && rd == 1'b1 && mode[0] == 1'b0;
  assign selected = rd == 1'b1 && mode[0] == 1'b0;
  assign reg_out  = rd == 1'b1 && mode[0] == 1'b1;
  // Our GROMs cover all the bases currently.
  assign addr = {grom_base,grom_sel,offset};
  assign dout = read_addr[15:8];
  always @(posedge clk, posedge reset) begin
    if(reset == 1'b1) begin
      grom_sel <= 3'b000;
      read_addr_refresh <= 1'b0;
      offset <= {13{1'b0}};
    end else begin
      // we handle only two scenarios:
      // 	write to GROM address counter
      //		read from GROM data
      if(we == 1'b1 && mode[0] == 1'b1) begin
        // write to address counter
        offset[7:0] <= din;
        offset[12:8] <= offset[4:0];
        grom_sel <= offset[7:5];
        grom_base <= mode[4:1];
        read_addr_refresh <= 1'b1;
      end
      old_rd <= rd;
      if(old_rd == 1'b1 && rd == 1'b0) begin
        if(mode[0] == 1'b0) begin
          offset <= next_offset;
          read_addr_refresh <= 1'b1;
        end
        else begin
          // address byte read just finished
          read_addr[15:8] <= read_addr[7:0];
        end
      end
      if(read_addr_refresh == 1'b1) begin
        read_addr <= {grom_sel, next_offset };
        read_addr_refresh <= 1'b0;
      end
    end
  end


endmodule
