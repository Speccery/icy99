//--------------------------------------------------------------------------------
// tms9918.vhd
//
// This module is an implementation of the TI TMS9918 Video Processor chip.
// The module is not 100% compatible with the orignal design.
// There are some missing features, but also some extensions.
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
//--------------------------------------------------------------------------------

module tms9918(
	input wire clk,
	input wire reset,
	input wire mode,        // 1 for registers, 0 for memory
	input wire [7:0] addr,  // extension, 8 bit address in
	input wire [7:0] data_in,
	output wire [15:0] data_out,  // extended to 16-bits (top 8 correspond to 8-bit interface)
  output reg cpu_read_cycle_ack,
  output reg cpu_write_cycle_ack,
	input wire wr,          // high for 1 clock cycle to write
	input wire rd,          // can be high multiple cycles. high-to-low transition increments addr for data reads
	output reg vga_vsync,
	output reg vga_hsync,
	output wire debug1,
	output wire debug2,
	output wire int_out,    // interrupt out, high means interrupt pending
	output reg [2:0] vga_red,
	output reg [2:0] vga_green,
	output reg [1:0] vga_blue,
  output wire vde,
  // Interface for external RAM. If EXTERNAL VRAM is defined, this interface is used,.
  // otherwise embedded block RAM is used for VRAM. On the ICE40HX chips (BlackIce-II) there
  // is not enough block RAM and external RAM must be used for video memory too.
  output wire [13:0] xram_addr,
  output wire [7:0]  xram_data_out,
  input  wire [7:0]  xram_data_in,
  output wire xram_read_rq,   // high for one clock
  input  wire xram_read_ack,  // high when xram_data_in is valid
  output wire xram_pipeline_reads,  // when set high, xram is held with VDP 
  output wire xram_write_rq,  // high for one clock
  input  wire xram_write_ack,
  // Debug interface display two 32 bit numbers
  input wire [31:0] debugA,
  input wire [31:0] debugB
);

// CPU side of VRAM and VDP
reg write_state;
reg [7:0] hold_reg;
reg [16:0] vram_addr;
reg [7:0] reg0;
reg [7:0] reg1 = 8'h00;  // init with zero, interrupts disabled
reg [7:0] reg2;
reg [7:0] reg3;
reg [7:0] reg4;
reg [7:0] reg5;
reg [7:0] reg6;
reg [7:0] reg7;
// In 9938 mode plenty of additional registers and other regs expanded.
// R#0 bit 4: IE1, when enabled, raster interrupts are generated
// R#2 expanded to have bits A16,A15,A14
// R#4 expanded to have A16, A15, A14
// R#5 expanded to have A14 bit sprite attribute table
// R#6 expanded to have A16,A15,A14
reg mode9938 = 1'b0;
reg [7:0] reg9;   // bit 7=1: 212 scanlines
reg [7:0] reg10;  // Color table high A16,A15,A14 (LSBs) expands reg3
reg [7:0] reg11;  // Sprite attribute table high A16,A15 (LSBs) expands R5
reg [7:0] reg14;  // Address A16,A15,A14 (LSBs)
reg [7:0] reg15;  // Status register pointer (low 4 bits)
reg [7:0] reg16;  // Color color palette address register (low 4 bits)
reg [7:0] reg17;  // Control register pointer (low 6 bits, MSB selects autoincrement mode)
reg [7:0] reg19;  // Interrupt line register -> raster interrupts
// F18A 30 lines mode
reg [7:0] reg49;  // bit 6=1: 30 character lines

reg [7:0] stat_reg0 = 8'h00;
// 9938 style registers follow
reg [7:0] stat_reg1 = 8'h00;  // bits 5..1 = ID#, bit0 = FH horizontal scan interrupt
                              // Here I set ID to be 0

wire [7:0] active_stat_reg_rd = !mode9938 ? stat_reg0 : // TMS9918 mode
  reg15[3:0] == 4'h0 ? stat_reg0 : 
  reg15[3:0] == 4'h1 ? stat_reg1 :
  reg15[3:0] == 4'h4 ? 8'hFE :  // Status register S#4: 1111_111,X8
  reg15[3:0] == 4'h6 ? 8'hFC :  // Status register S#6: 1111_11,Y9,Y8
  stat_reg0;
