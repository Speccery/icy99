// top_flea.v 
// EP (C) 2019
// This is the toplevel for FleaFPGA Ohm board.
// It instanciates the platform neutral sys.v which
// implements the TI-99/4A.

// The following macros enable placement of ROM contents to SDRAM to save internal block RAM.
`ifdef USE_SDRAM
// If SDRAM is not configured, everything must be internally stored.
// `define CONSOLE_GROM_IN_SDRAM 0   // 24K - KEEP IN BLOCK RAM
`define CART_GROM_IN_SDRAM    1   // 32K - PUT IN SDRAM
// `define CONSOLE_ROM_IN_SDRAM  0   // 8K - KEEP IN BLOCK RAM
`define PAD_IN_SDRAM_TEST     1   // 1K - TEST SCRATCHPAD IN SDRAM (for testing only)
`endif

module fleatop
(
  input  wire clk_25mhz,
  output wire [0:0] LVDS_Red, LVDS_Green, LVDS_Blue, LVDS_ck,
  output wire PS2_enable,
  input  wire usb_fpga_dp, usb_fpga_dn,
  output wire mmc_n_cs,
  output wire n_led1,
  output wire slave_tx_o,
  input  wire slave_rx_i,
  output wire GPIO_2,   // pin 3 on Raspi header
  input  wire GPIO_3,   // pin 5 on Raspi header
  input  wire ps2_clk2, 
  input  wire ps2_data2,

  // SDRAM interface - always included, but only used if USE_SDRAM is defined
  output wire sdram_csn,       // chip select
  output wire sdram_clk,       // clock to SDRAM
  output wire sdram_cke,       // clock enable to SDRAM
  output wire sdram_rasn,      // SDRAM RAS
  output wire sdram_casn,      // SDRAM CAS
  output wire sdram_wen,       // SDRAM write-enable
  output wire [12:0] sdram_a,  // SDRAM address bus
  output wire  [1:0] sdram_ba, // SDRAM bank-address
  output wire  [1:0] sdram_dqm,// byte select
  inout  wire [15:0] sdram_d   // data bus to/from SDRAM
);

  // Housekeeping logic for unwanted peripherals on FleaFPGA Ohm board goes here..
