// File src/tms9919.vhd translated with vhd2vl v3.0 VHDL to Verilog RTL translator
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
// tms9919.vhd
//
// Implementation of the TMS9919 sound chip.
// The module is not 100% compatible with the orignal design.
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
//---------------------------------------------------------------------------------

module tms9919(
input wire clk,
input wire reset,
input wire we,
input wire [7:0] data_in,
output reg [7:0] dac_out
);

// 25MHz clock
// reset active high
// high for one clock for a write to sound chip
// data bus in


// output to audio DAC

reg [6:0] latch_high;  // written when MSB (bit 7) is set
reg [9:0] tone1_div_val;  // divider value
reg [3:0] tone1_att;  // attenuator value
reg [9:0] tone2_div_val;  // divider value
reg [3:0] tone2_att;  // attenuator value
reg [9:0] tone3_div_val;  // divider value
reg [3:0] tone3_att;  // attenuator value
reg [3:0] noise_div_val;  // Noise generator divisor
reg [3:0] noise_att;  // attenuator value
reg [9:0] tone1_counter;
reg [9:0] tone2_counter;
reg [9:0] tone3_counter;
reg [10:0] noise_counter;
reg [10:0] master_divider;
reg tone1_out;
reg tone2_out;
reg tone3_out;
reg noise_out;
reg bump_noise;
reg [15:0] noise_lfsr;
reg [3:0] add_value;
reg add_flag;
parameter [2:0]
  chan0 = 0,
  chan1 = 1,
  chan2 = 2,
  noise = 3,
  prepare = 4,
  output_stuff = 5;

reg [2:0] tone_proc;
reg [7:0] acc;  

// type volume_lookup_array is array (0 to 15) of std_logic_vector(7 downto 0);
// constant volume_lookup : volume_lookup_array := (
// 	"00111100", "00110000", "00100010", "00010011",
// 	"00001111", "00001111", "00001111", "00001111",
// 	"00001100", "00001000", "00000110", "00000100", 
// 	"00000011", "00000010", "00000001", "00000000"
// );

reg [7:0] volume_lookup[0:15];  
initial begin 
  volume_lookup[0] = 60;
  volume_lookup[1] = 48;
  volume_lookup[2] = 34;
  volume_lookup[3] = 19;
  volume_lookup[4] = 15;
  volume_lookup[5] = 15;
  volume_lookup[6] = 15;
  volume_lookup[7] = 15;
  volume_lookup[8] = 12;
  volume_lookup[9] = 8;
  volume_lookup[10] = 6;
  volume_lookup[11] = 4;
  volume_lookup[12] = 3;
  volume_lookup[13] = 2;
  volume_lookup[14] = 1;
  volume_lookup[15] = 0;
