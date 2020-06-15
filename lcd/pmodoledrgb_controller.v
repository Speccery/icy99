/*
 * Copyright (c) 2017 Joel Holdsworth <joel@airwebreathe.org.uk>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of copyright holder nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

module pmodoledrgb_controller(clk, reset, frame_begin, sending_pixels,
  sample_pixel, pixel_index, pixel_data, cs, sdin, sclk, d_cn, resn, vccen,
  pmoden);
localparam Width = 96;
localparam Height = 64;
localparam PixelCount = Width * Height;
localparam PixelCountWidth = $clog2(PixelCount);

parameter ClkFreq = 6250000; // Hz
input clk, reset;
output frame_begin, sending_pixels, sample_pixel;
output [PixelCountWidth-1:0] pixel_index;
input [15:0] pixel_data;
output cs, sdin, sclk, d_cn, resn, vccen, pmoden;

// Frame begin event
localparam FrameFreq = 60;
localparam FrameDiv = ClkFreq / FrameFreq;
localparam FrameDivWidth = $clog2(FrameDiv);

reg [FrameDivWidth-1:0] frame_counter;
assign frame_begin = frame_counter == 0;

// State Machine
localparam PowerDelay = 20; // ms
localparam ResetDelay = 3; // us
localparam VccEnDelay = 20; // ms
localparam StartupCompleteDelay = 100; // ms

localparam MaxDelay = StartupCompleteDelay;
localparam MaxDelayCount = (ClkFreq * MaxDelay) / 1000;
reg [$clog2(MaxDelayCount)-1:0] delay;

localparam StateCount = 32;
localparam StateWidth = $clog2(StateCount);

localparam PowerUp = 5'b00000;
localparam Reset = 5'b00001;
localparam ReleaseReset = 5'b00011;
localparam EnableDriver = 5'b00010;
localparam DisplayOff = 5'b00110;
localparam SetRemapDisplayFormat = 5'b00111;
localparam SetStartLine = 5'b00101;
localparam SetOffset = 5'b00100;
localparam SetNormalDisplay = 5'b01100;
localparam SetMultiplexRatio = 5'b01101;
localparam SetMasterConfiguration = 5'b01111;
localparam DisablePowerSave = 5'b01110;
localparam SetPhaseAdjust = 5'b01010;
localparam SetDisplayClock = 5'b01011;
localparam SetSecondPrechargeA = 5'b01001;
localparam SetSecondPrechargeB = 5'b01000;
localparam SetSecondPrechargeC = 5'b11000;
localparam SetPrechargeLevel = 5'b11001;
localparam SetVCOMH = 5'b11011;
localparam SetMasterCurrent = 5'b11010;
localparam SetContrastA = 5'b11110;
localparam SetContrastB = 5'b11111;
localparam SetContrastC = 5'b11101;
localparam DisableScrolling = 5'b11100;
localparam ClearScreen = 5'b10100;
localparam VccEn = 5'b10101;
localparam DisplayOn = 5'b10111;
localparam PrepareNextFrame = 5'b10110;
localparam SetColAddress = 5'b10010;
localparam SetRowAddress = 5'b10011;
localparam WaitNextFrame = 5'b10001;
localparam SendPixel = 5'b10000;

assign sending_pixels = state == SendPixel;

assign resn = state != Reset;
assign d_cn = sending_pixels;
assign vccen = state == VccEn || state == DisplayOn ||
  state == PrepareNextFrame || state == SetColAddress ||
  state == SetRowAddress || state == WaitNextFrame || state == SendPixel;
assign pmoden = !reset;

reg [15:0] color;

reg [StateWidth-1:0] state;
wire [StateWidth-1:0] next_state = fsm_next_state(state, frame_begin, pixel_index);

function [StateWidth-1:0] fsm_next_state;
  input [StateWidth-1:0] state;
  input frame_begin;
  input [PixelCountWidth-1:0] pixels_remain;
  case (state)
    PowerUp: fsm_next_state = Reset;
    Reset: fsm_next_state = ReleaseReset;
    ReleaseReset: fsm_next_state = EnableDriver;
    EnableDriver: fsm_next_state = DisplayOff;
    DisplayOff: fsm_next_state = SetRemapDisplayFormat;
    SetRemapDisplayFormat: fsm_next_state = SetStartLine;
    SetStartLine: fsm_next_state = SetOffset;
    SetOffset: fsm_next_state = SetNormalDisplay;
    SetNormalDisplay: fsm_next_state = SetMultiplexRatio;
    SetMultiplexRatio: fsm_next_state = SetMasterConfiguration;
    SetMasterConfiguration: fsm_next_state = DisablePowerSave;
    DisablePowerSave: fsm_next_state = SetPhaseAdjust;
    SetPhaseAdjust: fsm_next_state = SetDisplayClock;
    SetDisplayClock: fsm_next_state = SetSecondPrechargeA;
    SetSecondPrechargeA: fsm_next_state = SetSecondPrechargeB;
    SetSecondPrechargeB: fsm_next_state = SetSecondPrechargeC;
    SetSecondPrechargeC: fsm_next_state = SetPrechargeLevel;
    SetPrechargeLevel: fsm_next_state = SetVCOMH;
    SetVCOMH: fsm_next_state = SetMasterCurrent;
    SetMasterCurrent: fsm_next_state = SetContrastA;
    SetContrastA: fsm_next_state = SetContrastB;
    SetContrastB: fsm_next_state = SetContrastC;
    SetContrastC: fsm_next_state = DisableScrolling;
    DisableScrolling: fsm_next_state = ClearScreen;
    ClearScreen: fsm_next_state = VccEn;
    VccEn: fsm_next_state = DisplayOn;
    DisplayOn: fsm_next_state = PrepareNextFrame;
    PrepareNextFrame: fsm_next_state = SetColAddress;
    SetColAddress: fsm_next_state = SetRowAddress;
    SetRowAddress: fsm_next_state = WaitNextFrame;
    WaitNextFrame: fsm_next_state = frame_begin ? SendPixel : WaitNextFrame;
    SendPixel: fsm_next_state = (pixel_index == PixelCount-1) ?
      PrepareNextFrame : SendPixel;
    default: fsm_next_state = PowerUp;
  endcase
endfunction

// SPI Master
localparam SpiCommandMaxWidth = 40;
localparam SpiCommandBitCountWidth = $clog2(SpiCommandMaxWidth);

reg [SpiCommandBitCountWidth-1:0] spi_word_bit_count;
reg [SpiCommandMaxWidth-1:0] spi_word;

wire spi_busy = spi_word_bit_count != 0;
assign cs = !spi_busy;
assign sclk = clk | !spi_busy;
assign sdin = spi_word[SpiCommandMaxWidth-1] & spi_busy;

// Video
assign sample_pixel = (state == WaitNextFrame && frame_begin) ||
  (sending_pixels && frame_counter[3:0] == 0);
assign pixel_index = sending_pixels ?
  frame_counter[FrameDivWidth-1:$clog2(16)] : 0;

always @(negedge clk) begin
  if (reset) begin
    frame_counter <= 0;
    delay <= 0;
    state <= 0;
    spi_word <= 0;
    spi_word_bit_count <= 0;
  end else begin
    frame_counter <= (frame_counter == FrameDiv-1) ? 0 : frame_counter + 1;

    if (spi_word_bit_count > 1) begin
      spi_word_bit_count <= spi_word_bit_count - 1;
      spi_word <= {spi_word[SpiCommandMaxWidth-2:0], 1'b0};
    end else if (delay != 0) begin
      spi_word <= 0;
      spi_word_bit_count <= 0;
      delay <= delay - 1;
    end else begin
      state <= next_state;
      case (next_state)
        PowerUp: begin
          spi_word <= 0;
          spi_word_bit_count <= 0;
          delay <= (ClkFreq * PowerDelay) / 1000;
        end
        Reset: begin
          spi_word <= 0;
          spi_word_bit_count <= 0;
          delay <= (ClkFreq * ResetDelay) / 1000;
        end
        ReleaseReset: begin
          spi_word <= 0;
          spi_word_bit_count <= 0;
          delay <= (ClkFreq * ResetDelay) / 1000;
        end
        EnableDriver: begin
          // Enable the driver
          spi_word <= {16'hFD12, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        DisplayOff: begin
          // Turn the display off
          spi_word <= {8'hAE, {SpiCommandMaxWidth-8{1'b0}}};
          spi_word_bit_count <= 8;
          delay <= 1;
        end
        SetRemapDisplayFormat: begin
          // Set the remap and display formats
          spi_word <= {16'hA072, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetStartLine: begin
          // Set the display start line to the top line
          spi_word <= {16'hA100, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetOffset: begin
          // Set the display offset to no vertical offset
          spi_word <= {16'hA200, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetNormalDisplay: begin
          // Make it a normal display with no color inversion or forcing
          // pixels on/off
          spi_word <= {8'hA4, {SpiCommandMaxWidth-8{1'b0}}};
          spi_word_bit_count <= 8;
          delay <= 1;
        end
        SetMultiplexRatio: begin
          // Set the multiplex ratio to enable all of the common pins
          // calculated by thr 1+register value
          spi_word <= {16'hA83F, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetMasterConfiguration: begin
          // Set the master configuration to use a required a required
          // external Vcc supply.
          spi_word <= {16'hAD8E, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        DisablePowerSave: begin
          // Disable power saving mode.
          spi_word <= {16'hB00B, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetPhaseAdjust: begin
          // Set the phase length of the charge and dischare rates of
          // an OLED pixel.
          spi_word <= {16'hB131, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetDisplayClock: begin
          // Set the display clock divide ration and oscillator frequency
          spi_word <= {16'hB3F0, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetSecondPrechargeA: begin
          // Set the second pre-charge speed of color A
          spi_word <= {16'h8A64, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetSecondPrechargeB: begin
          // Set the second pre-charge speed of color B
          spi_word <= {16'h8B78, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetSecondPrechargeC: begin
          // Set the second pre-charge speed of color C
          spi_word <= {16'h8C64, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetPrechargeLevel: begin
          // Set the pre-charge voltage to approximately 45% of Vcc
          spi_word <= {16'hBB3A, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetVCOMH: begin
          // Set the VCOMH deselect level
          spi_word <= {16'hBE3E, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetMasterCurrent: begin
          // Set the master current attenuation
          spi_word <= {16'h8706, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetContrastA: begin
          // Set the contrast for color A
          spi_word <= {16'h8191, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetContrastB: begin
          // Set the contrast for color B
          spi_word <= {16'h8250, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        SetContrastC: begin
          // Set the contrast for color C
          spi_word <= {16'h837D, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 1;
        end
        DisableScrolling: begin
          // Disable scrolling
          spi_word <= {8'h25, {SpiCommandMaxWidth-8{1'b0}}};
          spi_word_bit_count <= 8;
          delay <= 1;
        end
        ClearScreen: begin
          // Clear the screen
          spi_word <= {40'h2500005F3F, {SpiCommandMaxWidth-40{1'b0}}};
          spi_word_bit_count <= 40;
          delay <= 1;
        end
        VccEn: begin
          spi_word <= 0;
          spi_word_bit_count <= 0;
          delay <= (ClkFreq * VccEnDelay) / 1000;
        end
        DisplayOn: begin
          // Turn the display on
          spi_word <= {8'hAF, {SpiCommandMaxWidth-8{1'b0}}};
          spi_word_bit_count <= 8;
          delay <= (ClkFreq * StartupCompleteDelay) / 1000;
        end
        PrepareNextFrame: begin
          // Deassert CS before beginning next frame
          spi_word <= 0;
          spi_word_bit_count <= 0;
          delay <= 1;
        end
        SetColAddress: begin
          // Set the column address
          spi_word <= {24'h15005F, {SpiCommandMaxWidth-24{1'b0}}};
          spi_word_bit_count <= 24;
          delay <= 1;
        end
        SetRowAddress: begin
          // Set the row address
          spi_word <= {24'h75003F, {SpiCommandMaxWidth-24{1'b0}}};
          spi_word_bit_count <= 24;
          delay <= 1;
        end
        WaitNextFrame: begin
          spi_word <= 0;
          spi_word_bit_count <= 0;
          delay <= 0;
        end
        SendPixel: begin
          spi_word <= {pixel_data, {SpiCommandMaxWidth-16{1'b0}}};
          spi_word_bit_count <= 16;
          delay <= 0;
        end
        default: begin
          spi_word <= 0;
          spi_word_bit_count <= 0;
          delay <= 0;
        end
      endcase
    end
  end
end

endmodule
