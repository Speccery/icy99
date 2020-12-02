// top_ulx3s.v 
// EP (C) 2020
// This is the toplevel for ULX3S board, based on FleaFPGA Ohm board.
// It instanciates the platform neutral sys.v which
// implements the TI-99/4A.

module top_ulx3s
#(
  // enable (set to 1) only one: c_dvi_v or c_vga2dvid_vhd
  parameter c_dvi_v        = 1,
  parameter c_vga2dvid_vhd = 0
)
(
  input  wire clk_25mhz,
  output wire [3:0] gpdi_dp,

  output wire usb_fpga_pu_dp, usb_fpga_pu_dn, 
  input  wire usb_fpga_dp, usb_fpga_dn,

  output wire [7:0]led,
  input  wire [6:0]btn,

  output wire flash_csn,  // ULX3S chip selects
  output wire adc_csn,

  output sdram_csn,       // chip select
  output sdram_clk,       // clock to SDRAM
  output sdram_cke,       // clock enable to SDRAM
  output sdram_rasn,      // SDRAM RAS
  output sdram_casn,      // SDRAM CAS
  output sdram_wen,       // SDRAM write-enable
  output [12:0] sdram_a,  // SDRAM address bus
  output  [1:0] sdram_ba, // SDRAM bank-address
  output  [1:0] sdram_dqm,// byte select
  inout  [15:0] sdram_d,  // data bus to/from SDRAM

  input  sd_clk, sd_cmd,
  inout   [3:0] sd_d,

  input         wifi_txd,
  output        wifi_rxd,  // SPI from ESP32
  input         wifi_gpio16,
  input         wifi_gpio5,
  output        wifi_gpio0,
  output        wifi_en,

  output wire   ftdi_rxd,   // output from FPGA to FTDI
  input  wire   ftdi_txd,   // input from FTDI to FPGA

  // for secondary serial port we could use
  // GND, GP27 (output) and GP26 (input)
  input  wire [24:0] gp, 
  output wire gp_25,
  output wire gp_26, 
  output wire gp_27
`ifdef LCD_SUPPORT
  ,
  output wire oled_clk,
  output wire oled_mosi,
  output wire oled_dc,
  output wire oled_resn,
  output wire oled_csn,
`endif
  // Audio DACs (4 bits with the ULX3S)
  output wire [3:0] audio_l,
  output wire [3:0] audio_r
);

  // Housekeeping logic for unwanted peripherals on ULX3S.
  assign flash_csn = 1'b1;  // Flash ROM disable.
  assign adc_csn   = 1'b1;
  assign wifi_en   = 1'b1;  // ESP32 enable
  //assign wifi_gpio0 = 1'b1;
  // enable pull ups on both D+ and D- on the USB / PS2 connector
  assign usb_fpga_pu_dp = 1'b1;
  assign usb_fpga_pu_dn = 1'b1;

  // clock generation
  wire clk_locked;
  wire [3:0] clocks;
  ecp5pll
  #(
      .in_hz( 25*1000000),
    .out0_hz(125*1000000),
    .out1_hz( 25*1000000),
    .out2_hz(125*1000000), .out2_deg(90)
  )
  ecp5pll_inst
  (
    .clk_i(clk_25mhz),
    .clk_o(clocks),
    .locked(clk_locked),

    .phasesel(2'b00),
    .phasedir(1'b0), 
    .phasestep(1'b0), 
    .phaseloadreg(1'b0)
  );
  wire pll_125mhz  = clocks[0]; // shift clock
  wire pll_25mhz   = clocks[1]; // pixel clock
  wire clk         = clocks[1]; // CPU and TI99/4A system
  wire clk_sdram   = clocks[0]; // SDRAM core

  // ===============================================================
  // Joystick for OSD control and games
  // ===============================================================

  wire f1_pressed;
  wire [3:0] cursor_keys_pressed;

  localparam C_reset_delay_bits=24;
  reg R_btn_resetn;
  reg [C_reset_delay_bits-1:0] R_reset_delay;
  reg [6:0] R_btn_joy;
  always @(posedge clk)
  begin
    R_btn_joy <= btn;
    // reliable start: after PLL lock, wait some delay and release reset
    R_btn_resetn <= btn[0] & R_reset_delay[C_reset_delay_bits-1];
    if(clk_locked)
    begin
      if(R_reset_delay[C_reset_delay_bits-1]==1'b0)
        R_reset_delay <= R_reset_delay+1;
    end
    else
      R_reset_delay <= 0;
  end

  // ===============================================================
  // SPI Slave for RAM and CPU control
  // ===============================================================
  wire        spi_ram_wr, spi_ram_rd;
  wire [31:0] spi_ram_addr;
  wire  [7:0] spi_ram_di;
  reg   [7:0] spi_ram_do;
  
  assign sd_d[0] = 1'bz;
  assign sd_d[3] = 1'bz; // FPGA pin pullup sets SD card inactive at SPI bus

  wire irq;
  spi_ram_btn
  #(
    .c_sclk_capable_pin(1'b0),
    .c_addr_bits(32)
  )
  spi_ram_btn_inst
  (
    .clk(clk),
    .csn(~wifi_gpio5),
    .sclk(wifi_gpio16),
    .mosi(sd_d[1]), // wifi_gpio4
    .miso(sd_d[2]), // wifi_gpio12
    .btn(R_btn_joy),
    .irq(irq),
    .wr(spi_ram_wr),
    .rd(spi_ram_rd),
    .addr(spi_ram_addr),
    .data_in(spi_ram_do),
    .data_out(spi_ram_di),
    .f1_pressed(f1_pressed),
    .cursor_keys_pressed(cursor_keys_pressed)
  );
  // Used for interrupt to ESP32
  assign wifi_gpio0 = ~irq;

  reg [7:0] R_cpu_control;
  always @(posedge clk) begin
    if (spi_ram_wr && spi_ram_addr[31:24] == 8'hFF) begin
      R_cpu_control <= spi_ram_di;
    end
  end
  
  reg  [31:0] bootloader_addr;
  reg         bootloader_read_rq = 0;
  wire        bootloader_read_ack;
  wire  [7:0] bootloader_din;
  reg         bootloader_write_rq = 0;
  wire        bootloader_write_ack;
  reg   [7:0] bootloader_dout;

  always @(posedge clk)
    if((spi_ram_rd || spi_ram_wr) && spi_ram_addr[31:24] == 8'h00)
      bootloader_addr <= spi_ram_addr;

  always @(posedge clk)
  begin
    if(bootloader_read_ack)
    begin
      bootloader_read_rq <= 0;
      spi_ram_do <= bootloader_din;
    end
    else
    begin
      if(spi_ram_rd && spi_ram_addr[31:24] == 8'h00)
      begin
        bootloader_read_rq <= 1;
      end
    end
  end

  always @(posedge clk)
  begin
    if(bootloader_write_ack)
      bootloader_write_rq <= 0;
    else
    begin
      if(spi_ram_wr && spi_ram_addr[31:24] == 8'h00)
      begin
        bootloader_write_rq <= 1;
        bootloader_dout <= spi_ram_di;
      end
    end
  end

  //------------------------------------------------------------
  // our SRAM
  wire [15:0] sram_pins_din, sram_pins_dout;
  wire sram_pins_drive;
  // SRAM pins
  wire RAMOE;
  wire RAMWE;
  wire RAMCS;
  wire RAMLB;
  wire RAMUB;
  wire [22:0] ADR;
  // Need to populate memory map with internal SRAM:
  // 8K  at 00000 system ROM
  // 8K  at 02000 low memory expansion - stored in SDRAM
  // 1K  at 08000 scratch pad
  // 24K at 0A000 high memory expansion - stored SDRAM
  // 32K at 10000 GROM space (system+8K for module)
  // 16K at 20000 VRAM
  // 64K at 40000 cartridge RAM
  // without 32K RAM expansion this amounts to 73K.
  // 5 blocks in total.

  // Since we need byte addressability we need 10 blocks. 
  // For the select signals, note that ADR has 16-bit word address, not byte address.
  // Thus ADR[14] is CPU A15.
  wire rom_sel = (ADR[22:12] == 11'b0000_0000_000);    //  8K @ 00000
  wire dsr_sel = (ADR[22:12] == 11'b0000_0000_010);    //  8K @ 04000
`ifndef PAD_IN_SDRAM  
  wire pad_sel = (ADR[22: 9] == 14'b0000_0000_1000_00);//  1K @ 08000 
`endif
  wire gro_sel = (ADR[22:15] == 8'b0000_0001);        // 64K @ 10000 (actually 56K)
  `ifdef EXTERNAL_VRAM
  wire vra_sel = (ADR[22:13] == 10'b0000_0010_00);     // 16K @ 20000
  `endif  
  // ram_sel is for RAM extension. 32K of RAM, 8K @ 2000 and 24K @ A000.
  wire ram_sel = (ADR[22:12] == 11'b0000_0000_001)    // 2000..3FFF 
              || (ADR[22:12] == 11'b0000_0000_101)    // A000..BFFF
              || (ADR[22:13] == 10'b0000_0000_11)     // C000..FFFF
              || (ADR[22:15] ==  8'b0000_0011)        // 30000..3FFFF DSR TIPI ROM (32K actually used)
              || (ADR[22:20] ==  3'b001)              // All cartridges mapped to 2M..4M area.
              || (ADR[22:19] ==  4'b0001)             // SAMS memory 1M to 2M
              || (ADR[22:20] ==  3'b010)              // just testing
`ifdef PAD_IN_SDRAM
              || (ADR[22: 9] == 14'b0000_0000_1000_00) //  1K @ 08000 
`endif              
              
              ; 

  // Note address bit numbering, we are dealing here with words addresses. Thus A0 is not high/low byte select.
  // In comments below A14 and A13 refer to TMS9900 address bits, with word addresses they are A13 and A12.
  // We will be using a contiguous block of 32K RAM, but the address bits above conflict with TMS9900 A14 and A13 as high bits.
  // Hence calculate top bits again. When addressing 2000 we set A14 and A13 to zero (16 bit addresses)
  wire [13:0]ram_exp_addr = { (ADR[14:12] == 3'b010) ? 2'b00 : ADR[13:12], ADR[11:0] };
 
  // ROM
  wire [7:0] rom_out_lo, rom_out_hi;
  rom16 #(16, 12, 8192/2, "roms/994arom.mem") sysrom(pll_25mhz, ADR[11:0], { rom_out_hi, rom_out_lo} );
  // SCRATCHPAD (here 1K not 256bytes)
`ifndef PAD_IN_SDRAM
  wire pad_we_lo = pad_sel && !RAMLB && !RAMWE;
  wire pad_we_hi = pad_sel && !RAMUB && !RAMWE;
  wire [7:0] pad_out_lo, pad_out_hi;
  dualport_par #(8, 9) pad_lb(pll_25mhz, pad_we_lo, ADR[ 8:0], sram_pins_dout[ 7:0], pll_25mhz, ADR[ 8:0], pad_out_lo);
  dualport_par #(8, 9) pad_hb(pll_25mhz, pad_we_hi, ADR[ 8:0], sram_pins_dout[15:8], pll_25mhz, ADR[ 8:0], pad_out_hi);
`endif

  // GROM 24K
  wire [7:0] gro_out_lo, gro_out_hi;
  rom16 #(16,14,24576/2,"roms/994agrom.mem") sysgrom(pll_25mhz, ADR[13:0], {gro_out_hi, gro_out_lo } );
  // GROM extension space for cartridges, so that we can load something in addition to system GROMs.
  // This space is 32K for the ULX3S, two 16K RAM blocks. Fills the range 6000..DFFF (here actually to FFFF).
  // A14-A13-A12
  // 011? :6,7
  // 100? :8,9
  // 101? :A,B
  // 110? :C,D
  // 111? :E,F wraps to 6,7
  wire [15:0] grom_ext_out;
  wire grom_ext_sel = gro_sel && (ADR[14:12] == 3'b011 || ADR[14:12] == 3'b100 || ADR[14:12] == 3'b101 || ADR[14:12] == 3'b110);  
  wire grom_ext_we_lo = grom_ext_sel && !RAMLB && !RAMWE;
  wire grom_ext_we_hi = grom_ext_sel && !RAMUB && !RAMWE;
  dualport_par #(8, 14) grom_ext_lb(pll_25mhz, grom_ext_we_lo, ADR[13:0], sram_pins_dout[ 7:0], pll_25mhz, ADR[13:0], grom_ext_out[7:0]);
  dualport_par #(8, 14) grom_ext_hb(pll_25mhz, grom_ext_we_hi, ADR[13:0], sram_pins_dout[15:8], pll_25mhz, ADR[13:0], grom_ext_out[15:8]);

  // RAM expansion, 32K.
  wire [15:0] ram_expansion_out;
`ifndef USE_SDRAM
  wire ram_exp_we_lo = ram_sel && !RAMLB && !RAMWE;
  wire ram_exp_we_hi = ram_sel && !RAMUB && !RAMWE;
  dualport_par #(8, 14) ram_exp_lb(pll_25mhz, ram_exp_we_lo, ram_exp_addr, sram_pins_dout[ 7:0], pll_25mhz, ram_exp_addr, ram_expansion_out[7:0]);
  dualport_par #(8, 14) ram_exp_hb(pll_25mhz, ram_exp_we_hi, ram_exp_addr, sram_pins_dout[15:8], pll_25mhz, ram_exp_addr, ram_expansion_out[15:8]);
`endif

`ifdef EXTERNAL_VRAM
  // VRAM 16K
  wire vra_we_lo = vra_sel && !RAMLB && !RAMWE;
  wire vra_we_hi = vra_sel && !RAMUB && !RAMWE;
  wire [7:0] vra_out_lo, vra_out_hi;
  dualport_par #(8,13) vra_lb(pll_125mhz, vra_we_lo, ADR[12:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[12:0], vra_out_lo);
  dualport_par #(8,13) vra_hb(pll_125mhz, vra_we_hi, ADR[12:0], sram_pins_dout[15:8], pll_125mhz, ADR[12:0], vra_out_hi);
`endif  

/*
  // DSR (total 8K for Device Service Routines like HEXBUS)
  wire [15:0] dsr_out;
  // SYS writes, SYS reads
  wire dsr_we_lo = dsr_sel && !RAMLB && !RAMWE;
  wire dsr_we_hi = dsr_sel && !RAMUB && !RAMWE;
  dualport_par #(8,12) dsr_lb(pll_25mhz, dsr_we_lo, ADR[11:0], sram_pins_dout[ 7:0], pll_25mhz, ADR[11:0], dsr_out[ 7:0]);
  dualport_par #(8,12) dsr_hb(pll_25mhz, dsr_we_hi, ADR[11:0], sram_pins_dout[15:8], pll_25mhz, ADR[11:0], dsr_out[15:8]);
*/
  wire addr_strobe;

`ifdef USE_SDRAM
  wire ram_exp_wr = ram_sel && !RAMWE;
  wire ram_exp_rd = ram_sel && !RAMOE;

  wire use_memory_busy = ram_exp_wr | ram_exp_rd;

  // First test. Keep memory busy active for 100 cycles.
  reg [6:0] busy_count = 7'h00;
  wire memory_busy = (|busy_count);

  wire my_as = addr_strobe & ram_sel; // Address strobe: Combinatorial
  reg  my_as_q;                       // Address strobe: Latched and thus delayed by one clock. It fixes SDRAM.
  wire sdram_done;

  // generate wait states for SDRAM access
  always @(posedge clk)
  begin 
    my_as_q <= my_as; // DEBUGGING: Delay the strobe issue to SDRAM controller by on cycle. 

    busy_count <= (|busy_count) ? busy_count - 7'd1 : 0;
    if (my_as)      busy_count <= 7'd100;
    if (sdram_done) busy_count <= 0; // stop the delay generator
  end

  // Debug signals
  // assign gp[0] = addr_strobe;
  // assign gp[1] = use_memory_busy;
  // assign gp[2] = ram_sel && !RAMWE;
  // assign gp[3] = my_as;
  // assign gp[6] = memory_busy;
  // assign gp[9] = RAMWE;
  // assign gp[12] = ram_sel;
  
  SDRAM sdram_i (
    .clk_in(clk_sdram),     // controller clock
    // interface to the SDRAM chip
    .sd_data(sdram_d),          // 16 bit databus
    .sd_addr(sdram_a),          // 13 bit multiplexed address bus
    .sd_dqm(sdram_dqm),         // two byte masks
    .sd_ba(sdram_ba),           // two banks
    .sd_cs(sdram_csn),          // chip select
    .sd_we(sdram_wen),          // write enable
    .sd_ras(sdram_rasn),        // row address select
    .sd_cas(sdram_casn),        // columns address select
    .sd_cke(sdram_cke),         // clock enable
    .sd_clk(sdram_clk),         // chip clock (inverted from input clk)
    // interface to TMS9900 et al
    .din(sram_pins_dout),        // data input from cpu
    .dout(ram_expansion_out),    // data output to cpu
    .ad({ 1'b0, ADR[22:0]}),     // 24 bit word address
    .as(my_as_q),               // address strobe (active low - start memory cycle)
    .nwr(RAMWE),                // cpu/chipset requests write
    .rst(~R_btn_resetn),        // cpu reset (active high)
    .ack(sdram_done)
  );

`else
  wire use_memory_busy = 1'b0;
  wire memory_busy = 1'b0;
`endif  

  // Data input multiplexer
  assign sram_pins_din = 
    rom_sel ? { rom_out_hi, rom_out_lo } :
`ifndef PAD_IN_SDRAM
    pad_sel ? { pad_out_hi, pad_out_lo } :
`endif
`ifdef EXTERNAL_VRAM    
    vra_sel ? { vra_out_hi, vra_out_lo } :
`endif    
    (gro_sel && !grom_ext_sel) ? { gro_out_hi, gro_out_lo } : // system GROM
    grom_ext_sel ? grom_ext_out :           // Cartridge GROM 32K
    ram_sel ? ram_expansion_out :
    16'h0000;

  // VGA
  wire [3:0] red, green, blue;
  wire hsync, vsync;

//-------------------------------------------------------------------

  wire clk = pll_25mhz;

  // need to implement SRAM here

  // Serial port assignments begin
  wire serloader_tx;
  wire tms9902_tx;
  
  `define SERIAL_TO_TMS9902
  // `define SERIAL_TO_ESP
  `ifndef SERIAL_TO_ESP
    `ifdef SERIAL_TO_TMS9902
      // Here our serial traffic goes to TMS9902
      wire tms9902_rx = ftdi_txd;
      assign ftdi_rxd = tms9902_tx;
      assign gp_27 = tms9902_tx;
      wire serloader_rx = 1'b1;   // serloader gets no data
      assign wifi_rxd = 1'b1;		  // let the ESP32 be silent for now.
    `else
      // Route serial port to the serloader component.
      wire serloader_rx = ftdi_txd;  // all incoming traffic goes to serloader 
      assign ftdi_rxd = serloader_tx; // send to FTDI chip  
      assign wifi_rxd = 1'b1;		  // let the ESP32 be silent for now.
    `endif
  `else
    wire serloader_rx = 1'b1;
    assign wifi_rxd = ftdi_txd; // passthru for esp32 micropython
    assign ftdi_rxd = wifi_txd;
  `endif

`ifndef SERIAL_TO_TMS9902  
  wire tms9902_rx = gp[26];   // receive from FTDI chip
  assign gp_27 = tms9902_tx;
`endif
  // wire serloader_rx = gp[26];     // serloader UART receive GPIO_3;
  // assign gp_27 = serloader_tx;   // serloader UART transit, was GPIO_2  on the FLEA OHM
  // wire tms9902_rx = ftdi_txd;   // receive from FTDI chip
  // assign ftdi_rxd = tms9902_tx; // send to FTDI chip
  // Serial port assignments end

  // PS2 keyboard - if there is signals from either port go with that.
  // The port should be pulled up, so I guess and operation should do the trick.
  wire ps2clk = usb_fpga_dp;
  wire ps2dat = usb_fpga_dn;

  wire [3:0] sys_LED;
  wire vde;

  assign led[0] = irq;
  assign led[3:1] = { sd_cmd, sd_clk, sd_d[3] & sd_d[0] }; // this should enable the pull-ups
  assign led[4] = tipi_led0;
  assign led[7:5] = sys_LED[3:1]; // LEDs from sys module. sys_LED[3] is the stuck signal.

  wire [7:0] audio;

  // Signals for Raspi interface
  wire tipi_r_clk= gp[20];    // input from Raspi, GPIO_6, SPI clock
  wire tipi_r_rt = gp[21];    // input from Raspi, GPIO_13
  wire tipi_r_le = gp[22];    // input from Raspi, GPIO_19
  wire tipi_r_dout = gp[23];   // input from Raspi, GPIO_16, SPI DATA from Raspi
  wire tipi_r_dc   = gp[24];   // input from Raspi, GPIO_21
  wire tipi_r_din;          // output to  Raspi, GPIO_20, SPI data to Raspi
  wire tipi_r_reset;        // output to  Raspi, GPIO_26
  // Assign signals to output pins
  assign gp_25 = tipi_r_reset;        // output to  Raspi, GPIO_26
  assign gp_26 = tipi_r_din;          // output to  Raspi, GPIO_20, SPI data to Raspi
  wire tipi_led0;           // TIPI status LED (DSR enabled)

`ifdef LCD_SUPPORT
  wire pin_cs, pin_sdin, pin_sclk, pin_d_cn, pin_resn, pin_vccen, pin_pmoden;
  assign oled_clk = pin_sclk;
  assign oled_mosi = pin_sdin;
  assign oled_dc = pin_d_cn;
  assign oled_resn = pin_resn;
  assign oled_csn = pin_cs;
`endif
  // With ULX3S and current SDRAM controller we don't support byte writes. We could, but this is
  // a good case to test. Hence we pass the parameter zero.
  sys #(0,1) ti994a (
  	.clk(clk), 
  	.LED(sys_LED), 
    .tms9902_tx(tms9902_tx),
    .tms9902_rx(tms9902_rx),
    .RAMOE(RAMOE),
    .RAMWE(RAMWE),
    .RAMCS(RAMCS),
    .RAMLB(RAMLB),
    .RAMUB(RAMUB),
    .ADR(ADR),
    .addr_strobe(addr_strobe),
    .sram_pins_din(sram_pins_din),
    .sram_pins_dout(sram_pins_dout),
    .sram_pins_drive(sram_pins_drive),
    .memory_busy(memory_busy), 
    .use_memory_busy(use_memory_busy),
    .red(red), .green(green), .blue(blue),
    .hsync(hsync), .vsync(vsync), .vde(vde), // video display enable signal
    .cpu_reset_switch_n(R_btn_resetn),  // cpu_reset_switch_n
`ifdef LCD_SUPPORT
    // LCD signals
    .pin_cs(pin_cs),
    .pin_sdin(pin_sdin),
    .pin_sclk(pin_sclk),
    .pin_d_cn(pin_d_cn),
    .pin_resn(pin_resn),
    .pin_vccen(pin_vccen),
    .pin_pmoden(pin_pmoden),
`endif
    // bootloader UART
    .serloader_tx(serloader_tx), 
    .serloader_rx(serloader_rx),
    // external bootloader
    .xbootloader_addr(bootloader_addr),
    .xbootloader_read_rq(bootloader_read_rq),
    .xbootloader_read_ack(bootloader_read_ack),
    .xbootloader_din(bootloader_din),
    .xbootloader_write_rq(bootloader_write_rq),
    .xbootloader_write_ack(bootloader_write_ack),
    .xbootloader_dout(bootloader_dout),
    // PS/2 keyboard
    .ps2clk(ps2clk), .ps2dat(ps2dat),
    // F1 key state
    .f1_pressed(f1_pressed),
    .cursor_keys_pressed(cursor_keys_pressed),
    // audio DAC put
    .audio(audio),

    .tipi_led0(tipi_led0),
    // Raspberry PI interface for TIPI
    .tipi_r_clk(tipi_r_clk),    
    .tipi_r_rt(tipi_r_rt),      // input from Raspi, GPIO_13
    .tipi_r_le(tipi_r_le),      // input from Raspi, GPIO_19
    .tipi_r_reset(tipi_r_reset),// output to  Raspi, GPIO_26
    .tipi_r_dout(tipi_r_dout),  // input from Raspi, GPIO_16, SPI DATA from Raspi
    .tipi_r_din(tipi_r_din),    // output to  Raspi, GPIO_20, SPI data to Raspi
    .tipi_r_dc(tipi_r_dc)       // input from Raspi, GPIO_21

  );
  assign audio_l = audio[7:4];
  assign audio_r = audio[7:4];  

  wire [7:0] red_out   = { red,   4'h0 };
  wire [7:0] green_out = { green, 4'h0 };
  wire [7:0] blue_out  = { blue,  4'h0 };

  wire hsyn = ~hsync;
  wire vsyn = ~vsync;

  // ===============================================================
  // SPI Slave for OSD display
  // ===============================================================

  wire [7:0] osd_vga_r, osd_vga_g, osd_vga_b;
  wire osd_vga_hsync, osd_vga_vsync, osd_vga_blank;
  spi_osd
  #(
    .c_start_x(62), .c_start_y(80),
    .c_chars_x(64), .c_chars_y(20),
    .c_init_on(0),
    .c_transparency(1),
    .c_char_file("osd/osd.mem"),
    .c_font_file("osd/font_bizcat8x16.mem")
  )
  spi_osd_inst
  (
    .clk_pixel(pll_25mhz), .clk_pixel_ena(1),
    .i_r(  red_out),
    .i_g(green_out),
    .i_b( blue_out),
    .i_hsync(hsyn), .i_vsync(vsyn), .i_blank(~vde),
    .i_csn(~wifi_gpio5), .i_sclk(wifi_gpio16), .i_mosi(sd_d[1]), // .o_miso(),
    .o_r(osd_vga_r), .o_g(osd_vga_g), .o_b(osd_vga_b),
    .o_hsync(osd_vga_hsync), .o_vsync(osd_vga_vsync), .o_blank(osd_vga_blank)
  );

  wire [1:0] tmds[3:0];
  generate
  if(c_dvi_v)
  DVI_out
  #(
    .generic_ddr(0),
    .ecp5_ddr(1)
  )
  DVI_out_i
  (
    .pixclk(pll_25mhz),
    .pixclk_x5(pll_125mhz),
    .red(osd_vga_r),
    .green(osd_vga_g),
    .blue(osd_vga_b), 
    .vde(~osd_vga_blank),
    .hSync(osd_vga_hsync),
    .vSync(osd_vga_vsync),
    .tmds_c(tmds[3]),
    .tmds_r(tmds[2]),
    .tmds_g(tmds[1]),
    .tmds_b(tmds[0])
  );
  if(c_vga2dvid_vhd)
  // VGA to digital video converter
  vga2dvid
  #(
    .C_ddr(1'b1),
    .C_shift_clock_synchronizer(1'b0)
  )
  vga2dvid_instance
  (
    .clk_pixel(pll_25mhz),
    .clk_shift(pll_125mhz),
    .in_red(osd_vga_r),
    .in_green(osd_vga_g),
    .in_blue(osd_vga_b),
    .in_hsync(osd_vga_hsync),
    .in_vsync(osd_vga_vsync),
    .in_blank(osd_vga_blank),
    .out_clock(tmds[3]),
    .out_red(tmds[2]),
    .out_green(tmds[1]),
    .out_blue(tmds[0])
  );
  endgenerate

  ODDRX1F ddr0_clock (.D0(tmds[3][0]), .D1(tmds[3][1]), .Q(gpdi_dp[3]), .SCLK(pll_125mhz), .RST(0));
  ODDRX1F ddr0_red   (.D0(tmds[2][0]), .D1(tmds[2][1]), .Q(gpdi_dp[2]), .SCLK(pll_125mhz), .RST(0));
  ODDRX1F ddr0_green (.D0(tmds[1][0]), .D1(tmds[1][1]), .Q(gpdi_dp[1]), .SCLK(pll_125mhz), .RST(0));
  ODDRX1F ddr0_blue  (.D0(tmds[0][0]), .D1(tmds[0][1]), .Q(gpdi_dp[0]), .SCLK(pll_125mhz), .RST(0));



endmodule