wire [5:0] reg4_9938 = mode9938 ? reg4[5:0] : { 3'b000, reg4[2:0]};   // Either full 6 bits (9938) or 3 bits (9918)

reg [7:0] mem_rd_bus;
reg bump_rq;
reg vdp_rd_prev;
reg vdp_mode_prev;
reg [1:0] vdp_addr_prev;  // video refresh circuit
wire columns_80 = reg0[2];
reg clk25MHz;  // 25MHz 25/75 clock
reg [1:0] clkdiv=0;
wire Hsync;
wire Vsync;
wire [9:0] VGARow;
reg [9:0] VGACol;
wire [9:0] VGACol2;
wire [7:0] vga_shift;
wire video_on;
reg clk12_5MHz;  // 12.5 MHz 50/50 clock
// linebuffer based VGA implementation
wire [7:0] vga_line_buf_out;  // linebuf to VGA data out
reg [7:0] vga_line_buf_in;  // write bus to linebuffer
reg [16:0] vram_out_addr;  // vram hardware addr bus
wire [9:0] line_buf_addra;
wire [9:0] line_buf_addrb;
wire [0:0] line_buf_bit8_out;

wire [7:0] mem_data_in;         // Data from VRAM, either internal block RAM or external RAM
reg ram_write_rq;
reg ram_read_rq;
reg ram_pipeline_reads;         // Used to signal external memory control that we want to pipeline reads.
wire ram_read_ack;
wire ram_write_ack;

reg line_buf_bit8_in;
reg sig_coinc_pending;
reg sig_5th_pending;
reg vga_bank;
reg [8:0] vga_line_buf_addr;
reg adv_line_buf_addr;
wire vga_line_buf_wr;  // write strobe
reg [6:0] xpos;
reg [7:0] ypos;
reg pixel_write;
reg sprite_presence_write;  // Written high for sprites to detect COINC
reg [5:0] sprite_early_clocks;

// reg pixel_write_pending;
reg pixel_toggler;
parameter [4:0]
  wait_frame = 0,
  wait_line = 1,
  process_line = 2,
  process_sprites = 3,
  count_active_sprites = 4,
  sprites_addr = 5,
  sprite_read_vert = 6,
  sprite_read_horiz = 7,
  sprite_read_char = 8,
  sprite_read_color = 9,
  sprite_read_pattern0 = 10,
  sprite_read_pattern1 = 11,
  sprite_write_pattern_setup = 12,
  sprite_write_pattern0 = 13,
  sprite_write_pattern1 = 14,
  sprite_write_pattern_last = 15,
  sprite_next = 16,
  cpu_vram_read0 = 17,
  cpu_vram_write0 = 18;

reg [4:0] refresh_state = wait_frame;
reg [4:0] refresh_return_state;
parameter [2:0]
  setup_read_char = 0,
  read_char1      = 1,
  read_pattern    = 2,
  read_color      = 3,
  grab_pattern    = 4,
  grab_color      = 5,
  write_pixels    = 6,
  write_pixel_last = 7;

reg [2:0] process_pixel;
reg [16:0] char_addr;
reg [16:0] char_addr_reload;
reg [7:0] char_code;
reg [7:0] char_pattern;
reg [3:0] color0;
reg [3:0] color1;
reg [4:0] pixel_count;  // display start and in VGA scanlines
parameter disp_start = 16;
parameter disp_rendr = disp_start - 2;
parameter disp_start2 = disp_start + 2;
parameter disp_rendr_slv = disp_rendr;  //
parameter slv_511 = 511;
parameter slv_760 = 760;
parameter slv_479 = 479;  // EP-USTRIP
reg blanking;  // sprite generator variables
reg [4:0] sprite_counter;
reg [4:0] sprite_counter_next;
reg [8:0] sprite_y;  // attr table byte 0, with an extra bit
reg [7:0] sprite_x;  // attr table byte 1
reg [7:0] sprite_name;  // attr table byte 2	(partially signed, from -31 bleed to screen)
reg [7:0] sprite_color;  // attr table byte 3 (early,0,0,0,color:4)
reg [8:0] sprite_line;
reg [15:0] sprite_pixels;
reg [3:0] sprite_write_count;
reg [5:0] active_sprites;  //https://www.msx.org/forum/semi-msx-talk/emulation/question-about-msx1-palette?page=2
reg [7:0] color_data;

reg [8:0] sprite_yy;  // Temporary variable for spritle line check
reg [8:0] sprite_line_check;

// debug counters to find out what is going on
reg [15:0]  dbg_bytes_read_count;
reg [15:0]  dbg_bytes_read_total;

wire [31:0] debugAdisplay = { reg15, reg4, 7'h00, mode9938, reg2};  // debugA

//1:0, 0, 0
//2:0, 241, 20
//3:68, 249, 86
//4:85, 79, 255
//5:128, 111, 255
//6:250, 80, 51
//7:12, 255, 255
//8:255, 81, 52
//9:255, 115, 86
//A:226, 210, 4
//B:242, 217, 71
//C:4, 212, 19
//D:231, 80, 229
//E:208, 208, 208
//F:255, 255, 255

reg [7:0] palette_lookup[0:15];  // FIXME: write a verilog function for this

initial begin
	palette_lookup[0] <= 0;	// transparent
	palette_lookup[1] <= 0;	// black
	palette_lookup[2] <= 8'b00011100;
	palette_lookup[3] <= 8'b00111101;
	palette_lookup[4] <= 8'b01001011 ;
	palette_lookup[5] <= 8'b10010011 ;
	palette_lookup[6] <= 8'b11101001 ;
	palette_lookup[7] <= 8'b00011111 ;	// cyan
	palette_lookup[8] <= 8'b11101001 ;	// medium red
	palette_lookup[9] <= 8'b11110010 ;	// light red
	palette_lookup[10] <= 8'b11111000 ;	// dark yellow
	palette_lookup[11] <= 8'b11111010 ; // light yellow
	palette_lookup[12] <= 8'b00011000 ;	// dark green
	palette_lookup[13] <= 8'b11110111 ;	// magenta
	palette_lookup[14] <= 8'b10010010 ; // gray
	palette_lookup[15] <= 8'b11111111 ;	// white
end

  assign data_out = mode == 1'b0 && addr[7:6] == 2'b00 ? {mem_rd_bus,8'h00} : 
                    mode == 1'b1 && addr[7:6] == 2'b00 ? {active_stat_reg_rd,8'h00 } :
                    addr == 8'h40 ? {reg0,8'h00} : 
                    addr == 8'h41 ? {reg1,8'h00} : 
                    addr == 8'h42 ? {2'b00,reg2[3:0],10'b0000000000} :  
                    addr == 8'h43 ? {2'b00,reg3,6'b000000} : 
                    addr == 8'h44 ? {2'b00,reg4[2:0],11'b00000000000} : 
                    addr == 8'h45 ? {2'b00,reg5[6:0],7'b0000000} : 
                    addr == 8'h46 ? {2'b00,reg6[2:0],11'b00000000000} : 
                    addr == 8'h47 ? {reg7,8'h00} : 
                    addr == 8'h48 ? {vram_addr[15:0]} : 
                    addr == 8'h49 ? {6'b000000,VGACol} : 
                    addr == 8'h4A ? {6'b000000,VGARow} : 
                    addr == 8'h4B ? {vga_bank,2'b00,12'h000,blanking} :
                    addr == 8'h4C ? dbg_bytes_read_total :
                    addr == 8'h4D ? dbg_bytes_read_count :
                    addr == 8'h52 ? { reg2, 8'h00 } :
                    addr == 8'h53 ? { reg3, 8'h00 } :
                    addr == 8'h54 ? { reg4, 8'h00 } :
                    addr == 8'h55 ? { reg5, 8'h00 } :
                    addr == 8'h56 ? { reg6, 8'h00 } :
                    addr == 8'h57 ? { reg7, 8'h00 } :
                    addr == 8'h5A ? { reg10, 8'h00 } :
                    addr == 8'h5B ? { reg11, 8'h00 } :
                    addr == 8'h5E ? { reg14, 8'h00 } :
                    addr == 8'h5F ? { reg15, 8'h00 } :
                    addr == 8'h60 ? { reg16, 8'h00 } :
                    addr == 8'h61 ? { reg17, 8'h00 } :
                    addr == 8'h63 ? { reg19, 8'h00 } :
                     0;

  //////////////////////////////////////////////////////////////////////////////////////////////
  // PPPP   III X   X EEEEE L      SSSS         SSSS TTTTTT  AAA  RRRR  TTTTT
  // P   P   I   X X  E     L     S            S       T    A   A R   R   T
  // PPPP    I    X   EEE   L      SSS          SSS    T    AAAAA RRRR    T
  // P       I   X X  E     L         S            S   T    A   A R R     T
  // P      III X   X EEEEE LLLLL SSSS         SSSS    T    A   A R  R    T
  //////////////////////////////////////////////////////////////////////////////////////////////
  // Here is the pixel pump.
  // 
  // The original design of this module was for Xilinx Spartan in VHDL.
  // In this port, to be compatible with Lattice ICE40HX, the design runs at a lower clock speed
  // and with less capable dual port RAMs. As a consequence, here is a logic block to shift and 
  // write pixels to the scanline buffer. It runs in parallel with the main state machine,
  // enabling overlap between VRAM fetches and VGA linebuffer writes.
  // Each pixel is written twice, to scale up to VGA resolution horizontally
  //  Inputs: 
  //    go_write_pixels
  //    color0, color1, pixel_count, pattern_out, vga_line_buf_addr, pixel_toggler
  //    go - toggle this to start
  //  Outputs: 
  //    pixel_write     - write enable to line buffer
  //    vga_line_buf_in - data to be written to line buffer
  //    pixel_toggler   - toggles to write pixels twice
  //    wr_render_addr  - address to write pixels into
  reg         wr_go = 1'b0, gogo = 1'b0;
  reg [15:0]  wr_pattern_out, pattern_out;
  reg [3:0]   wr_color0, wr_color1;
  reg [4:0]   wr_pixel_count=0;
  reg [1:0]   wr_pixel_toggler=0; // our state machine indication
  reg         wr_sprite=0, sprite_out=0;
  reg [8:0]   wr_render_addr;
  reg         wr_coinc_pending = 0;
  reg         wr_setup_delay = 1'b0;
  reg         wr_first_pixel;
  reg [5:0]   wr_sprite_early_clocks;

  reg [3:0] pixel_out_4bit = 4'h0;
  reg [7:0] palettized = 8'h0;

  always @(posedge clk)
  begin
    wr_setup_delay <= 1'b0;
    if (wr_go != gogo) begin
      wr_color0 <= color0;
      wr_color1 <= color1;
      wr_pixel_count <= pixel_count;
      wr_pattern_out <= pattern_out;
      wr_sprite <= sprite_out;    // if 1 we are processing sprite pixels, i.e. reading them first and then writing to detect collisions
      // wr_pixel_toggler: For sprites start with state 2, i.e. read pixel. 
      //                   With 80 columns, start and stay in mode 2'b01 all the time.
      //                   Otherwise we start from state 2'b00.
      wr_pixel_toggler <= sprite_out ? 2'b10 : (columns_80 ? 2'b01 : 2'b00);  
      line_buf_bit8_in <= 1'b0; 
      wr_render_addr <= vga_line_buf_addr;
      wr_sprite_early_clocks <= sprite_early_clocks;
      wr_coinc_pending <= 0;
      wr_go <= ~wr_go;
      wr_setup_delay <= 1'b1;
      // For characters, don't increment line buffer address on first pixel before write cycle.
      // Sprites don't need this, sincethey have state 2'b10 to do the setup.
      wr_first_pixel <= !sprite_out; 
    end

    // Choose data to be written. For sprites wr_color0 is never written.
    vga_line_buf_in <= { 4'h0, wr_pattern_out[15] ? wr_color1 : wr_color0 }; 

    if (wr_pixel_count != 5'b00000 && !wr_setup_delay) begin    
      if (wr_pixel_toggler == 2'b10) begin
        // Here we read sprite pixel: line_buf_bit8_out is high if a sprite pixel already written here.
        if(line_buf_bit8_out[0] == 1'b1 && wr_pattern_out[15]) begin
          wr_coinc_pending <= 1'b1;
        end
        wr_pixel_toggler <= (columns_80 ? 2'b01 : 2'b00);  
        // Enable pixel write for non-transparent sprite pixels
        pixel_write <= wr_pattern_out[15] && wr_color1 != 4'h0 && !(|wr_sprite_early_clocks);     
        sprite_presence_write <= wr_pattern_out[15];
        line_buf_bit8_in <= sprite_out ? wr_pattern_out[15] : 1'b0; // For active sprite pixels write this bit
      end else begin
        // Write pixel, for pattern or sprites
        pixel_write <= !wr_sprite ? 
          1'b1 :      // Characters, write all pixels
          (wr_pixel_toggler == 2'b00 && wr_pattern_out[15] && wr_color1 != 4'h0 && !(|wr_sprite_early_clocks)); // Sprites
        sprite_presence_write <= wr_pixel_toggler == 2'b00 && wr_pattern_out[15] && !(|wr_sprite_early_clocks); 
        line_buf_bit8_in <= sprite_out & wr_pattern_out[15]; // For active sprite pixels write this bit high

        if(!wr_first_pixel && !(|wr_sprite_early_clocks))
          wr_render_addr <= wr_render_addr + 1;   
        wr_first_pixel <= 1'b0;

        wr_pixel_toggler <= (!wr_sprite || (wr_sprite && wr_pixel_toggler == 2'b00)) ?   
          { 1'b0, (columns_80 ? 1'b1 :   ~wr_pixel_toggler[0])} :  // not a sprite or state 00, just toggle bit 0. With 80 columns stick to 2'b01.
          2'b10;                           // Sprite pixel, go to read previous contents
        if (wr_pixel_toggler == 2'b01) begin
          wr_pixel_count <= wr_pixel_count - 1;
          wr_pattern_out <= { wr_pattern_out[14:0], 1'b0 };
          if(wr_sprite_early_clocks)
            wr_sprite_early_clocks <= wr_sprite_early_clocks - 1;
        end
        if(&wr_render_addr) begin
          // we're at the end of the scanline, stop rendering.
          wr_pixel_count <= 5'd0;
          pixel_write <= 1'b0;
        end
      end 
    end else begin
      pixel_write <= 1'b0;
    end
  end
  //////////////////////////////////////////////////////////////////////////////////////////////
  // PPPP   III X   X EEEEE L      SSSS         SSSS TTTTTT  OOO  PPPP
  // P   P   I   X X  E     L     S            S       T    O   O P   P
  // PPPP    I    X   EEE   L      SSS          SSS    T    O   O PPPP
  // P       I   X X  E     L         S            S   T    O   O P
  // P      III X   X EEEEE LLLLL SSSS         SSSS    T     OOO  P
  //////////////////////////////////////////////////////////////////////////////////////////////

  // cpu_mem_read is high when CPU wants to read VRAM
  wire cpu_mem_read;
  reg cpu_read_already_done = 1'b0;
  reg cpu_mem_read_pending = 1'b0;
  assign cpu_mem_read = (rd == 1'b1 && mode == 1'b0 && addr[7:6] == 2'b00) && !cpu_read_already_done;
  // cpu_mem_write is high when CPU wants to write VRAM
  wire cpu_mem_write;
  reg cpu_mem_write_pending = 1'b0;
  assign cpu_mem_write = (mode == 1'b0 && wr == 1'b1 && addr[7:6] == 2'b00);

  assign debug1 = vga_bank;
  assign debug2 = refresh_state == wait_line ? 1'b1 : 1'b0;
  // stat_reg0(7): interrupt pending
  // reg1(5): Interrupt enable, i.e. mask bit
  assign int_out = stat_reg0[7] == 1'b1 && reg1[5] == 1'b1 ? 1'b1 : 1'b0;

  reg [5:0] sprite_limit; // Render no more than 8 sprites per scanline

  reg detect_frame_end = 1'b0, detect_line_end = 1'b0;

  // Last scanline is 192 normally, 212 in a specific 9938 case.
  wire [7:0] last_scanline = mode9938 && reg9[7] == 1'b1 ? 212 : // 9938 212 scanlines
      mode9938 && reg49[6] == 1'b1 ? 240 :    // F18A 30 lines
      192;

  // Name table memory base address. In 80 column mode the two LSBs are not used.
  wire [2:0] name_high_addr = mode9938 ? reg2[6:4] : 3'b000 ;
  wire [16:0] name_table_addr = columns_80 ? { name_high_addr, reg2[3:2], 12'b0000_0000_0000 } : { name_high_addr, reg2[3:0], 10'b00_0000_0000};
  
  
  // Cell width in scanline buffer pixels
  wire [4:0]  cell_width = columns_80 ? (reg1[4] == 1'b1 ? 6 : 8)      
                            : (reg1[4] == 1'b1 ? 12 : 16);

  reg drawing;  // Check simulation how drawing starts
  reg mask_coinc_before_next_render = 1'b0;

  always @(posedge clk, posedge reset) begin : P1
    reg [31:0] k;
    reg [8:0] spry;
    reg [8:0] yline;
    reg [7:0] t;
    reg [7:0] border;

    if(reset == 1'b1) begin
      write_state <= 1'b0;
      bump_rq <= 1'b0;
      refresh_state <= wait_frame;
      stat_reg0 <= 8'h00;
      stat_reg1 <= 8'h00; // Pretend that this is 9938
      sig_coinc_pending <= 1'b0;
      sig_5th_pending <= 1'b0;
      cpu_mem_write_pending <= 1'b0;
      cpu_mem_read_pending <= 1'b0;
      cpu_read_already_done <= 1'b0;
      ram_pipeline_reads <= 1'b0;
      reg0 <= 8'h00;
      reg1 <= 8'h00;
      detect_frame_end <= 1'b0;
      detect_line_end  <= 1'b0;
      drawing <= 1'b0;
      mask_coinc_before_next_render <= 1'b0;
      reg9 <= 8'h00;
      reg10 <= 8'h00;
      reg11 <= 8'h00;
      reg14 <= 8'h00;
      reg15 <= 8'h00;
      reg16 <= 8'h00;
      reg17 <= 8'h00;
      reg19 <= 8'h00;
      reg49 <= 8'h00;
      mode9938 <= 1'b0;
    end else begin
      // // Divide 100MHz clk by 4 to issue pulses in clk25Mhz. 
      // // It is high once per 4 clock cycles.
      k = (clkdiv) + 1;
      clkdiv <= k;
      // // FIXME CHECK clkdiv'length));
      // clk25MHz <= 1'b0;
      // if(clkdiv == 2'b11) begin
      //   clk25MHz <= 1'b1;
      // end
      clk25MHz <= 1'b1; // With Lattice ICE40HX version clock is 25MHz and this behaves as enable

      ram_pipeline_reads <= 1'b0;
      cpu_read_cycle_ack <= 1'b0;
      cpu_write_cycle_ack <= 1'b0;

      if(wr == 1'b1 && mode == 1'b1 && addr[7:6] == 2'b00) begin
        // write cycles to registers etc.
        cpu_write_cycle_ack <= 1'b1;  // ack this cycle, its a register write

        if(write_state == 1'b0) begin
          hold_reg <= data_in;
          // hold on to the first byte
          write_state <= 1'b1;
        end
        else begin
          case(data_in[7:6])
          2'b00 : begin
            // read from vram setup
            vram_addr <= {mode9938 ? 3'b000 : reg14[2:0], data_in[5:0],hold_reg};
          end
          2'b01 : begin
            // write to vram setup
            vram_addr <= {mode9938 ? 3'b000 : reg14[2:0], data_in[5:0],hold_reg};
          end
          2'b10 : begin
            // write to VDP register. Changed this code to decode 6 bits of register address
            // to support 80 column mode. Earlier only decoded 3 bits.
            case(data_in[5:0])
            6'd0 : reg0 <= hold_reg;    // 9938: IE1 bit 4
            6'd1 : reg1 <= hold_reg;
            6'd2 : reg2 <= hold_reg;    // 9938: 3 more bits of pattern layout table
            6'd3 : reg3 <= hold_reg;
            6'd4 : reg4 <= hold_reg;    // 9938: 3 more bits of pattern generator address
            6'd5 : reg5 <= hold_reg;    // 9938: MSB A14 of sprite attribute table
            6'd6 : reg6 <= hold_reg;    // 9938: 3 more bits of sprite pattern generator table
            6'd7 : reg7 <= hold_reg;
            6'd9 : reg9 <= hold_reg;    // 9938 select 212 scanlines
            6'd10 : reg10 <= hold_reg;  // 9938
            6'd11 : reg11 <= hold_reg;  // 9938
            6'd14 : reg14 <= hold_reg;  // 9938
            6'd15 : reg15 <= hold_reg;  // 9938: low 4 bits select status register
            6'd16 : reg16 <= hold_reg;  // 9938
            6'd17 : reg17 <= hold_reg;  // 9938
            6'd19 : reg19 <= hold_reg;  // 9938
            6'd49 : reg49 <= hold_reg;  // F18A select 30 lines 
            6'd63 : mode9938 <= hold_reg[0];    // EPEP BUGBUG enable 9938 with register 63 bit 0
            endcase
          end
          default : begin
            // do nothing
          end
          endcase
          write_state <= 1'b0;
        end
      end
      if((wr == 1'b1 || rd == 1'b1) && mode == 1'b0 && addr[7:6] == 2'b00) begin
        write_state <= 1'b0;
      end

      // generate ack for VDP register read cycles and extended status reg read cycles
      if((rd == 1'b1 && mode == 1'b1) || (rd == 1'b1 && mode == 1'b0 && addr[7:6]!=2'b00))
        cpu_read_cycle_ack <= 1'b1;

      if(cpu_mem_write)
        cpu_mem_write_pending <= 1'b1;
      if(cpu_mem_read)
        cpu_mem_read_pending <= 1'b1;
      if(rd == 1'b0)
        cpu_read_already_done <= 1'b0;

      vdp_rd_prev <= rd;
      vdp_mode_prev <= mode;
      vdp_addr_prev <= addr[7:6];
      if(vdp_rd_prev == 1'b1 && rd == 1'b0 && vdp_mode_prev == 1'b1 && vdp_addr_prev == 2'b00 
        && (!mode9938 || (mode9938 && reg15[3:0] == 4'h0))) begin
        // read became inactive on status register, clear interrupt request
        stat_reg0[7] <= 1'b0;
        stat_reg0[6] <= 1'b0;
        // also reset fifth sprite bit if active
        stat_reg0[5] <= 1'b0;
        // and coincide flag, if any two sprites have overlapping pixels (transparent are considered too)
      end
      if(bump_rq == 1'b1 && rd == 1'b0) begin
        vram_addr <= 1 + vram_addr; // Needs to be modified for 9938
        bump_rq <= 1'b0;
      end
      // VGA processing
      vga_hsync <= Hsync;
      vga_vsync <= Vsync;
      VGACol <= (VGACol2) - 32; // Apply a shift to VGACol
      // read from linebuffer
      if(clk25MHz == 1'b1) begin
        if(video_on == 1'b1 && reg1[6] == 1'b1) begin
          // vga_line_buf_out is the output of the linebuffer. The read address is computed from VGACol.
          // It needs one clock cycle to for the line buffer read operation. The the output is one pixel late.
          // Therefore VGACol==0 data is ready at VGACol == 1. This also means that in normal 32 column mode,
          // the last pixel is not at VGACol==511 but VGACol==512.
          if(VGACol != 0 && blanking == 1'b0 &&
               ( (VGACol <= (slv_511+1) && reg1[4] == 1'b0) 
              || (VGACol <= (slv_479+1) && reg1[4] == 1'b1) )
               ) begin
            pixel_out_4bit = vga_line_buf_out[3:0];
            drawing <= 1'b1;
          end else begin
            pixel_out_4bit = reg7[3:0];
            drawing <= 1'b0;
          end

/* Don't show debug stuff
 *
          // Show debug information.
          if(VGARow[9:2] == 8'h40) begin
            if(VGACol < 256) begin
              pixel_out_4bit = debugAdisplay[31 - VGACol[7:3]] ? 4'd15 : 4'd1;
              if(VGACol[4:0] == 5'b0_0000)
                pixel_out_4bit = 4'd6;
            end
          end
*/
/*
          if(VGARow[9:2] == 8'h48) begin
            if(VGACol < 256) begin
              pixel_out_4bit = debugB[31 - VGACol[7:3]] ? 4'd15 : 4'd1;
              if(VGACol[4:0] == 5'b0_0000)
                pixel_out_4bit = 4'd6;
            end
          end
 */
        end else begin
          pixel_out_4bit = 4'h0;
        end
        palettized = palette_lookup[pixel_out_4bit];
        vga_red <= palettized[7:5];
        vga_green <= palettized[4:2];
        vga_blue <= palettized[1:0];
      end
      //----------------------------------------------------------
      // Main state machine.
      //
      // Handle reading from vram and writing to line buffer.
      //----------------------------------------------------------
      if(1) begin // EPEP run on every cycle; if(clkdiv[0] == 1'b0) begin
        // By default read and write requests off
        ram_read_rq <= 1'b0;
        ram_write_rq <= 1'b0;

        // Collect any sprite coincidents over the current scanline.
        if (wr_coinc_pending && !mask_coinc_before_next_render) 
          sig_coinc_pending <= 1'b1; 

        if(VGARow == disp_rendr_slv && VGACol == {8'h00,2'b00})
          detect_frame_end <= 1'b1;

        if(VGARow == (({ypos,1'b0}) + disp_start) && VGACol == slv_760) 
          blanking <= 1'b0; // Remove blanking (only needed for first finished scanline but what the heck)

        if(VGARow == (({ypos,1'b0}) + disp_start) && VGACol == slv_760) begin
          detect_line_end <= 1'b1;
        end

        if (ram_read_ack)
          dbg_bytes_read_count <= dbg_bytes_read_count + 1;

        case(refresh_state)
        wait_frame : begin
          blanking <= 1'b1;
          if(detect_frame_end == 1'b1) begin            
            detect_frame_end <= 1'b0;
            detect_line_end  <= 1'b0;
            // start rendering
            refresh_state <= process_line;
            vga_bank <= 1'b0;
            xpos <= 7'd0;
            process_pixel <= setup_read_char;
            char_addr <= name_table_addr;
            char_addr_reload <= name_table_addr;
            vga_line_buf_addr <= 9'd0; 
            adv_line_buf_addr <= 1'b0;
            ypos <= {8{1'b0}};
            sprite_limit <= 0;
            // Debug counters
            dbg_bytes_read_total <= dbg_bytes_read_count;
            dbg_bytes_read_count <= 0;
          end else if (cpu_mem_read || cpu_mem_read_pending) begin 
             // Yield to CPU read if CPU wants to read
             vram_out_addr <= vram_addr;
             refresh_return_state <= refresh_state;
             refresh_state <= cpu_vram_read0;
             ram_read_rq <= 1'b1;
          end else if (cpu_mem_write || cpu_mem_write_pending) begin
             // CPU makes a write cycle to VRAM
             vram_out_addr <= vram_addr;
             refresh_return_state <= refresh_state;
             refresh_state <= cpu_vram_write0;
             ram_write_rq <= 1'b1;
          end
        end
        process_line : begin
          // here we read all the data for one scanline and write it to linebuffer.
          if(adv_line_buf_addr) begin
            vga_line_buf_addr <= vga_line_buf_addr + cell_width; // advance to next character cell.
            adv_line_buf_addr <= 1'b0;
          end


          case(process_pixel)
          setup_read_char : begin
            vram_out_addr <= char_addr;
            process_pixel <= read_char1;
            ram_read_rq <= 1'b1;
            ram_pipeline_reads <= 1'b1;  // Continue to own the bus
          end
          read_char1 : begin
            if(ram_read_ack == 1'b1) begin
              // now mem_data_in is the character code. Fetch from there the pattern.
              char_code = mem_data_in;  

              if(reg1[3] == 1'b1) begin
                // read M2, if set we have multicolor mode
                // multicolor mode
                vram_out_addr <= {reg4_9938,char_code,ypos[4:2]};
                // ignore two LSBs, "pixels" are four high
              end
              else if(reg0[1] == 1'b0) begin
                // read M3
                // Graphics mode 1 (actually anything else than graphics mode 2)
                vram_out_addr <= {reg4_9938,char_code,ypos[2:0]};
              end
              else begin
                // Graphics mode 2. 768 unique characters are possible.
                // Implement UNDOCUMENTED FEATURE: bits 1 and 0 of reg4 act as bit masks for the two
                // MSBs of the 10 bit char code. This allows character set to be limited even in this mode.
                vram_out_addr <= {reg4_9938[5:2],char_addr[9:8] & reg4_9938[1:0],char_code,ypos[2:0]};
                // 8 bit code and line in character
              end
              ram_read_rq <= 1'b1;
              process_pixel <= read_pattern;
            end
            ram_pipeline_reads <= 1'b1;  // Continue to own the bus once we get it
          end
          read_pattern : begin
            // if(ram_read_ack) begin
              // store pattern, and work out the address of the color byte
              // pattern will be ready in the next cycle in pipeline mode: char_pattern = mem_data_in; 
              if(reg0[1] == 1'b0) begin  // Graphics mode 1
                vram_out_addr <= {reg10[2:0], reg3,1'b0,char_code[7:3]};
              end
              else begin
                // Graphics mode 2
                // Implement UNDOCUMENTED FEATURE: bits 6 through 0 of reg3 act as bit masks for the seven
                // MSBs of the 10 bit char code. This allows character set to be limited even in this mode.
                vram_out_addr <= {reg10[2:0],reg3[7],{char_addr[9:8],char_code[7:3]} & reg3[6:0],char_code[2:0],ypos[2:0]};
              end
              process_pixel <= read_color;
              // now char addr is no longer used and we can increment to next.
              char_addr <= (char_addr) + 1;
              ram_read_rq <= 1'b1;
            // end    
            ram_pipeline_reads <= 1'b1;  // Continue to own the bus
          end
          read_color : begin
            // if(ram_read_ack) begin
              // Due to pipelining color only ready in the next cycle: color_data <= mem_data_in;
              // process_pixel <= write_pixels;
              process_pixel <= grab_pattern;
              pixel_count <= reg1[4] ? 6 : 8; // text mode if reg1[4] is set, character cells are 6 pixels wide
              sprite_out <= 1'b0;             // This is not a sprite.
            // end 
            ram_pipeline_reads <= 1'b1;  // Continue to own the bus
          end
          grab_pattern: begin
            char_pattern <= mem_data_in;  // Grab pattern, there is a delay due to pipelining
            process_pixel <= grab_color;
            ram_pipeline_reads <= 1'b1;  // Continue to own the bus
          end
          grab_color: begin
            color_data <= mem_data_in;
            process_pixel <= write_pixels;
            // Note here we drop pipelining
          end 
          write_pixels : begin
            // Read color data, and wait for the render shifter engine to become available.
            if(reg1[3] == 1'b1) begin       // read M2, if set we have multicolor mode
              // BUGBUG: we don't deal yet with transparency!
              color1 <= char_pattern[7:4]; // multicolor mode, char_pattern determines our colors
              color0 <= char_pattern[3:0];
            end else begin
              // In text mode, ignore VRAM data and use reg7. Otherwise (GM1,2) VRAM data.
              color1 <= reg1[4] ? reg7[7:4] : color_data[7:4];
              // If transparent or text mode user border color; otherwise VRAM data.
              color0 <= (color_data[3:0] == 4'b0000 || reg1[4] == 1'b1) ? reg7[3:0] : color_data[3:0];
            end 
            // Wait for write machine to be available, then proceed
            if(wr_pixel_count == 0) 
              process_pixel <= write_pixel_last;
            else begin
              // Here we have an opportunity to yield the VRAM bus to CPU reads and writes
              if (1) begin
                if (cpu_mem_read || cpu_mem_read_pending) begin 
                  // Yield to CPU read if CPU wants to read
                  vram_out_addr <= vram_addr;
                  refresh_return_state <= refresh_state;
                  refresh_state <= cpu_vram_read0;
                  ram_read_rq <= 1'b1;
                end else if (cpu_mem_write || cpu_mem_write_pending) begin
                  // CPU makes a write cycle to VRAM
                  vram_out_addr <= vram_addr;
                  refresh_return_state <= refresh_state;
                  refresh_state <= cpu_vram_write0;
                  ram_write_rq <= 1'b1;
                end              
              end
            end
          end
          write_pixel_last : begin
            pattern_out[15:8] <= reg1[3] ? 8'hf0 : char_pattern;  // Multicolor mode uses fixed pattern
            gogo <= ~gogo;
            process_pixel <= setup_read_char;
            // loop back this state machine
            xpos <= xpos + 7'd1;
            // In next clock (after gogo has read vga_line_buf_addr) advance to next char cell.
            adv_line_buf_addr <= 1'b1;  

            if(  (xpos == 7'd31 && reg1[4] == 1'b0 && !columns_80)  // normal 32 characters wide
              || (xpos == 7'd39 && reg1[4] == 1'b1 && !columns_80)  // ordinary text mode, 40 chars wide
              || (xpos == 7'd39 && reg1[4] == 1'b0 && columns_80)   // 64 characters mode (icy99 specific ?)
              || (xpos == 7'd79 && reg1[4] == 1'b1 && columns_80)   // 80 columns text mode, 80 characters wide
              ) begin
              xpos <= 7'd0;
              // Ignore sprites in text mode.
              refresh_state <= reg1[4] ? wait_line : process_sprites;
            end
          end
          endcase
        end
        process_sprites : begin
            // process sprites: first determine how many of them are active (0-32)
          // The highest numbered active sprite has the lowest priority - all others are 
          // drawn on top of it. Thus we need to find out how many sprites are active
          // and only draw them, from the highest numbered downwards.
          sprite_counter <= 5'b00000;
          // start from the lowest numbered sprite
          sprite_counter_next <= 5'b00001;
          refresh_state <= count_active_sprites;
          vram_out_addr <= {reg11[1:0], reg5[7:0],5'b00000,2'b00};
          // start reading sprite 0 Y-coordinate
          active_sprites <= {6{1'b0}};
          // Request external memory bus and enter pipelined mode.
          ram_read_rq <= 1'b1;
          mask_coinc_before_next_render <= 1'b0;  // Any upcoming sprite coincidents count
        end
        count_active_sprites : begin
          if(ram_read_ack == 1'b1) begin                
            if(mem_data_in == 8'hD0) begin
              // end of displayed sprites: display sprites with a lower number than this one.
              refresh_state <= sprite_next;
            end
            else begin
              // the coordinate was not the magical D0 (208) so go on and count higher.
              // Also count sprites which would be rendered for this line.
              sprite_yy = (mem_data_in[7:5] == 3'b111) ? {1'b0,mem_data_in} : {1'b1,mem_data_in};
              sprite_line_check = ({1'b1,ypos}) - (sprite_yy) - 1;
              if((reg1[1] == 1'b1 && sprite_line_check[8:4] == 5'b00000) || (reg1[1] == 1'b0 && sprite_line_check[8:3] == 6'b000000)) begin
                active_sprites <= (active_sprites) + 1;
                if(active_sprites == {2'b00,4'h4}) begin
                  // this would be the fifth sprite
                  sig_5th_pending <= 1'b1;
                  stat_reg0[4:0] <= sprite_counter;
                end
              end

              if(sprite_counter == 5'b11111) begin
                // all sprites are active, go and draw them
                refresh_state <= sprites_addr;
              end else begin
                // go fetch next.
                // Note here we do not change refresh state, we stay in this state while counting.
                sprite_counter <= sprite_counter_next;
                sprite_counter_next <= (sprite_counter_next) + 1;
                vram_out_addr <= {reg11[1:0], reg5[7:0],sprite_counter_next,2'b00};
                ram_read_rq <= 1'b1;
              end
            end
          end
        end
        sprites_addr : begin
          vram_out_addr <= {reg11[1:0], reg5[7:0],sprite_counter,2'b00};
          refresh_state <= sprite_read_vert;
          ram_read_rq <= 1'b1;
        end
        sprite_read_vert : begin
          if(ram_read_ack == 1'b1) begin                
            if(mem_data_in == 8'hD0) begin
              // vertical count D0 (208) stop immediately processing
              refresh_state <= wait_line;   // BUGBUG EPEP This does not really work, the code below overwrites this.
            end else begin
              if(mem_data_in[7:5] == 3'b111) begin
                sprite_y <= {1'b0,mem_data_in};
              end
              else begin
                sprite_y <= {1'b1,mem_data_in};
              end
              vram_out_addr <= {reg11[1:0], reg5[7:0],sprite_counter,2'b01};
              refresh_state <= sprite_read_horiz;
              ram_read_rq <= 1'b1;
            end
          end
        end
        sprite_read_horiz : begin
          if(ram_read_ack == 1'b1) begin                
            // sprite_line <= unsigned("1" & ypos) - unsigned("0" & sprite_y);
            sprite_line <= ({1'b1,ypos}) - (sprite_y) - 1;
            sprite_x <= mem_data_in;
            vram_out_addr <= {reg11[1:0], reg5[7:0],sprite_counter,2'b10};
            refresh_state <= sprite_read_char;
            ram_read_rq <= 1'b1;
          end
        end
        sprite_read_char : begin
          if(ram_read_ack == 1'b1) begin 
            // First condition for 16x16 and second for 8x8 sprite sizes.
            if((reg1[1] == 1'b1 && sprite_line[8:4] == 5'b00000) || (reg1[1] == 1'b0 && sprite_line[8:3] == 6'b000000)) begin
              sprite_name <= mem_data_in;
              vram_out_addr <= {reg11[1:0], reg5[7:0],sprite_counter,2'b11};
              refresh_state <= sprite_read_color;
              // active_sprites <= (active_sprites) + 1;
              // if(active_sprites == {2'b00,4'h4}) begin
              //   // this would be the fifth sprite
              //   sig_5th_pending <= 1'b1;
              //   stat_reg0[4:0] <= sprite_counter;
              // end
              ram_read_rq <= 1'b1;
            end else begin
              // sprite does not belong to this scanline. Either the offset is negative or beyound 15 ("1111")
              refresh_state <= sprite_next;
            end
          end
        end
        sprite_read_color : begin
          if(ram_read_ack == 1'b1) begin                        
            sprite_color <= mem_data_in;
            if(reg1[1] == 1'b1) begin
              // 16x16 sprite
              vram_out_addr <= {reg6[5:0],sprite_name[7:2],1'b0,sprite_line[3:0]};
            end
            else begin
              // 8x8 sprite
              vram_out_addr <= {reg6[5:0],sprite_name[7:0],sprite_line[2:0]};
            end
            refresh_state <= sprite_read_pattern0;
            ram_read_rq <= 1'b1;
          end
        end
        sprite_read_pattern0 : begin
          if(ram_read_ack == 1'b1) begin                        
            // if(sprite_color[3:0] == 4'b0000) begin
            //   sprite_pixels[15:8] <= 8'h00;
            //   // this sprite is transparent. Still need to "write" pixels to detect collisions
            // end
            // else begin
              sprite_pixels[15:8] <= mem_data_in;
            // end
            vram_out_addr <= {reg6[5:0],sprite_name[7:2],1'b1,sprite_line[3:0]};
            refresh_state <= sprite_read_pattern1;
            ram_read_rq <= 1'b1;
          end
        end
        sprite_read_pattern1 : begin
          if(ram_read_ack == 1'b1) begin                        
            //if(sprite_color[3:0] == 4'b0000) begin
            //  sprite_pixels[7:0] <= 8'h00;
            // end else begin
              sprite_pixels[7:0] <= mem_data_in;
            // end
            sprite_write_count <= {reg1[1],3'b111}; // 8x8: "0111", 16x16: "1111"
            refresh_state <= sprite_write_pattern_setup;
          end
        end
        sprite_write_pattern_setup : begin
          // Here setup the line buffer address.
          // Note that we stick in this state for as long as we can start writing pixels.
          if(sprite_color[7] == 1'b1) begin
            // early clock bit set. Now we need to figure out our address.
            $display("Early bit set, counter=%d", sprite_counter);
            if((sprite_x) >= 32) begin
              // just force bit 5 to zero to substract 32. This is bogus but we don't care
              vga_line_buf_addr <= {sprite_x[7:6],1'b0,sprite_x[4:0],1'b0};
            end else begin
              // Sprite bleeds in from the left
              vga_line_buf_addr <= 9'd0;
              sprite_early_clocks <= 6'd32-{ 1'b0, sprite_x[4:0] };
              $display("Setting sprite_early_clocks %d", sprite_early_clocks);
            end
          end else begin
            vga_line_buf_addr <= {sprite_x,1'b0}; // setup address normally
            sprite_early_clocks <= 6'd0;
          end

          // Start the machinery to write the sprite pattern to the scanline buffer
          if(wr_pixel_count == 0) begin
            refresh_state <= sprite_next;
            gogo <= ~gogo;
            color1 <= sprite_color[3:0];
            pixel_count <= reg1[1] ? 5'd16 : 5'd8 ; // 16x16 or 8x8 sprites
            pattern_out <= sprite_pixels;
            sprite_out <= 1'b1;
            sprite_limit <= sprite_limit + 1;
          end 
        end
        sprite_next : begin
          sprite_counter <= (sprite_counter) - 1;
          if(sprite_counter == 5'b00000 || sprite_limit >= 12) begin
            // if we were already at sprite zero we are done.
            refresh_state <= wait_line;
          end
          else begin
            // otherwise look at next sprite
            refresh_state <= sprites_addr;
          end
        end
        wait_line : begin
          if(detect_line_end == 1'b1) begin 
            detect_line_end <= 1'b0;
            sprite_early_clocks <= 6'd0;
            // we arrived at next line boundary, process it
            vga_bank <=  ~vga_bank;
            refresh_state <= process_line;
            vga_line_buf_addr <= 9'd0;
            adv_line_buf_addr <= 1'b0;
            sprite_limit <= 0;
            // Moved to detection of first line end. blanking <= 1'b0;
            if(ypos[2:0] != 3'b111) begin
              char_addr <= char_addr_reload;  // reload char ptr to beginning of line
            end
            else begin
              char_addr_reload <= char_addr;
            end
            ypos <= ypos + 1;
      
            if(ypos == last_scanline) begin
              blanking <= 1'b1;
              refresh_state <= wait_frame;
              stat_reg0[7] <= 1'b1; // make VDP interrupt pending
            end
            if(sig_coinc_pending == 1'b1) begin
              stat_reg0[5] <= 1'b1;  // set COINCinde flag (also set for transparent sprites)
              sig_coinc_pending <= 1'b0;
              mask_coinc_before_next_render <= 1'b1;  // Don't react to wr_coinc_pending before next time sprites start
            end
            if(sig_5th_pending == 1'b1) begin
              stat_reg0[6] <= 1'b1;
              sig_5th_pending <= 1'b0;
            end
          end else if (VGACol < slv_760-10'd32) begin
            // If we still have some time before the timing mark yield to CPU if necessary          
            if (cpu_mem_read || cpu_mem_read_pending) begin 
              // Yield to CPU read if CPU wants to read
              vram_out_addr <= vram_addr;
              refresh_return_state <= refresh_state;
              refresh_state <= cpu_vram_read0;
              ram_read_rq <= 1'b1;
            end else if (cpu_mem_write || cpu_mem_write_pending) begin
              // CPU makes a write cycle to VRAM
              vram_out_addr <= vram_addr;
              refresh_return_state <= refresh_state;
              refresh_state <= cpu_vram_write0;
              ram_write_rq <= 1'b1;
            end
          end
        end
        cpu_vram_read0: begin
          if(ram_read_ack) begin
            refresh_state <= refresh_return_state;
            mem_rd_bus <= mem_data_in;
            cpu_mem_read_pending <= 1'b0;
            cpu_read_already_done <= 1'b1;
            bump_rq <= 1'b1;
            cpu_read_cycle_ack <= 1'b1;
          end
        end
        cpu_vram_write0: begin  // Simply wait for the write cycle to get done.
          if(ram_write_ack) begin
            refresh_state <= refresh_return_state;
            cpu_mem_write_pending <= 1'b0;
            bump_rq <= 1'b1;
            cpu_write_cycle_ack <= 1'b1;
          end
        end 
        endcase
      end
    end
  end

  assign line_buf_addra = {~vga_bank,wr_render_addr};
  assign line_buf_addrb = {vga_bank,VGACol[8:0]};

  // Since the design was done for Xilinx which supports true dual port RAMs, 
  // on ICE40HX we need two RAMs so that we have the same capability (or actually even wider capability).
  // The other difference with ICE40HX is that the system runs on pixel clock, so the memory buses are occupied
  // on every cycle and we cannot multiplex reads from different addresses (except by halving the resolution of the
  // scanline buffer, which would be fine, but for now we keep this at VGA pixel size).
  // In the original design one port is used for rendering, i.e. to read and write pixels. 
  // Reading on the render port is used for sprite overlap detection.
  // The 2nd port is continuously used for VGA update.
  // Below we create two dual port RAMS, so that we have two independent read buffers.
  // For the second RAM we use a smaller 512 9-bit wide dual port RAM, since we only use it for rendering, we do not
  // need the banking feature needed for VGA update. We actually use only one bit of this buffer,
  // to detect sprite coincidence.
    wire not_used_8;

  dualport_par #(.WIDTH(9), .DEPTH(10)) LINEBUFFER(
    .clk_a(clk),
    .we_a(pixel_write),
    .addr_a(line_buf_addra),
    .din_a( {line_buf_bit8_in, vga_line_buf_in}),
    // Port B
    .clk_b(clk),
    .addr_b(line_buf_addrb),
    .dout_b( {not_used_8, vga_line_buf_out })
  );

  wire [7:0] not_user_7_0;
  dualport_par #(.WIDTH(9), .DEPTH(9)) RENDERBUFFER( 
    .clk_a(clk),
    .we_a(sprite_presence_write),
    .addr_a(line_buf_addra[8:0]),
    .din_a( {line_buf_bit8_in, vga_line_buf_in}),
    // Port B
    .clk_b(clk),
    .addr_b(line_buf_addra[8:0]),
    .dout_b( {line_buf_bit8_out, not_user_7_0 })
  );

`ifdef EXTERNAL_VRAM  
  // VRAM is external.
  assign xram_data_out  = data_in;
  assign xram_addr      = vram_out_addr;
  assign mem_data_in    = xram_data_in;
  assign xram_write_rq  = ram_write_rq;
  assign xram_read_rq   = ram_read_rq;
  assign xram_pipeline_reads = ram_pipeline_reads;
  assign ram_read_ack   = xram_read_ack;
  assign ram_write_ack  = xram_write_ack;
`else
  // Internal block RAM used for VRAM.
  assign xram_data_out  = 0;
  assign xram_addr      = 0;
  assign xram_write_rq  = 0;
  assign xram_read_rq   = 0;
  assign xram_pipeline_reads = 0;
  reg    [1:0] read_ack_delay = 2'b00;
  assign ram_read_ack = read_ack_delay[1];
  assign ram_write_ack  = 1;
    reg [7:0] ram_read_buffer;
  wire [7:0] ram_read_out;
  assign mem_data_in = ram_read_buffer;

  always @(posedge clk)
  begin 
    // Simulate external ram controller by delaying data reads.
     read_ack_delay <= { read_ack_delay[0], ram_read_rq };
    // Delay data output with one cycle
    ram_read_buffer <= ram_read_out;  
  end

  // VRAM extended to 64K
  dualport_par #(.WIDTH(8), .DEPTH(16)) FRAMEBUFFER (
    // Port A, write port
    .clk_a(clk),
    .we_a(ram_write_rq),
    .addr_a(vram_out_addr[15:0]),
    .din_a(data_in),  // The write data always comes from the CPU
    // Port B, our read port
    .clk_b(clk),
    .addr_b(vram_out_addr[15:0]),
    .dout_b(ram_read_out)  // Data read from VRAM goes always to mem_data_in bus.
  );
`endif
  
  VGA_SYNC vgadriver(
    .clk(clk),
    .video_on(video_on),
    .horiz_sync(Hsync),
    .vert_sync(Vsync),
    .pixel_row(VGARow),
    .pixel_column(VGACol2));

  assign vde = video_on;

endmodule