`ifndef USE_SDRAM
  // When SDRAM is not used, drive all signals to inactive states.
  assign sdram_csn = 1'b 1;     // DRAM Chip disable.
  assign sdram_clk = 1'b 0;     // DRAM Clock low.
  assign sdram_cke = 1'b 0;     // DRAM Clock disable.
  assign sdram_rasn = 1'b 1;    // DRAM RAS high.
  assign sdram_casn = 1'b 1;    // DRAM CAS high.
  assign sdram_wen = 1'b 1;     // DRAM WE high.
  assign sdram_a = 12'b 0;      // DRAM address bus
  assign sdram_ba = 2'b 0;      // DRAM bank-address
  assign sdram_dqm = 2'b 0;     // byte select
  assign sdram_d = 16'bz;      // data bus to/from SDRAM
`endif
  assign mmc_n_cs = 1'b 1;    // Micro SD card chip disable.
  assign PS2_enable = 1'b 1;  // Configures both USB host ports for legacy PS/2 mode.

  // clock generation
  wire pll_250mhz, pll_125mhz, pll_25mhz;

  clk_25_250_125_25 clk_pll (
    .clki(clk_25mhz),
    .clko(pll_250mhz),
    .clks1(pll_125mhz),
    .clks2(pll_25mhz)
  );

  wire clk = pll_25mhz;         // CPU and TI99/4A system
  wire clk_sdram = pll_125mhz;  // SDRAM core

  // Reset logic similar to ULX3S
  localparam C_reset_delay_bits=24;
  wire clk_locked;
  assign clk_locked = 1'b1; // Assume PLL is always locked for Flea
  reg R_btn_resetn = 1'b0;
  reg [C_reset_delay_bits-1:0] R_reset_delay = 0;
  
  always @(posedge clk)
  begin
    // reliable start: after PLL lock, wait some delay and release reset
    R_btn_resetn <= R_reset_delay[C_reset_delay_bits-1];
    if(clk_locked)
    begin
      if(R_reset_delay[C_reset_delay_bits-1]==1'b0)
        R_reset_delay <= R_reset_delay+1;
    end
    else
      R_reset_delay <= 0;
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
  // -- 8K  at 02000 low memory expansion
  // 1K  at 08000 scratch pad
  // -- 24K at 0A000 high memory expansion
  // 32K at 10000 GROM space (system+8K for module)
  // 16K at 20000 VRAM : This is instantiated in tms9918.v since we have not defined EXTERNAL_VRAM
  // 16K at 40000 cartridge RAM
  // without 32K RAM expansion this amounts to 73K.
  // 5 blocks in total.

  // Since we need byte addressability we need 10 blocks. 
  // For the select signals, note that ADR has 16-bit word address, not byte address.
  // Thus ADR[14] is CPU A15.
  wire rom_sel = (ADR[22:12] == 11'b0000_0000_000);    //  8K @ 00000
`ifndef PAD_IN_SDRAM_TEST  
  wire pad_sel = (ADR[22: 9] == 14'b0000_0000_1000_00);//  1K @ 08000 
`endif
  wire gro_sel = (ADR[22:14] == 9'b0000_0001_0);      // 32K @ 10000
  wire car_sel = (ADR[22:13] == 10'b0000_0100_00);     // 16K @ 40000

  // GROM extension space for cartridges, so that we can load something in addition to system GROMs.
  // This space is 32K for the FleaFPGA, two 16K RAM blocks. Fills the range 6000..DFFF (here actually to FFFF).
  // A14-A13-A12
  // 011? :6,7
  // 100? :8,9
  // 101? :A,B
  // 110? :C,D
  // 111? :E,F wraps to 6,7
  wire grom_ext_sel = gro_sel && (ADR[14:12] == 3'b011 || ADR[14:12] == 3'b100 || ADR[14:12] == 3'b101 || ADR[14:12] == 3'b110);  

  // ram_sel is for RAM extension. 32K of RAM, 8K @ 2000 and 24K @ A000.
  wire ram_sel = (ADR[22:12] == 11'b0000_0000_001)    // 2000..3FFF 
              || (ADR[22:15] ==  8'b0000_0000)        // A000..FFFF, note overlaps above
`ifdef CONSOLE_ROM_IN_SDRAM
              || rom_sel
`endif
`ifdef PAD_IN_SDRAM_TEST
              || (ADR[22: 9] == 14'b0000_0000_1000_00) //  1K @ 08000 
`endif 
`ifdef CONSOLE_GROM_IN_SDRAM
              || (gro_sel && !grom_ext_sel)
`endif   
`ifdef CART_GROM_IN_SDRAM
              || grom_ext_sel
`endif          
              ; 

  // Note address bit numbering, we are dealing here with words addresses. Thus A0 is not high/low byte select.
  // In comments below A14 and A13 refer to TMS9900 address bits, with word addresses they are A13 and A12.
  // We will be using a contiguous block of 32K RAM, but the address bits above conflict with TMS9900 A14 and A13 as high bits.
  // Hence calculate top bits again. When addressing 2000 we set A14 and A13 to zero (16 bit addresses)
  wire [13:0]ram_exp_addr = { (ADR[14:12] == 3'b010) ? 2'b00 : ADR[13:12], ADR[11:0] };
 
  // ROM
`ifndef CONSOLE_ROM_IN_SDRAM
  wire [7:0] rom_out_lo, rom_out_hi;
  rom16 #(16, 12, 8192/2, "roms/994arom.mem") sysrom(pll_125mhz, ADR[11:0], { rom_out_hi, rom_out_lo} );
`endif
  /*
  wire rom_we_lo = rom_sel && !RAMLB && !RAMWE;
  wire rom_we_hi = rom_sel && !RAMUB && !RAMWE;
  dualport_par #(8,12) rom_lb(pll_125mhz, rom_we_lo, ADR[11:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[11:0], rom_out_lo);
  dualport_par #(8,12) rom_hb(pll_125mhz, rom_we_hi, ADR[11:0], sram_pins_dout[15:8], pll_125mhz, ADR[11:0], rom_out_hi);
  */
  // SCRATCHPAD (here 1K not 256bytes)
`ifndef PAD_IN_SDRAM_TEST
  wire pad_we_lo = pad_sel && !RAMLB && !RAMWE;
  wire pad_we_hi = pad_sel && !RAMUB && !RAMWE;
  wire [7:0] pad_out_lo, pad_out_hi;
  dualport_par #(8, 9) pad_lb(pll_125mhz, pad_we_lo, ADR[ 8:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[ 8:0], pad_out_lo);
  dualport_par #(8, 9) pad_hb(pll_125mhz, pad_we_hi, ADR[ 8:0], sram_pins_dout[15:8], pll_125mhz, ADR[ 8:0], pad_out_hi);
`endif

`ifndef CONSOLE_GROM_IN_SDRAM
  // GROM 24K
  wire [7:0] gro_out_lo, gro_out_hi;
  rom16 #(16,14,24576/2,"roms/994agrom.mem") sysgrom(pll_125mhz, ADR[13:0], {gro_out_hi, gro_out_lo } );
`endif 
  /*
  wire gro_we_lo = gro_sel && !RAMLB && !RAMWE;
  wire gro_we_hi = gro_sel && !RAMUB && !RAMWE;
  dualport_par #(8,14) gro_lb(pll_125mhz, gro_we_lo, ADR[13:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[13:0], gro_out_lo);
  dualport_par #(8,14) gro_hb(pll_125mhz, gro_we_hi, ADR[13:0], sram_pins_dout[15:8], pll_125mhz, ADR[13:0], gro_out_hi);
  */
  // GROM extension space for cartridges, so that we can load something in addition to system GROMs.
  // This space is 32K for the FleaFPGA, two 16K RAM blocks. Fills the range 6000..DFFF (here actually to FFFF).
  // For FleaFPGA Ohm with limited block RAM, we comment this out initially and will add it via SDRAM
  /*
`ifndef CART_GROM_IN_SDRAM
  wire [15:0] grom_ext_out;
  wire grom_ext_we_lo = grom_ext_sel && !RAMLB && !RAMWE;
  wire grom_ext_we_hi = grom_ext_sel && !RAMUB && !RAMWE;
  dualport_par #(8, 14) grom_ext_lb(pll_125mhz, grom_ext_we_lo, ADR[13:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[13:0], grom_ext_out[7:0]);
  dualport_par #(8, 14) grom_ext_hb(pll_125mhz, grom_ext_we_hi, ADR[13:0], sram_pins_dout[15:8], pll_125mhz, ADR[13:0], grom_ext_out[15:8]);
`endif
  */

  // RAM expansion, 32K.
  wire [15:0] ram_expansion_out;
`ifndef USE_SDRAM
  wire ram_exp_we_lo = ram_sel && !RAMLB && !RAMWE;
  wire ram_exp_we_hi = ram_sel && !RAMUB && !RAMWE;
  dualport_par #(8, 14) ram_exp_lb(pll_125mhz, ram_exp_we_lo, ram_exp_addr, sram_pins_dout[ 7:0], pll_125mhz, ram_exp_addr, ram_expansion_out[7:0]);
  dualport_par #(8, 14) ram_exp_hb(pll_125mhz, ram_exp_we_hi, ram_exp_addr, sram_pins_dout[15:8], pll_125mhz, ram_exp_addr, ram_expansion_out[15:8]);
`endif

  // CARTRIDGE (paged, here 2 pages total 16K)
  wire car_we_lo = car_sel && !RAMLB && !RAMWE;
  wire car_we_hi = car_sel && !RAMUB && !RAMWE;
  wire [7:0] car_out_lo, car_out_hi;
  dualport_par #(8,13) car_lb(pll_125mhz, car_we_lo, ADR[12:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[12:0], car_out_lo);
  dualport_par #(8,13) car_hb(pll_125mhz, car_we_hi, ADR[12:0], sram_pins_dout[15:8], pll_125mhz, ADR[12:0], car_out_hi);

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
    my_as_q <= my_as; // DEBUGGING: Delay the strobe issue to SDRAM controller by one cycle. 

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
`ifndef CONSOLE_ROM_IN_SDRAM
    rom_sel ? { rom_out_hi, rom_out_lo } :
`endif
`ifndef PAD_IN_SDRAM_TEST
    pad_sel ? { pad_out_hi, pad_out_lo } :
`endif
`ifndef CONSOLE_GROM_IN_SDRAM
    (gro_sel && !grom_ext_sel) ? { gro_out_hi, gro_out_lo } : // system GROM
`endif
/*
`ifndef CART_GROM_IN_SDRAM
    grom_ext_sel ? grom_ext_out :           // Cartridge GROM 32K
`endif
*/
    ram_sel ? ram_expansion_out :
    car_sel ? { car_out_hi, car_out_lo } :
    16'h0001;  // 0001 if nothing selected

  // VGA
  wire [3:0] red, green, blue;
  wire hsync, vsync;

//-------------------------------------------------------------------

  // Serial port assignments begin
  // wire serloader_rx = slave_rx_i;  // all incoming traffic goes to serloader 
  wire serloader_rx = GPIO_3;
  wire serloader_tx;
  assign GPIO_2 = serloader_tx; 
  wire tms9902_rx = slave_rx_i;
  wire tms9902_tx;
  assign slave_tx_o = tms9902_tx;
  // Serial port assignments end

  // PS2 keyboard - if there is signals from either port go with that.
  // The port should be pulled up, so I guess and operation should do the trick.
  wire ps2clk = usb_fpga_dp & ps2_clk2;
  wire ps2dat = usb_fpga_dn & ps2_data2;

  wire [3:0] LED;
  wire vde;

  // assign n_led1 = LED[3];  // stuck signal
  // Let's debug with n_led1. Implement a counter which blinks it.
  reg [23:0] blink_counter = 0;

  // Running blink counter from clk_25mhz works.
  // Running blink counter from clk works.
  always @(posedge pll_125mhz) begin // was using clk
    blink_counter <= blink_counter + 1;
  end
  // assign n_led1 = blink_counter[23];  // blinker
  assign n_led1 = ~GPIO_3; // Show receive activity on serial port

  wire pin_cs, pin_sdin, pin_sclk, pin_d_cn, pin_resn, pin_vccen, pin_pmoden;
  sys #(0,0) ti994a(
    .clk(clk), 
    .LED(LED), 
    .tms9902_tx(tms9902_tx), 
    .tms9902_rx(tms9902_rx),
    .RAMOE(RAMOE), 
    .RAMWE(RAMWE), 
    .RAMCS(RAMCS), 
    .RAMLB(RAMLB), 
    .RAMUB(RAMUB),
    .ADR(ADR), 
    .sram_pins_din(sram_pins_din), 
    .sram_pins_dout(sram_pins_dout),
    .sram_pins_drive(sram_pins_drive),
    .memory_busy(memory_busy),
    .use_memory_busy(use_memory_busy),
    .addr_strobe(addr_strobe),
    .red(red), 
    .green(green), 
    .blue(blue), 
    .hsync(hsync), 
    .vsync(vsync),
    .cpu_reset_switch_n(R_btn_resetn),
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
    .vde(vde), // video display enable signal
    .ps2clk(ps2clk), 
    .ps2dat(ps2dat)
  );

  wire [7:0] red_out   = { red,   4'h0 };
  wire [7:0] green_out = { green, 4'h0 };
  wire [7:0] blue_out  = { blue,  4'h0 };

  wire hsyn = ~hsync;
  wire vsyn = ~vsync;
  
  // TMDS differential pairs - 2 bits each
  wire [1:0] tmds_c, tmds_r, tmds_g, tmds_b;
  
  DVI_out out(
    .pixclk(pll_25mhz),
    .pixclk_x5(pll_125mhz),
    .red(red_out),
    .green(green_out),
    .blue(blue_out),
    .vde(vde),
    .hSync(hsyn),
    .vSync(vsyn),
    .tmds_c(tmds_c),
    .tmds_r(tmds_r),
    .tmds_g(tmds_g),
    .tmds_b(tmds_b)
  );
  
  // Map TMDS pairs to LVDS differential outputs
  // Use ODDRX1F for DDR output with proper 1-bit reset and connect only positive outputs
  // The LVDS buffers in the pin constraints will create the differential pairs
  ODDRX1F ddr0_clock (.D0(tmds_c[0]), .D1(tmds_c[1]), .Q(LVDS_ck[0]), .SCLK(pll_125mhz), .RST(1'b0));
  ODDRX1F ddr0_red   (.D0(tmds_r[0]), .D1(tmds_r[1]), .Q(LVDS_Red[0]), .SCLK(pll_125mhz), .RST(1'b0));
  ODDRX1F ddr0_green (.D0(tmds_g[0]), .D1(tmds_g[1]), .Q(LVDS_Green[0]), .SCLK(pll_125mhz), .RST(1'b0));
  ODDRX1F ddr0_blue  (.D0(tmds_b[0]), .D1(tmds_b[1]), .Q(LVDS_Blue[0]), .SCLK(pll_125mhz), .RST(1'b0));


endmodule

module clk_25_250_125_25(
  input clki, 
  output clks1,
  output clks2,
  output locked,
  output clko
);
  wire clkfb;
  wire clkos;
  wire clkop;
  (* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
  EHXPLLL #(
      .PLLRST_ENA("DISABLED"),
      .INTFB_WAKE("DISABLED"),
      .STDBY_ENABLE("DISABLED"),
      .DPHASE_SOURCE("DISABLED"),
      .CLKOP_FPHASE(0),
      .CLKOP_CPHASE(0),
      .OUTDIVIDER_MUXA("DIVA"),
      .CLKOP_ENABLE("ENABLED"),
      .CLKOP_DIV(2),
      .CLKOS_ENABLE("ENABLED"),
      .CLKOS_DIV(4),
      .CLKOS_CPHASE(0),
      .CLKOS_FPHASE(0),
      .CLKOS2_ENABLE("ENABLED"),
      .CLKOS2_DIV(20),
      .CLKOS2_CPHASE(0),
      .CLKOS2_FPHASE(0),
      .CLKFB_DIV(10),
      .CLKI_DIV(1),
      .FEEDBK_PATH("INT_OP")
    ) pll_i (
      .CLKI(clki),
      .CLKFB(clkfb),
      .CLKINTFB(clkfb),
      .CLKOP(clkop),
      .CLKOS(clks1),
      .CLKOS2(clks2),
      .RST(1'b0),
      .STDBY(1'b0),
      .PHASESEL0(1'b0),
      .PHASESEL1(1'b0),
      .PHASEDIR(1'b0),
      .PHASESTEP(1'b0),
      .PLLWAKESYNC(1'b0),
      .ENCLKOP(1'b0),
      .LOCK(locked)
    );
  assign clko = clkop;
endmodule
