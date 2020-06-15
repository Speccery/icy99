// File src/spi_slave.vhd translated with vhd2vl v3.0 VHDL to Verilog RTL translator
// vhd2vl settings:
//  * Verilog Module Declaration Style: 2001

// vhd2vl is Free (libre) Software:
//   Copyright (C) 2001 Vincenzo Liguori - Ocean Logic Pty Ltd
//     http://www.ocean-logic.com
//   Modifications Copyright (C) 2006 Mark Gonzales - PMC Sierra Inc
//   Modifications (C) 2010 Shankar Giri
//   Modifications Copyright (C) 2002-2017 Larry Doolittle
//     http://doolittle.icarus.com/~larry/vhd2vl/
//   Modifications (C) 2017 Rodrigo A. Melo
//
//   vhd2vl comes with ABSOLUTELY NO WARRANTY.  Always check the resulting
//   Verilog for correctness, ideally with a formal verification tool.
//
//   You are welcome to redistribute vhd2vl under certain conditions.
//   See the license (GPLv2) file included with the source for details.

// The result of translation follows.  Its copyright status should be
// considered unchanged from the original VHDL.

//--------------------------------------------------------------------------------
// Company: 
// Engineer: Erik Piehl
// 
// Create Date:    10:34:14 01/07/2018 
// Design Name: 
// Module Name:    spi_slave - Behavioral 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//--------------------------------------------------------------------------------
// Uncomment the following library declaration if using
// arithmetic functions with Signed or Unsigned values
// Uncomment the following library declaration if instantiating
// any Xilinx primitives in this code.
//library UNISIM;
//use UNISIM.VComponents.all;
// no timescale needed

module spi_slave(
input wire clk,
input wire rst,
input wire cs_n,
input wire spi_clk,
input wire mosi,
output wire miso,
output wire spi_rq,
output reg [7:0] rx_data,
output reg rx_ready,
input wire [7:0] tx_data,
output wire tx_busy,
input wire tx_new_data
);

// debug for now - data was wll received or sent
// launch transmission of new data

`define false 0
`define true 1

//-----------------------------------------------------------------------------	
// Signals for LPC1343 SPI controller receiver
//-----------------------------------------------------------------------------	
reg [7:0] lastCS = 8'h00;
reg [7:0] spi_tx_shifter;
reg [31:0] spi_bitcount;
reg spi_ready = `false;
reg [31:0] spi_test_count = 0;
reg [2:0] spi_clk_sampler = 3'b000;
reg spi_rx_bit;
reg wait_clock = `false;
reg transmitter_busy;

  assign spi_rq = spi_ready == `true ? 1'b1 : 1'b0;
  // indicates data well received / sent
  assign miso = cs_n == 1'b0 ? spi_tx_shifter[7] : 1'bZ;
  assign tx_busy = transmitter_busy;
  always @(posedge clk) begin
    if(rst == 1'b1) begin
      lastCS <= 8'hFF;
      spi_ready <= `false;
      spi_test_count <= 0;
      spi_clk_sampler <= 3'b000;
      wait_clock <= `false;
      transmitter_busy <= 1'b1;
      spi_tx_shifter <= 8'hFF;
    end
    else begin
      spi_clk_sampler <= {spi_clk_sampler[1:0],spi_clk};
      lastCS <= {lastCS[6:0],cs_n};
      rx_ready <= 1'b0;
      if(lastCS[7:5] == 3'b111 && lastCS[1:0] == 2'b00 && cs_n == 1'b0 && wait_clock == `false) begin
        // falling edge of CS
        spi_bitcount <= 0;
        spi_ready <= `false;
        // spi_test_count <= spi_test_count + 1;
        // spi_tx_shifter <= std_logic_vector(to_unsigned(spi_test_count,8));
        wait_clock <= `true;
      end
      if(spi_clk_sampler == 3'b011 && lastCS[0] == 1'b0 && cs_n == 1'b0) begin
        // rising edge of clock, receive shift
        spi_rx_bit <= mosi;
        spi_ready <= `false;
        wait_clock <= `false;
      end
      if(spi_clk_sampler == 3'b110 && lastCS[0] == 1'b0 && cs_n == 1'b0) begin
        // falling edge of clock, transmit shift
        spi_tx_shifter <= {spi_tx_shifter[6:0],spi_rx_bit};
        spi_bitcount <= spi_bitcount + 1;
        if(spi_bitcount == 7) begin
          spi_bitcount <= 0;
          spi_ready <= `true;
          rx_data <= {spi_tx_shifter[6:0],spi_rx_bit};
          rx_ready <= 1'b1;
          // a single clock cycle pulse
          transmitter_busy <= 1'b0;
          // ready transmit a byte (if there are subsequent clocks)
        end
      end
      if(transmitter_busy == 1'b0 && tx_new_data == 1'b1) begin
        transmitter_busy <= 1'b1;
        spi_tx_shifter <= tx_data;
      end
    end
    // reset
  end


endmodule
