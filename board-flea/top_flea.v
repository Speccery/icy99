// top_flea.v 
// EP (C) 2019
// This is the toplevel for FleaFPGA Ohm board.
// It instanciates the platform neutral sys.v which
// implements the TI-99/4A.

module fleatop
(
  input  wire clk_25mhz,
  output wire [3:0] gpdi_dp, gpdi_dn,
  output wire PS2_enable,
  input  wire usb_fpga_dp, usb_fpga_dn,
  output wire Dram_CKE,
  output wire Dram_n_cs,
  output wire mmc_n_cs,
  output wire n_led1,
  output wire slave_tx_o,
  input  wire slave_rx_i,
  output wire GPIO_2,   // pin 3 on Raspi header
  input  wire GPIO_3,   // pin 5 on Raspi header
  input  wire ps2_clk2, 
  input  wire ps2_data2
);

  // Housekeeping logic for unwanted peripherals on FleaFPGA Ohm board goes here..
  assign Dram_CKE = 1'b 0;    // DRAM Clock disable.
  assign Dram_n_cs = 1'b 1;   // DRAM Chip disable.
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
  wire [17:0] ADR;
  // Need to populate memory map with internal SRAM:
  // 8K  at 00000 system ROM
  // -- 8K  at 02000 low memory expansion
  // 1K  at 08000 scratch pad
  // -- 24K at 0A000 high memory expansion
  // 32K at 10000 GROM space (system+8K for module)
  // 16K at 20000 VRAM
  // 16K at 40000 cartridge RAM
  // without 32K RAM expansion this amounts to 73K.
  // 5 blocks in total.

  // Since we need byte addressability we need 10 blocks. 
  // For the select signals, note that ADR has 16-bit word address, not byte address.
  // Thus ADR[14] is CPU A15.
