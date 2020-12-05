// sys.v 
// EP (C) 2019
// Evolved into a full TI-99/4A verilog implementation.
// This is a platform neutral implementation of the TI-99/4A.
// It needs to be included into a toplevel file for a given FPGA platform.

module sys
#(parameter mem_supports_byte_writes=1,
  parameter external_bl32=0) 
(
    input clk, 
    output [3:0] LED, 
    input   tms9902_tx, 
    output  tms9902_rx, 
    output  RAMOE, 
    output  RAMWE, 
    output  RAMCS, 
    output  RAMLB, 
    output  RAMUB,
    output [22:0] ADR, 
    output addr_strobe,
    input  [15:0] sram_pins_din, 
    output [15:0] sram_pins_dout,
    output sram_pins_drive,
    input wire memory_busy,      // if set memory is busy, wait a cycle
    input wire use_memory_busy,  // if set memory_busy signal above is valid
    // Video output signals
    output wire [3:0] red, 
    output wire [3:0] green, 
    output wire [3:0] blue, 
    output wire       hsync, 
    output wire       vsync,
    // CPU Reset 
    input wire  cpu_reset_switch_n,
  `ifdef LCD_SUPPORT
    // LCD signals
    output wire pin_cs, 
    output wire pin_sdin, 
    output wire pin_sclk, 
    output wire pin_d_cn, 
    output wire pin_resn, 
    output wire pin_vccen, 
    output wire pin_pmoden,
  `endif
    // Serloader UART
    output wire serloader_tx, 
    input wire  serloader_rx, 
    // ULX3S Loading by ESP32 bootloader
    input   [31:0] xbootloader_addr,
    input          xbootloader_read_rq,
    output         xbootloader_read_ack,
    output   [7:0] xbootloader_din,
    input          xbootloader_write_rq,
    output         xbootloader_write_ack,
    input    [7:0] xbootloader_dout,
    // Misc
    output wire vde, // Video display enable (active area)
    input ps2clk, 
    input ps2dat,
    output wire f1_pressed,
    output wire [3:0] cursor_keys_pressed,
    // Audio
    output [7:0] audio,

    // TIPI signals
    output wire tipi_led0,
    // Raspberry PI interface for TIPI
    input wire  tipi_r_clk,   // input from Raspi, GPIO_6, SPI clock
    input wire  tipi_r_rt,    // input from Raspi, GPIO_13
    input wire  tipi_r_le,    // input from Raspi, GPIO_19
    output wire tipi_r_reset, // output to  Raspi, GPIO_26
    input wire  tipi_r_dout,  // input from Raspi, GPIO_16, SPI DATA from Raspi
    output wire tipi_r_din,   // output to  Raspi, GPIO_20, SPI data to Raspi
    input wire  tipi_r_dc     // input from Raspi, GPIO_21
  );

 
  wire rd, wr;
  wire [15:0] ab, db_out, db_in, xram_o;

 //-------------------------------------------------------------------
   // TIPI interface
  wire tipi_db_dir;
  wire tipi_db_en;
  wire [1:0] tipi_page;
  wire tipi_dsr_en;
  wire tipi_memen = ~(rd | wr); // active low
  wire [7:0] tipi_dout; // Note that for TIPI these are reversed
  wire cruin_tipi;
  wire tipi_ioreg_en;   // active low
  wire tipi_enabled;    // CRU 1100 is high
 //-------------------------------------------------------------------
 // Signals for SAMS (1MB memory expansion)
 wire [11:0] sams_dout;
 reg  sams_mapen; // SAMS mapping enabled
 wire sams_we;    // Write strobe for SAMS registers
 wire sams_rd;    // Read strobe for SAMS registers
 wire [11:0] sams_addr_out; // Translated address out from SAMS
 reg  sams_enabled; // SAMS enabled when CRU 1E00 is high (regs appear at 4000)
 //-------------------------------------------------------------------

  reg [31:0] debug_addr;
  wire RX = tms9902_rx; 

 //-------------------------------------------------------------------
 // Chip select generation
 //-------------------------------------------------------------------
  wire cartridge_cs = ab[15:13] == 3'b011;
  // wire nROMCE = !(ab[15:13] == 3'b000);  // low 8k is ROM
  wire nACACE = !(ab[15:8] == 8'h01);       // UART at CRU 0100
  wire nVDPCE = !((ab[15:8] == 8'h88 && rd) || (ab[15:8] == 8'h8c && wr));  // low VDP when selected
  // Map external RAM everywhere except 0000..1FFF and 8800..9FFF
  // wire nxRAMCE = !(ab[15:13] != 3'b000 && ab[15:12] != 4'd9 && ab[15:11] != 5'b1000_1); 
  wire n_9901CE = !(ab[15:8] == 8'h00);     // TMS9901 at address zero
  wire tipi_cs = (ab[15:13] == 3'b010) && tipi_enabled; // TIPI chip select in memory space
  wire sams_cs = (ab[15:13] == 3'b010) && sams_enabled; // SAMS chip select in memory space
  wire sams_cru_cs = ab[15:8] == 8'h1E; // SAMS chip select in CRU space
  wire mem_window_cs = ab[15:8] == 8'h85;
 //-------------------------------------------------------------------

  reg [15:0] mem_window_reg;

  // external RAM everywhere except on IO area. However, write protect low 8K (i.e. ROM)
  wire nxRAMCE = !(
    (ab[15:13] == 3'b000 && !wr) ||  // 0000..1fff    ROM read only
    ab[15:13] == 3'b001   ||    // 2000..3fff low 8k of extended 32K RAM
    tipi_cs   ||                // 4000..5FF8 TIPI DSR read
    (cartridge_cs && !wr) ||    // 6000..7FFF cartridge memory, read only
    ab[15:10] == 6'b1000_00 ||  // 8000..83ff scratchpad
    (ab[15:8] == 8'h98 && ab[1] == 1'b0) ||           // GROM read port
    mem_window_cs      ||       // 8500..85FF paged memory window
    ab[15:13] == 3'b101 ||      // A000..BFFF 8K of extended 32K RAM
    ab[15:14] == 2'b11);        // C000..FFFF 16K of extended 32K RAM

  wire sams_area_cs = // SAMS area overrides the above. 32K RAM expansion must also be mapped to SAMS region.
    ab[15:13] == 3'b001 ||      // 2000..3fff low 8k of extended 32K RAM
    ab[15:13] == 3'b101 ||      // A000..BFFF 8K of extended 32K RAM
    ab[15:14] == 2'b11;         // C000..FFFF 16K of extended 32K RAM

  // GROM control signals
  wire grom_wr = (wr && !last_wr && ab[15:8] == 8'h9c);
  wire grom_rd = (rd && ab[15:8] == 8'h98);
  wire [7:0] grom_o;
  wire grom_reg_out;  // Data read from GROM controller
  wire grom_selected; // Data read from GROM i.e. RAM
  wire [19:0] grom_addr;
  
  // CRU signals etc
  wire cruin, cruout, cruclk, xout, rin;
  wire cruin_9901, cruin_9902;
  wire nrts, ncts;
  wire int = 0;
  wire nmi = 0;
  wire hold;  

  // reset for a few clocks
  reg [15:0] reset_shifter = 0;
  wire reset = reset_shifter != 16'hff_ff;  // reset on until shifter is ffff
  reg [7:0] cpu_reset_ctrl = 8'hff;         // bit 0, if low, puts CPU to reset.

  always @(posedge clk) 
  begin 
    reset_shifter = { reset_shifter[14:0], 1'b1 };  // Shift in ones
  end

  wire cpu_reset = (cpu_reset_switch_n == 1'b0 || cpu_reset_ctrl[0] == 1'b0) ? 1 : reset; // cpu_reset_switch_n=0 forces CPU reset

 wire rd_now, iaq, as;
 reg cache_hit = 1'b0;
 // wire use_ready = 1'b0;
 wire n_int_req;
 wire int_req = !n_int_req;
 // reg int_req = 1'b0;
 reg [3:0] ic03 = 4'd1;
 wire int_ack;
 wire holda;
 wire stuck;
 reg [7:0] waits = 8'd0;
 wire cpu_rd_ack, cpu_wr_ack;
 
 wire vdp_wr, vdp_rd;
 wire cpu_vdp_rd_ack;
 wire cpu_vdp_wr_ack;

 reg keep_ready = 1'b0;
 wire use_ready = !nxRAMCE || !nVDPCE;
  //                                           external memory acks       ||               VDP acks
 wire ready_now = use_ready && ((!nxRAMCE && (cpu_wr_ack || cpu_rd_ack)) || (!nVDPCE && (cpu_vdp_wr_ack || cpu_vdp_rd_ack)));
 wire ready = ready_now || keep_ready;


 always @(posedge clk)
 begin
  // If we get an ack, remember that
  if (use_ready && ready_now)
    keep_ready = 1'b1;
  if (!rd && !wr)
    keep_ready = 1'b0;

  if(bootloader_read_ack)
    debug_addr <= ADR;
 end

 assign cruin = 
          !n_9901CE ? cruin_9901 : 
          !nACACE ? cruin_9902 : 
          cruin_tipi;

 wire [15:0] cpu_ir, cpu_ir_pc; // CPU instruction register, CPU program counter+2 at the time of the IR
 wire [15:0] cpu_ir_pc2;  // Also previous value of cpu_ir_pc
 
 reg [7:0] trace_addr = 8'h00;
 `ifdef TRACEBUFFER
 // Trace buffer to see what the heck the CPU is doing (typically before going to a grinding halt).
 // The trace buffer width is 36 bits. Top 4 bits are control (iaq, int_req, wr, rd) followed by data and finally address.
 // Data is CPU databus in for reads and databus out for writes.
 wire trace_we = rd_now || wr;
 reg last_trace_we = 1'b0;
 wire [35:0] trace_data_in = { iaq, int_req, wr, rd, wr ? db_out : db_in, ab};
 wire [35:0] trace_data_out;
 dualport_par #(36,8) tracebuf(clk, trace_we, trace_addr, trace_data_in, clk, bootloader_addr[10:3], trace_data_out);

 always @(posedge clk) begin
  last_trace_we <= trace_we;
  if (last_trace_we && !trace_we)
    trace_addr <= trace_addr + 8'd1;  // At the end of trace buffer write advance address.
 end
 `else
 // No tracebuffer.
 wire [35:0] trace_data_out = 36'd0;
 `endif

  tms9900 cpu(    
        clk, cpu_reset,
        ab,
        db_in,  db_out,
        rd,     wr,   rd_now,
        cache_hit,
        use_ready,
        ready,
        iaq, 
        as, 
        int_req,
        ic03,
        int_ack,
        cruin,  cruout, cruclk,
        hold,   holda,
        waits,
        stuck,
        cpu_ir,
        cpu_ir_pc,
        cpu_ir_pc2
  );

wire vdp_debug1, vdp_debug2;
wire vdp_int;
wire [2:0] vdp_red;
wire [2:0] vdp_green;
wire [1:0] vdp_blue;

assign red   = { vdp_red, vdp_red[0] };
assign green = { vdp_green, vdp_green[0] };
assign blue  = { vdp_blue, vdp_blue[0], vdp_blue[0] };

wire [15:0] vdp_data_out;

reg last_wr, last_rd;
always @(posedge clk) 
begin 
  last_wr <= wr;
  last_rd <= rd;
end

//---- LCD write bus -----
reg lcd_ram_wr;
reg [12:0] lcd_wr_addr;
wire [15:0] lcd_wr_data;

reg [9:0] xpos, ypos;

assign lcd_wr_data = { red, 1'b0, green, 2'b00, blue, 1'b0 };
reg last_hsync;

parameter HPOS=10'd78;
parameter VPOS=10'd42;

`define INVERT

always @(posedge clk) begin
  last_hsync <= hsync;
  if (vsync == 1'b0) begin
    `ifdef INVERT
    lcd_wr_addr <= 96*63+95; // Start of last line in frame buffer when inverting
    `else 
    lcd_wr_addr <= 13'd0;
    `endif
    xpos <= 10'd0;
    ypos <= 10'd0;
  end if (hsync == 1'b1 && last_hsync == 1'b0) begin
    ypos <= ypos + 8'd1;
    xpos <= 10'd0;
    // `ifdef INVERT
    // if(ypos[0] == 1'b0 && ypos >= VPOS)
    //   lcd_wr_addr <= lcd_wr_addr - 13'd192; // Substract two line lenghts to get to start of next
    // `endif
  end else begin
    xpos <= xpos + 1;
    if (xpos >= HPOS && xpos < (HPOS+2*10'd96) 
        && ypos >= VPOS && ypos < (VPOS+2*10'd64) 
        && xpos[0]==1'b0 && ypos[0]==1'b0) begin 
      // capture pixels inside the window, every other pixel both horizontally and vertically
      lcd_ram_wr <= 1'b1;
    end else begin
      lcd_ram_wr <= 1'b0;
    end 
    if (lcd_ram_wr) begin
    `ifdef INVERT
      lcd_wr_addr <= lcd_wr_addr - 13'd1;
    `else
      lcd_wr_addr <= lcd_wr_addr + 13'd1;
    `endif
    end
  end
end

//---- VDP Signals ----
assign vdp_wr = wr && !last_wr && ab[15:8] == 8'h8c;  // trigger on rising edge of wr
assign vdp_rd = rd && ab[15:8] == 8'h88;

wire [13:0] vdp_xmem_addr;
wire [7:0] vdp_xmem_data_out, vdp_xmem_data_in;
wire vdp_read_rq,  vdp_read_ack;
wire vdp_write_rq, vdp_write_ack;
wire vdp_pipeline_reads;

tms9918 vdp(
	.clk(clk),
	.reset(cpu_reset),  // used to be reset, now cpu_reset -> interrupts will be disabled
	.mode(ab[1]),
	.addr(ab[8:1]),
	.data_in(db_out[15:8]),
	.data_out(vdp_data_out),
	.wr(vdp_wr),
	.rd(vdp_rd),
  .cpu_read_cycle_ack(cpu_vdp_rd_ack),
  .cpu_write_cycle_ack(cpu_vdp_wr_ack),
	.vga_vsync(vsync),
	.vga_hsync(hsync),
	.debug1(vdp_debug1),
	.debug2(vdp_debug2),
	.int_out(vdp_int),
	.vga_red(vdp_red),
	.vga_green(vdp_green),
	.vga_blue(vdp_blue),
  .vde(vde),
  // interface to external memory
  .xram_addr(vdp_xmem_addr),
  .xram_data_out(vdp_xmem_data_in), 
  .xram_data_in(vdp_xmem_data_out),
  .xram_read_rq(vdp_read_rq),
  .xram_read_ack(vdp_read_ack),
  .xram_pipeline_reads(vdp_pipeline_reads),
  .xram_write_rq(vdp_write_rq),
  .xram_write_ack(vdp_write_ack),
  .debugA(bootloader_addr),
  .debugB(debug_addr)
);

  tms9902  aca(clk, nrts, 1'b0 /*dsr*/, ncts, /*int*/, nACACE, 
    cruout, cruin_9902, cruclk, xout, rin, ab[5:1]);

  assign db_in = vdp_rd ? vdp_data_out : 
                 grom_reg_out ? { grom_o, 8'h00 } :
                 (grom_selected && grom_addr[0] == 1'b1) ? { xram_o[ 7:0], 8'h00 } :  // GROM low byte
                 (grom_selected && grom_addr[0] == 1'b0) ? { xram_o[15:8], 8'h00 } :  // GROM high byte
                 (!grom_selected && ab[15:8] == 8'h98)   ? 16'hff00 :
                 (!tipi_ioreg_en) ? { 8'h00, tipi_dout } :
                 (ab[15:8] == 8'h86) ? mem_window_reg :
                 sams_rd ? { sams_dout[7:0], sams_dout[7:0] } :
                 nxRAMCE == 1'b0 ? xram_o :                                           // Normal reads 
                 16'd0;

  assign ncts  = nrts;
  assign tms9902_tx = xout ;
  assign rin   = RX;

  wire [15:0] tms9901_out, tms9901_dir;
  wire n_int7_p15, n_int8_p14, n_int9_p13, n_int10_p12;
  wire [15:0] pin_signals = { n_int7_p15, n_int8_p14, n_int9_p13, n_int10_p12, 
    1'b0, // cassette input
    1'b1, // pull up
     tms9901_out[9:2], 2'b0 };
    // tms9901_out; // { 12'hA50, tms9901_out[3:0]};
  wire [6:1] n_INT;


  tms9901 psi( .clk(clk), .n_reset(!cpu_reset), .n_ce(n_9901CE), 
    .cruin(cruout), .cruclk(cruclk), .cruout(cruin_9901),
    .S(ab[5:1]), .n_intreq(n_int_req), .n_INT(n_INT),
    .POUT(tms9901_out), .PIN(pin_signals), .DIR(tms9901_dir) 
  );

  assign LED[1:0] = tms9901_out[1:0]; // ab[6:1];
  assign LED[2] = cpu_reset_ctrl[0];
  assign LED[3] = stuck;

  reg bootloader_write_ack2 = 1'b0;
  reg bootloader_read_ack2 = 1'b0;


  //----------------------------------------------------------
  // handle memloader writes to the keyboard matrix
  //----------------------------------------------------------
  // keyboard state matrix
  reg [7:0] keyboard0, keyboard1, keyboard2, keyboard3, 
            keyboard4, keyboard5, keyboard6, keyboard7;
  reg [7:0] keyline;
  reg [7:0] bootloader_readback_reg;

  initial begin 
    // Initialize all keys to the up state.
    keyboard0 = 8'hff;
    keyboard1 = 8'hff;
    keyboard2 = 8'hff;
    keyboard3 = 8'hff;
    keyboard4 = 8'hff;
    keyboard5 = 8'hff;
    keyboard6 = 8'hff;
    keyboard7 = 8'hff;
  end


  always @(posedge clk)
  begin
    bootloader_write_ack2 <= 1'b0;
    bootloader_read_ack2 <= 1'b0;
    if (bootloader_write_rq && bootloader_addr[24]==1'b1) begin
      case (bootloader_addr[4:3])
        2'b00: begin  // Keyboard input
          case(bootloader_addr[2:0])
          3'd0: keyboard0 <= bootloader_dout;
          3'd1: keyboard1 <= bootloader_dout;
          3'd2: keyboard2 <= bootloader_dout;
          3'd3: keyboard3 <= bootloader_dout;
          3'd4: keyboard4 <= bootloader_dout;
          3'd5: keyboard5 <= bootloader_dout;
          3'd6: keyboard6 <= bootloader_dout;
          3'd7: keyboard7 <= bootloader_dout;
          endcase
          bootloader_write_ack2 <= 1'b1;
        end
        2'b01: begin  // CPU reset control
          cpu_reset_ctrl <= bootloader_dout;
          bootloader_write_ack2 <= 1'b1;
        end
        2'b10: bootloader_write_ack2 <= 1'b1;
        2'b11: bootloader_write_ack2 <= 1'b1;
      endcase
    end else if(bootloader_read_rq  && bootloader_addr[24]==1'b1) begin
      casez(bootloader_addr[11:0])
      // Keyboard matrix readback
      12'b0000_0000_0???: 
        begin
            case(bootloader_addr[2:0])
            3'd0: bootloader_readback_reg <= keyboard0;
            3'd1: bootloader_readback_reg <= keyboard1;
            3'd2: bootloader_readback_reg <= keyboard2;
            3'd3: bootloader_readback_reg <= keyboard3;
            3'd4: bootloader_readback_reg <= keyboard4;
            3'd5: bootloader_readback_reg <= keyboard5;
            3'd6: bootloader_readback_reg <= keyboard6;
            3'd7: bootloader_readback_reg <= keyboard7;
            endcase
        end
      // Reset control readback, cpu history registers
      12'b0000_0000_100?: bootloader_readback_reg <= cpu_reset_ctrl;
      12'b0000_0000_1010: bootloader_readback_reg <= cpu_ir[15:8];
      12'b0000_0000_1011: bootloader_readback_reg <= cpu_ir[7:0];
      12'b0000_0000_1100: bootloader_readback_reg <= cpu_ir_pc[15:8];
      12'b0000_0000_1101: bootloader_readback_reg <= cpu_ir_pc[7:0];
      12'b0000_0000_1110: bootloader_readback_reg <= cpu_ir_pc2[15:8];
      12'b0000_0000_1101: bootloader_readback_reg <= cpu_ir_pc2[7:0];
      // Tracebuffer, it has 256 entries, each entry is 8 bytes
      12'b1???_????_?00?: bootloader_readback_reg <= 8'h00;
      12'b1???_????_?010: bootloader_readback_reg <= trace_addr;
      12'b1???_????_?011: bootloader_readback_reg <= { 4'h0, trace_data_out[35:32] }; // control signals
      12'b1???_????_?100: bootloader_readback_reg <= trace_data_out[31:24];           // data high
      12'b1???_????_?101: bootloader_readback_reg <= trace_data_out[23:16];           // data low
      12'b1???_????_?110: bootloader_readback_reg <= trace_data_out[15:8];            // addr high
      12'b1???_????_?111: bootloader_readback_reg <= trace_data_out[7:0];             // addr low
      endcase
      bootloader_read_ack2 <= 1'b1; // Note: returned data is just shit
    end 
    case(tms9901_out[4:2])
    3'd0: keyline = keyboard0;
    3'd1: keyline = keyboard1;
    3'd2: keyline = keyboard2;
    3'd3: keyline = keyboard3;
    3'd4: keyline = keyboard4;
    3'd5: keyline = keyboard5;
    3'd6: keyline = keyboard6;
    3'd7: keyline = keyboard7;
    endcase
  end

  //----------------------------------------------------------
  // Route keyboard matrix data to TMS9901
  //----------------------------------------------------------
  wire [7:0] ps2_keyline;
  assign n_INT[1] = 1'b1;   // Peripheral interrupt
  assign n_INT[2] = ~vdp_int;
  assign n_INT[3]    = keyline[0] & ps2_keyline[0];
  assign n_INT[4]    = keyline[1] & ps2_keyline[1];
  assign n_INT[5]    = keyline[2] & ps2_keyline[2];
  assign n_INT[6]    = keyline[3] & ps2_keyline[3];
  assign n_int7_p15  = keyline[4] & ps2_keyline[4];  
  assign n_int8_p14  = keyline[5] & ps2_keyline[5];  
  assign n_int9_p13  = keyline[6] & ps2_keyline[6];  
  assign n_int10_p12 = keyline[7] & ps2_keyline[7];  

  //----------------------------------------------------------
  // external SRAM controller setup
  //----------------------------------------------------------
  reg [7:0] cart_page = 8'd0;
  // Paged cartridge area at address 2M. Support for 256 pages.
  // The size is thus 256*8K = 2M megs.
  wire [22:0] x_cart_addr     = {3'b001, cart_page, ab[12:1]};     
  wire [22:0] x_grom_addr     = {8'b0000_0001, grom_addr[15:1] };   // address of GROM in external memory
  wire [22:0] x_cpu_addr      = {8'b0000_0000, ab[15:1] };          // CPU RAM in external memory
  wire [22:0] x_tipi_dsr_addr = {9'b0000_0011_0, tipi_page[1:0], ab[12:1] };  // 32K TIPI ROM at 30000
  wire [22:0] x_window_addr   = {mem_window_reg, ab[7:1] };         // A window to all memory, 256 bytes at 8500
  wire [22:0] x_sams_addr     = {4'b0001, sams_addr_out[7:0], ab[11:1] }; // SAMS memory at 1 Megabyte
  
  always @(posedge clk)
  begin
    if(cpu_reset) begin
      cart_page <= 8'd0;
      mem_window_reg <= 16'd0;
    end else begin
      if (cartridge_cs && cpu_wr_rq) begin
        // write to cartride area. Store the page value from the ADDRESS bus.
        // This is the TI extended Basic banking scheme.
        cart_page <= ab[8:1];
      end
      if(ab[15:8] == 8'h86 && cpu_wr_rq) begin
        mem_window_reg <= db_out;
      end
    end
  end
  

  wire [22:0] xaddr_bus = grom_selected ? x_grom_addr : 
                          cartridge_cs  ? x_cart_addr :
                          tipi_cs       ? x_tipi_dsr_addr : 
                          mem_window_cs ? x_window_addr :
                          sams_area_cs  ? x_sams_addr :
                                          x_cpu_addr;

  // The code below does not seem to synthesize properly with yosys
  // wire [18:0] xaddr_bus = (ab[15:0] == 16'h9800) ? // grom_selected  ?  
  //   {4'b0001, grom_addr[15:1] } : 
  //   {4'b0000, ab[15:1] };  // Address from CPU
  wire MEM_n = !((rd || wr) && (!nxRAMCE || grom_selected)); // MEM_n now low when nxRAMCE is low and memory access on-going
  wire cpu_rd_rq = rd && !last_rd;   // When rd goes high issue read request
  wire cpu_wr_rq = wr && !last_wr;   // When wr goes high issue write request

  // Yosys can't handle bidirectional pins directly, need to handle them differently.
  wire [15:0] sram_pins_din;
  wire [15:0] sram_pins_dout;
  wire sram_pins_drive;
  `ifdef SIMULATE
    assign sram_pins_din = DAT;
    assign DAT = sram_pins_drive ? sram_pins_dout : 16'bz;
  `endif

  // External GROM controller
  gromext groms(
    .clk(clk), .reset(cpu_reset),
    .din(db_out[15:8]), .dout(grom_o),
    .selected(grom_selected), 
    .reg_out(grom_reg_out),
    .mode(ab[5:1]),
    .we(grom_wr), .rd(grom_rd),
    .addr(grom_addr)
  );

  // Serloader variables to be able to bootload this thing
  wire spi_miso, spi_rq;
  wire [31:0] sbootloader_addr;
  wire sbootloader_read_rq, sbootloader_write_rq;
  wire [7:0] sbootloader_din, sbootloader_dout;
  wire sbootloader_read_ack, sbootloader_write_ack;

  // Declare the actual bootloader signals. Either xbootloader or sbootloader is assigned to these.
  wire [31:0] bootloader_addr;
  wire bootloader_read_rq, bootloader_write_rq;
  wire [7:0] bootloader_din, bootloader_dout;
  wire bootloader_read_ack, bootloader_write_ack;

  // Declare and assign bootloader buses based on used bootloader
  assign bootloader_addr     = external_bl32 ? xbootloader_addr     : sbootloader_addr;
  assign bootloader_dout     = external_bl32 ? xbootloader_dout     : sbootloader_dout;
  assign bootloader_read_rq  = external_bl32 ? xbootloader_read_rq  : sbootloader_read_rq;
  assign bootloader_write_rq = external_bl32 ? xbootloader_write_rq : sbootloader_write_rq;
  // assign the acks based on which one is actually used
  assign xbootloader_read_ack  = external_bl32 ? bootloader_read_ack  : 1'b0;
  assign xbootloader_write_ack = external_bl32 ? bootloader_write_ack : 1'b0;
  assign sbootloader_read_ack  = external_bl32 ? 1'b0 : bootloader_read_ack ;
  assign sbootloader_write_ack = external_bl32 ? 1'b0 : bootloader_write_ack ;
  // Both fed with the same data from memory
  assign xbootloader_din     = bootloader_din;
  assign sbootloader_din     = bootloader_din;

  // General variables. 
  wire [7:0] bootloader_mem_din;
  wire bootloader_read_ack1, bootloader_write_ack1; // to/from xmemctrl
  assign hold = bootloader_read_rq || bootloader_write_rq;  
  assign bootloader_read_ack = bootloader_read_ack1 || bootloader_read_ack2;
  assign bootloader_write_ack = bootloader_write_ack1 || bootloader_write_ack2;
  assign bootloader_din = bootloader_addr[24] ? bootloader_readback_reg : bootloader_mem_din;

  wire serloader_reset = reset; //  | ~B2; // Serloader is reset with reset and when B2 is pressed

  serloader bootloader(
    .clk(clk), .rst(reset), .tx(serloader_tx), .rx(serloader_rx),
    .spi_cs_n(1'b1), .spi_clk(1'b1), .spi_mosi(1'b1), .spi_miso(spi_miso),  // not used right now
    .spi_rq(spi_rq),
    .mem_addr(sbootloader_addr), // 32 bit address bus
    .mem_data_out(sbootloader_dout), .mem_data_in(sbootloader_din),
    .mem_read_rq(sbootloader_read_rq), .mem_read_ack(sbootloader_read_ack),
    .mem_write_rq(sbootloader_write_rq), .mem_write_ack(sbootloader_write_ack)
  );

  // external memory controller
  xmemctrl #(mem_supports_byte_writes) xmem
  ( 
    .clock(clk), .reset(reset),
    .SRAM_DAT_out(sram_pins_dout), .SRAM_DAT_in(sram_pins_din), .SRAM_DAT_drive(sram_pins_drive),
    .SRAM_ADR(ADR),
    .addr_strobe(addr_strobe),
    .SRAM_CE(RAMCS), .SRAM_OE(RAMOE), .SRAM_WE(RAMWE), .SRAM_BE({ RAMUB, RAMLB}),
    .memory_busy(memory_busy), .use_memory_busy(use_memory_busy),
    // Mapped address bus from CPU
    .xaddr_bus(xaddr_bus), 
    // flash load port not used now. Set everything to zero.
    .flashDataOut(16'h0000), .flashAddrOut(18'h00000), .flashLoading(1'b0), .flashRamWE_n(1'b0),
    // CPU signals
    .cpu_holda(holda), .MEM_n(MEM_n),
    .data_from_cpu(db_out), .read_bus_o(xram_o), 
    .cpu_wr_rq(cpu_wr_rq), .cpu_rd_rq(cpu_rd_rq),
    .cpu_wr_ack(cpu_wr_ack), .cpu_rd_ack(cpu_rd_ack),
    // Signals for serloader, the memory controller.
    .mem_data_out(bootloader_dout), .mem_data_in(bootloader_mem_din), 
    .mem_addr(bootloader_addr), 
    .mem_read_rq(bootloader_read_rq), .mem_write_rq(bootloader_write_rq),
    .mem_read_ack_o(bootloader_read_ack1), .mem_write_ack_o(bootloader_write_ack1),
    // VDP memory access port
    .vdp_addr(vdp_xmem_addr),
    .vdp_data_out(vdp_xmem_data_out), .vdp_data_in(vdp_xmem_data_in),
    .vdp_read_rq(vdp_read_rq),  .vdp_read_ack(vdp_read_ack), 
    .vdp_pipeline_reads(vdp_pipeline_reads),
    .vdp_write_rq(vdp_write_rq), .vdp_write_ack(vdp_write_ack)
    );

`ifdef LCD_SUPPORT
  lcd_sys lcd_controller(clk, reset,
    pin_cs, pin_sdin, pin_sclk, pin_d_cn, pin_resn, pin_vccen, pin_pmoden,
    // LCD RAM buffer memory
    lcd_ram_wr,
    lcd_wr_addr,
    lcd_wr_data
    );
`endif

    ps2matrix kbd(.clk(clk), 
      .ps2clk(ps2clk), .ps2data(ps2dat), 
      .line_sel(tms9901_out[4:2]), .keyline(ps2_keyline),
      .f1_pressed(f1_pressed),
      .cursor_keys_pressed(cursor_keys_pressed)
      );

  wire audio_wr = wr && !last_wr && ab[15:8] == 8'h84;  // trigger on rising edge of wr

  tms9919 audio_generator(
    .clk(clk),
    .reset(reset),  // checkme
    .we(audio_wr),
    .data_in(db_out[15:8]),
    .dac_out(audio)
  );


  // Signals going to Raspi

  tipi_module tipi(
		.clk(clk),
		.led0(tipi_led0), // output
		
		.crub(4'h1),  // The base address of TIPI (address is >1X00, X given here)
		
    // outputs from TIPI to enable DSR ROM and select it's page
		// .db_dir(tipi_db_dir), // these are outputs - the db_dir is not relevant with FPGA
		.db_en(tipi_db_en),   // tipi pulls this low when accessing it
		.dsr_b0(tipi_page[0]),
		.dsr_b1(tipi_page[1]),
		.dsr_en(tipi_dsr_en),

    .ioreg_en(tipi_ioreg_en),  // Low when accessing memory mapped regs of TIPI
    .tipi_enabled(tipi_enabled),
		
    // Signals for raspberry PI
		.r_clk(tipi_r_clk),
		.r_cd(tipi_r_dc),     // 0 = Data or 1 = Control byte selection
		.r_dout(tipi_r_dout),
		.r_le(tipi_r_le),
		.r_rt(tipi_r_rt),     // R|T 0 = RPi or 1 = TI originating data 
		.r_din(tipi_r_din),
		.r_reset(tipi_r_reset),

    // TMS9900 signals
		.ti_cruclk(cruclk),
		.ti_dbin(rd),
		.ti_memen(tipi_memen),
		.ti_we(~wr),
		.ti_cruin(cruin_tipi),
    .ti_cruout(cruout),
		// .ti_extint(tipi_extint),
		
		.ti_a(ab[15:0]), // ab[0:15]),
		.ti_din(db_out[7:0]), // [0:7]),
    .ti_dout(tipi_dout[7:0]), // [0:7])    
  );

  // SAMS memory paging unit.
  // CRU interface. Two bits can be written.
  // 1E00 - sams_enabled (registers appear in memory space)
  // 1E02 - sams_mapen (memory translation i.e. mapping i.e. paging is on)
  reg last_cruclk;
  always @(posedge clk)
  begin
    last_cruclk <= cruclk;
    if (cpu_reset) begin
      sams_enabled <= 1'b0;
      sams_mapen <= 1'b0;
    end else if(!last_cruclk && cruclk && sams_cru_cs) begin
      // Write to SAMS CRU space
      if(ab[7:1] == 7'b0000_000)
        sams_enabled <= cruout;
      else if(ab[7:1] == 7'b0000_001)
        sams_mapen <= cruout;
    end
  end

  assign sams_we = wr && !last_wr && sams_cs;
  assign sams_rd = rd && sams_cs;

  pager612 sams(
    .clk(clk),
    .abus_high(ab[15:12]),
    .abus_low(ab[4:1]),
    .dbus_in({ 4'h0, db_out[15:8] }),
    .dbus_out(sams_dout),
    .mapen(sams_mapen),
    .write_enable(sams_we),
    .page_reg_read(sams_rd),
    .translated_addr(sams_addr_out),
    .access_regs(sams_cs)
  );

endmodule

