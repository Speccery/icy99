# Erik Piehl (C) 2020
# Makefile for icy99 FPGA system

ifdef APIO
YOSYS = ~/.apio/packages/toolchain-yosys/bin/yosys
NEXTPNR_ECP5 = ~/.apio/packages/toolchain-ecp5/bin/nextpnr-ecp5
NEXTPNR_ICE40 = ~/.apio/packages/toolchain-ice40/bin/nextpnr-ice40
ECPPACK = ~/.apio/packages/toolchain-ecp5/bin/ecppack
ICEPACK_ICE40 = ~/.apio/packages/toolchain-ice40/bin/icepack
else
YOSYS = yosys
NEXTPNR_ECP5 = nextpnr-ecp5
NEXTPNR_ICE40 = nextpnr-ice40
ECPPACK = ecppack
ICEPACK_ICE40 = icepack
endif


# TI-99/4A FGPA implementation for various FPGA boards.
VERILOGS = src/ram2.v \
 src/sys.v src/rom.v \
 src/tms9900.v src/alu9900.v src/tms9902.v \
 src/erik_pll.v src/tms9918.v src/vga_sync.v \
 src/xmemctrl.v src/gromext.v \
 src/serloader.v src/serial_rx.v \
 src/serial_tx.v src/spi_slave.v src/tms9901.v \
 src/lcd_sys.v lcd/pmodoledrgb_controller.v lcd/ram_source.v \
 src/dualport_par.v src/ps2kb.v \
 src/tms9919.v

TIPI_VERILOGS = \
	tipi/crubits.v \
	tipi/shift_pload_sout.v \
	tipi/tipi_module.v \
	tipi/mux2_8bit.v \
	tipi/shift_sin_pout.v \
	tipi/tristate_8bit.v 

all: ti994a_ulx3s.bit

erik9900.blif: $(VERILOGS) top_blackice2.v blackice-ii.pcf Makefile 
	yosys  -q -DEXTERNAL_VRAM -p "synth_ice40 -top top_blackice2 -abc2 -blif erik9900.blif" $(VERILOGS) top_blackice2.v

erik9900.txt: erik9900.blif
	arachne-pnr -r -d 8k -P tq144:4k -p blackice-ii.pcf erik9900.blif -o erik9900.txt
	#skipped:# icebox_explain erik9900.txt > erik9900.ex

erik9900.bin: erik9900.txt
	icepack erik9900.txt erik9900.bin
	# icemulti -p0 erik9900.bin > erik9900.bin && rm j1a0.bin

# NEXTPNR ROUTING
next9900.json: $(VERILOGS) top_blackice2.v blackice-ii.pcf Makefile 
	$(YOSYS)  -q  -DEXTERNAL_VRAM -p 'synth_ice40 -json next9900.json -top top_blackice2 -blif next9900.blif' $(VERILOGS) top_blackice2.v

next9900.asc: next9900.json 
	$(NEXTPNR_ICE40) --hx8k --asc next9900.asc --json next9900.json --package tq144:4k --pcf blackice-ii.pcf --pcf-allow-unconstrained

next9900.bin: next9900.asc
	$(ICEPACK_ICE40) next9900.asc next9900.bin


# ECP5 FleaFPGA Ohm
flea.json: $(VERILOGS) top_flea.v src/dvi.v Makefile 
	$(YOSYS) -q -p "synth_ecp5 -json flea.json" src/dvi.v top_flea.v rom16.v $(VERILOGS)


flea_ohm.bit: Makefile flea.json
	$(NEXTPNR_ECP5) --25k --package CABGA381 --json flea.json --lpf flea_ohm.lpf --textcfg flea_out.cfg	
	$(ECPPACK)  flea_out.cfg flea_ohm.bit

# ECP5 ULX3S ECP5-85 board
VERILOGS_ULX3S = \
 top_ulx3s.v \
 src/ecp5pll.sv \
 src/sdram_cortex.v \
 src/dvi.v \
 src/vga2dvid.v \
 src/tmds_encoder.v \
 osd/osd.v \
 osd/spi_osd.v \
 osd/spi_ram_btn.v \
 osd/spirw_slave_v.v 
 
ti994a_ulx3s.json: $(VERILOGS) $(VERILOGS_ULX3S) $(TIPI_VERILOGS) Makefile 
	$(YOSYS) -q -DUSE_SDRAM -DPAD_IN_SDRAM -DLCD_SUPPORT \
		-p "synth_ecp5 -abc9 -json ti994a_ulx3s.json" \
		$(VERILOGS_ULX3S) rom16.v $(VERILOGS) $(TIPI_VERILOGS)

ti994a_ulx3s.bit: Makefile ti994a_ulx3s.json
	$(NEXTPNR_ECP5) --85k --package CABGA381 --json ti994a_ulx3s.json --lpf ulx3s.lpf --textcfg ti994a_ulx3s_out.cfg	
	$(ECPPACK) --compress ti994a_ulx3s_out.cfg ti994a_ulx3s.bit


clean:
	rm -f erik9900.blif erik9900.txt erik9900.bin next9900.bin next9900.asc next9900.json 
	rm -f flea.json flea_ohm.bit 
	rm -f ti994a_ulx3s.bit ti994a_ulx3s.json

.PHONY: clean
.PHONY: erik9900