end 

  always @(posedge clk, posedge reset) begin : P1
    reg k;

    if(reset == 1'b1) begin
      latch_high <= {7{1'b0}};
      tone1_att <= 4'b1111;
      // off
      tone2_att <= 4'b1111;
      // off
      tone3_att <= 4'b1111;
      // off
      noise_att <= 4'b1111;
      // off
      master_divider <= 0;
      add_value <= {4{1'b0}};
      add_flag <= 1'b0;
    end else begin
      if(we == 1'b1) begin
        // data write 
        if(data_in[7] == 1'b1) begin
          latch_high <= data_in[6:0];
          // store for later re-use
          case(data_in[6:4])
          3'b000 : begin
            tone1_div_val[3:0] <= data_in[3:0];
          end
          3'b001 : begin
            tone1_att <= data_in[3:0];
          end
          3'b010 : begin
            tone2_div_val[3:0] <= data_in[3:0];
          end
          3'b011 : begin
            tone2_att <= data_in[3:0];
          end
          3'b100 : begin
            tone3_div_val[3:0] <= data_in[3:0];
          end
          3'b101 : begin
            tone3_att <= data_in[3:0];
          end
          3'b110 : begin
            noise_div_val <= data_in[3:0];
            noise_lfsr <= 16'h0001;
            // initialize noise generator
          end
          3'b111 : begin
            noise_att <= data_in[3:0];
          end
          default : begin
          end
          endcase
        end
        else begin
          // Write with MSB set to zero. Use latched register value.
          case(latch_high[6:4])
          3'b000 : begin
            tone1_div_val[9:4] <= data_in[5:0];
          end
          3'b010 : begin
            tone2_div_val[9:4] <= data_in[5:0];
          end
          3'b100 : begin
            tone3_div_val[9:4] <= data_in[5:0];
          end
          default : begin
          end
          endcase
        end
      end

      // Ok. Now handle the actual sound generators.
      // The input freuency on the TI-99/4A is 3.58MHz which is divided by 32, this is 111875Hz.
      // Our clock is 25MHz. As the first approximation we will divide 25MHz by 223 (exact 223.46).
      // That gives a clock of 112107Hz - not sure if this is good enough.
      // After checking that actually yields half of the desired frequency. So let's go with 112.
      // This would give us 25e6/(2*112) = 111607 Hz. The error is 111875/111607 = 1.0024, so 0.2%.
      master_divider <= master_divider + 1;
      if(master_divider >= 111) begin
        master_divider <= 0;
        tone1_counter <= (tone1_counter) - 1;
        // tone1_counter'length));
        tone2_counter <= (tone2_counter) - 1;
        tone3_counter <= (tone3_counter) - 1;
        noise_counter <= (noise_counter) - 1;
        if((tone1_counter) == 0) begin
          tone1_out <=  ~tone1_out;
          tone1_counter <= tone1_div_val;
        end
        if((tone2_counter) == 0) begin
          tone2_out <=  ~tone2_out;
          tone2_counter <= tone2_div_val;
        end
        bump_noise <= 1'b0;
        if((tone3_counter) == 0) begin
          tone3_out <=  ~tone3_out;
          tone3_counter <= tone3_div_val;
          if(noise_div_val[1:0] == 2'b11) begin
            bump_noise <= 1'b1;
          end
        end
        if(noise_counter[8:0] == 9'b000000000) begin
          case(noise_div_val[1:0])
          2'b00 : begin
            bump_noise <= 1'b1;
            // 512 
          end
          2'b01 : begin
            if(noise_counter[9] == 1'b0) begin
              // 1024
              bump_noise <= 1'b1;
            end
          end
          2'b10 : begin
            if(noise_counter[10:9] == 2'b00) begin
              // 2048
              bump_noise <= 1'b1;
            end
          end
          default : begin
          end
          endcase
        end
        if(bump_noise == 1'b1) begin
          if(noise_div_val[2] == 1'b1) begin
            // white noise
            k = noise_lfsr[14] ^ noise_lfsr[13];
          end
          else begin
            k = noise_lfsr[14];
            // just feedback 
          end
          noise_lfsr <= {noise_lfsr[14:0],k};
          if(noise_lfsr[14] == 1'b1) begin
            noise_out <=  ~noise_out;
          end
        end
      end
      if(add_flag == 1'b1) begin
        acc <= acc + volume_lookup[add_value];
      end
      else begin
        acc <= acc - volume_lookup[add_value];
      end
      // Ok now combine the tone_out values
      case(tone_proc)
      chan0 : begin
        add_value <= tone1_att;
        add_flag <= tone1_out;
        tone_proc <= chan1;
      end
      chan1 : begin
        add_value <= tone2_att;
        add_flag <= tone2_out;
        tone_proc <= chan2;
      end
      chan2 : begin
        add_value <= tone3_att;
        add_flag <= tone3_out;
        tone_proc <= noise;
      end
      noise : begin
        add_value <= noise_att;
        add_flag <= noise_out;
        tone_proc <= prepare;
      end
      prepare : begin
        // During this step the acc gets updated with noise value
        add_value <= 4'b1111;
        // silence, this stage is just a wait state to pick up noise
        tone_proc <= output_stuff;
      end
      default : begin
        // output_stuff stage
        dac_out <= acc;
        add_value <= 4'b1111;
        // no change
        acc <= 8'h80;
        tone_proc <= chan0;
      end
      endcase
    end
  end


endmodule