/*  
  wire rom_sel = !RAMCS && (!RAMOE || !RAMWE) && (ADR[17:12] == 6'b000_000);    //  8K @ 00000
  wire pad_sel = !RAMCS && (!RAMOE || !RAMWE) && (ADR[17: 9] == 9'b000_1000_00);//  1K @ 08000 
  wire gro_sel = !RAMCS && (!RAMOE || !RAMWE) && (ADR[17:14] == 4'b001_0);      // 32K @ 10000
  wire vra_sel = !RAMCS && (!RAMOE || !RAMWE) && (ADR[17:13] == 5'b010_00);     // 16K @ 20000
  wire car_sel = !RAMCS && (!RAMOE || !RAMWE) && (ADR[17:13] == 5'b100_00);     // 16K @ 40000
*/
  wire rom_sel = (ADR[17:12] == 6'b000_000);    //  8K @ 00000
  wire pad_sel = (ADR[17: 9] == 9'b000_1000_00);//  1K @ 08000 
  wire gro_sel = (ADR[17:14] == 4'b001_0);      // 32K @ 10000
  wire vra_sel = (ADR[17:13] == 5'b010_00);     // 16K @ 20000
  wire car_sel = (ADR[17:13] == 5'b100_00);     // 16K @ 40000
  // Temporarily assign to top of 64K RAM to be able to run EVMBUG
  // wire car_sel = (ADR[17:13] == 5'b000_11);     // 16K @ 40000
 
  // ROM
  wire [7:0] rom_out_lo, rom_out_hi;
  rom16 #(16, 12, 8192/2, "roms/994arom.mem") sysrom(pll_125mhz, ADR[11:0], { rom_out_hi, rom_out_lo} );
  /*
  wire rom_we_lo = rom_sel && !RAMLB && !RAMWE;
  wire rom_we_hi = rom_sel && !RAMUB && !RAMWE;
  dualport_par #(8,12) rom_lb(pll_125mhz, rom_we_lo, ADR[11:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[11:0], rom_out_lo);
  dualport_par #(8,12) rom_hb(pll_125mhz, rom_we_hi, ADR[11:0], sram_pins_dout[15:8], pll_125mhz, ADR[11:0], rom_out_hi);
  */
  // SCRATCHPAD (here 1K not 256bytes)
  wire pad_we_lo = pad_sel && !RAMLB && !RAMWE;
  wire pad_we_hi = pad_sel && !RAMUB && !RAMWE;
  wire [7:0] pad_out_lo, pad_out_hi;
  dualport_par #(8, 9) pad_lb(pll_125mhz, pad_we_lo, ADR[ 8:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[ 8:0], pad_out_lo);
  dualport_par #(8, 9) pad_hb(pll_125mhz, pad_we_hi, ADR[ 8:0], sram_pins_dout[15:8], pll_125mhz, ADR[ 8:0], pad_out_hi);
  // GROM 32K
  wire [7:0] gro_out_lo, gro_out_hi;
  rom16 #(16,14,24576/2,"roms/994agrom.mem") sysgrom(pll_125mhz, ADR[13:0], {gro_out_hi, gro_out_lo } );
  /*
  wire gro_we_lo = gro_sel && !RAMLB && !RAMWE;
  wire gro_we_hi = gro_sel && !RAMUB && !RAMWE;
  dualport_par #(8,14) gro_lb(pll_125mhz, gro_we_lo, ADR[13:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[13:0], gro_out_lo);
  dualport_par #(8,14) gro_hb(pll_125mhz, gro_we_hi, ADR[13:0], sram_pins_dout[15:8], pll_125mhz, ADR[13:0], gro_out_hi);
  */
  // VRAM 16K
  wire vra_we_lo = vra_sel && !RAMLB && !RAMWE;
  wire vra_we_hi = vra_sel && !RAMUB && !RAMWE;
  wire [7:0] vra_out_lo, vra_out_hi;
  dualport_par #(8,13) vra_lb(pll_125mhz, vra_we_lo, ADR[12:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[12:0], vra_out_lo);
  dualport_par #(8,13) vra_hb(pll_125mhz, vra_we_hi, ADR[12:0], sram_pins_dout[15:8], pll_125mhz, ADR[12:0], vra_out_hi);
  // CARTRIDGE (paged, here 2 pages total 16K)
  wire car_we_lo = car_sel && !RAMLB && !RAMWE;
  wire car_we_hi = car_sel && !RAMUB && !RAMWE;
  wire [7:0] car_out_lo, car_out_hi;
  dualport_par #(8,13) car_lb(pll_125mhz, car_we_lo, ADR[12:0], sram_pins_dout[ 7:0], pll_125mhz, ADR[12:0], car_out_lo);
  dualport_par #(8,13) car_hb(pll_125mhz, car_we_hi, ADR[12:0], sram_pins_dout[15:8], pll_125mhz, ADR[12:0], car_out_hi);

  // Data input multiplexer
  assign sram_pins_din = 
    rom_sel ? { rom_out_hi, rom_out_lo } :
    pad_sel ? { pad_out_hi, pad_out_lo } :
    gro_sel ? { gro_out_hi, gro_out_lo } :
    vra_sel ? { vra_out_hi, vra_out_lo } :
    car_sel ? { car_out_hi, car_out_lo } :
    16'h0000;

  // VGA
  wire [3:0] red, green, blue;
  wire hsync, vsync;

//-------------------------------------------------------------------

  wire clk = pll_25mhz;

  // need to implement SRAM here

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

  assign n_led1 = LED[3];  // stuck signal

  wire pin_cs, pin_sdin, pin_sclk, pin_d_cn, pin_resn, pin_vccen, pin_pmoden;
  sys ti994a(clk, LED, 
    tms9902_tx, tms9902_rx,
    RAMOE, RAMWE, RAMCS, RAMLB, RAMUB,
    ADR, 
    sram_pins_din, sram_pins_dout,
    sram_pins_drive,
    red, green, blue, hsync, vsync,
    1'b1,  // cpu_reset_switch_n
    // LCD signals
    pin_cs, pin_sdin, pin_sclk, pin_d_cn, pin_resn, pin_vccen, pin_pmoden,
    // bootloader UART
    serloader_tx, serloader_rx,
    vde, // video display enable signal
    ps2clk, ps2dat
  );

  wire [7:0] red_out   = { red,   4'h0 };
  wire [7:0] green_out = { green, 4'h0 };
  wire [7:0] blue_out  = { blue,  4'h0 };

  wire hsyn = ~hsync;
  wire vsyn = ~vsync;
  DVI_out out(pll_25mhz, pll_125mhz, red_out, green_out, blue_out, 
    vde, hsyn, vsyn, gpdi_dp, gpdi_dn);

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
