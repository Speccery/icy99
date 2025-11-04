# Erik Piehl (C) 2025
# Based on the makefile from 2020 :) 
# Makefile for icy99 FPGA system for the blackice-ii board.

YOSYSPATH ?= $(HOME)/.apio/packages/tools-oss-cad-suite/bin
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

all: $(HOSTNAME)/flea_ohm.bit

loadroms:
	../tools/serialtool -p 1000008 -w ../roms/994aROM.Bin 0 50000
	../tools/serialtool -p 1000008 -w ../roms/994agROM.Bin 10000 50000

reset:
	../tools/serialtool -p 1000008 FC
	../tools/serialtool -p 1000008 FF

enter1:
	../tools/serialtool -p 1000005 ef
	../tools/serialtool -p 1000005 ff

# ECP5 FleaFPGA Ohm
$(HOSTNAME)/flea.json: $(VERILOGS) top_flea.v ../src/dvi.v ecp5pll.sv Makefile 
	@mkdir -p $(@D)
	@echo "Running Yosys synthesis..."
	@$(YOSYS) -q -p "synth_ecp5 -json $@" ecp5pll.sv ../src/dvi.v top_flea.v ../rom16.v $(VERILOGS) 
	# | grep -E "(Number of cells|Max frequency)"

$(HOSTNAME)/flea_ohm.bit: Makefile $(HOSTNAME)/flea.json
	@echo "Running place and route..."
	@$(NEXTPNR_ECP5) --25k --package CABGA381 --json $(HOSTNAME)/flea.json --lpf flea_ohm.lpf --textcfg $(HOSTNAME)/flea_out.cfg --timing-allow-fail 2>&1 
	#| grep -E "(Info: Device utilisation|Info: Placed|Info: Routed|Max frequency for clock|ERROR|Warning)"
	@rm -f $(HOSTNAME)/flea_ohm.bit
	@echo "Generating bitstream..."
	@$(ECPPACK) $(HOSTNAME)/flea_out.cfg $(HOSTNAME)/flea_ohm.bit

# SDRAM targets
sdram: $(HOSTNAME)/flea_ohm_sdram.bit

$(HOSTNAME)/flea_sdram.json: $(VERILOGS) top_flea.v ../src/dvi.v ../src/sdram_cortex.v ecp5pll.sv Makefile 
	@mkdir -p $(@D)
	@echo "Running Yosys synthesis (SDRAM)..."
	@$(YOSYS) -q -p "synth_ecp5 -json $@" -DUSE_SDRAM ecp5pll.sv ../src/dvi.v top_flea.v ../rom16.v $(VERILOGS) ../src/sdram_cortex.v 
	# | grep -E "(Number of cells|Max frequency)"

$(HOSTNAME)/flea_ohm_sdram.bit: Makefile $(HOSTNAME)/flea_sdram.json
	@echo "Running place and route (SDRAM)..."
	@$(NEXTPNR_ECP5) --25k --package CABGA381 --json $(HOSTNAME)/flea_sdram.json --lpf flea_ohm.lpf --textcfg $(HOSTNAME)/flea_sdram_out.cfg 2>&1
	# | grep -E "(Info: Device utilisation|Info: Placed|Info: Routed|Max frequency for clock|ERROR|Warning)"
	@rm -f $(HOSTNAME)/flea_ohm_sdram.bit
	@echo "Generating bitstream (SDRAM)..."
	@$(ECPPACK) $(HOSTNAME)/flea_sdram_out.cfg $(HOSTNAME)/flea_ohm_sdram.bit

clean:
	# Flea
	rm -f $(HOSTNAME)/flea.json $(HOSTNAME)/flea_ohm.bit
	rm -f $(HOSTNAME)/flea_out.cfg
	# Flea SDRAM
	rm -f $(HOSTNAME)/flea_sdram.json $(HOSTNAME)/flea_ohm_sdram.bit
	rm -f $(HOSTNAME)/flea_sdram_out.cfg

.PHONY: clean
.PHONY: erik9900
.PHONY: sdram
.PHONY: verbose

# Verbose targets for debugging - show full output
verbose: $(HOSTNAME)/flea_ohm_verbose.bit

$(HOSTNAME)/flea_ohm_verbose.bit: Makefile $(HOSTNAME)/flea.json
	$(NEXTPNR_ECP5) --25k --package CABGA381 --json $(HOSTNAME)/flea.json --lpf flea_ohm.lpf --textcfg $(HOSTNAME)/flea_out.cfg
	rm -f $(HOSTNAME)/flea_ohm_verbose.bit
	$(ECPPACK) $(HOSTNAME)/flea_out.cfg $(HOSTNAME)/flea_ohm_verbose.bit
	cp $(HOSTNAME)/flea_ohm_verbose.bit $(HOSTNAME)/flea_ohm.bit
