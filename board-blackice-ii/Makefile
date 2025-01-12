# Erik Piehl (C) 2025
# Based on the makefile from 2020 :) 
# Makefile for icy99 FPGA system for the blackice-ii board.

YOSYSPATH ?= /Users/perik/.apio/packages/tools-oss-cad-suite/bin
$(info YOSYSPATH is set to $(YOSYSPATH))

YOSYS 			= $(YOSYSPATH)/yosys
NEXTPNR_ECP5 	= $(YOSYSPATH)/nextpnr-ecp5
NEXTPNR_ICE40 	= $(YOSYSPATH)/nextpnr-ice40
ECPPACK 		= $(YOSYSPATH)/ecppack
ICEPACK_ICE40 	= $(YOSYSPATH)/icepack

HOSTNAME := $(shell hostname)

# TI-99/4A FGPA implementation for various FPGA boards.
VERILOGS = \
	../src/ram2.v \
	../src/sys.v \
	../src/rom.v \
	../src/tms9900.v \
	../src/alu9900.v \
	../src/tms9902.v \
	../src/erik_pll.v \
	../src/tms9918.v \
	../src/vga_sync.v \
	../src/xmemctrl.v \
	../src/gromext.v \
	../src/serloader.v \
	../src/serial_rx.v \
	../src/serial_tx.v \
	../src/spi_slave.v \
	../src/tms9901.v \
	../src/dualport_par.v \
	../src/ps2kb.v \
	../src/tms9919.v \
	../src/pager612.v

TIPI_VERILOGS = \
	../tipi/crubits.v \
	../tipi/shift_pload_sout.v \
	../tipi/tipi_module.v \
	../tipi/mux2_8bit.v \
	../tipi/shift_sin_pout.v \
	../tipi/tristate_8bit.v 

LCD_VERILOGS = \
	../src/lcd_sys.v \
	../lcd/pmodoledrgb_controller.v \
	../lcd/ram_source.v

# all: $(HOSTNAME)/ti994a_ulx3s.bit
all: $(HOSTNAME)/next9900.bin

# NEXTPNR ROUTING; Blackice II
$(HOSTNAME)/next9900.json: $(VERILOGS) top_blackice2.v blackice-ii.pcf Makefile 
	@mkdir -p $(@D)
	$(YOSYS)  -q  -DEXTERNAL_VRAM -p 'synth_ice40 -json $@ -top top_blackice2 -blif $(HOSTNAME)/next9900.blif' $(VERILOGS) top_blackice2.v

$(HOSTNAME)/next9900.asc: $(HOSTNAME)/next9900.json 
	$(NEXTPNR_ICE40) --hx8k --asc $@ --json $< --package tq144:4k --pcf blackice-ii.pcf --pcf-allow-unconstrained

$(HOSTNAME)/next9900.bin: $(HOSTNAME)/next9900.asc
	$(ICEPACK_ICE40) $< $@

loadroms:
	../tools/serialtool /dev/cu.usbserial-21230 -w ../roms/994aROM.Bin 0 50000
	../tools/serialtool /dev/cu.usbserial-21230 -w ../roms/994agROM.Bin 10000 50000

reset:
	../tools/serialtool /dev/cu.usbserial-21230 -p 1000008 FC
	../tools/serialtool /dev/cu.usbserial-21230 -p 1000008 FF

enter1:
	../tools/serialtool /dev/cu.usbserial-21230 -p 1000005 ef
	../tools/serialtool /dev/cu.usbserial-21230 -p 1000005 ff

# ECP5 FleaFPGA Ohm
flea.json: $(VERILOGS) top_flea.v ../src/dvi.v Makefile 
	$(YOSYS) -q -p "synth_ecp5 -json flea.json" ../src/dvi.v top_flea.v rom16.v $(VERILOGS)


flea_ohm.bit: Makefile flea.json
	$(NEXTPNR_ECP5) --25k --package CABGA381 --json flea.json --lpf flea_ohm.lpf --textcfg flea_out.cfg	
	$(ECPPACK)  flea_out.cfg flea_ohm.bit

# ECP5 ULX3S ECP5-85 board
VERILOGS_ULX3S = \
 top_ulx3s.v \
 ../src/ecp5pll.sv \
 ../src/sdram_cortex.v \
 ../src/dvi.v \
 ../src/vga2dvid.v \
 ../src/tmds_encoder.v \
 osd/osd.v \
 osd/spi_osd.v \
 osd/spi_ram_btn.v \
 osd/spirw_slave_v.v 
 
$(HOSTNAME)/ti994a_ulx3s.json: $(VERILOGS) $(VERILOGS_ULX3S) $(TIPI_VERILOGS) $(LCD_VERILOGS) Makefile 
	@mkdir -p $(@D)
	$(YOSYS) \
		-p "read -sv $(VERILOGS_ULX3S) rom16.v $(VERILOGS) $(TIPI_VERILOGS)" \
		-p "hierarchy -top top_ulx3s" \
		-p "synth_ecp5 -abc9 -json $@" 
	# these moved to top_ulx3s.v
	#  -DTIPI_SUPPORT -DLCD_SUPPORT -q -DUSE_SDRAM 


$(HOSTNAME)/ti994a_ulx3s.bit: Makefile $(HOSTNAME)/ti994a_ulx3s.json
	$(NEXTPNR_ECP5) --85k --package CABGA381 --json $(HOSTNAME)/ti994a_ulx3s.json --lpf ulx3s.lpf --textcfg $(HOSTNAME)/ti994a_ulx3s_out.cfg 
	# --lpf-allow-unconstrained
	# $(ECPPACK) --compress $(HOSTNAME)/ti994a_ulx3s_out.cfg $@
	$(ECPPACK) --compress --freq 62.0 $(HOSTNAME)/ti994a_ulx3s_out.cfg $@
	

clean:
	# Blackice II
	rm -f $(HOSTNAME)/next9900.bin $(HOSTNAME)/next9900.asc $(HOSTNAME)/next9900.json 
	# Flea
	rm -f flea.json flea_ohm.bit 
	# ULX3S
	rm -f $(HOSTNAME)/ti994a_ulx3s.bit $(HOSTNAME)/ti994a_ulx3s.json

.PHONY: clean
.PHONY: erik9900
